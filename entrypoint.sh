#!/bin/bash
set -e

# Environment variables with defaults
export CONFIG_DIR=${CONFIG_DIR:-"/config"}
export COMPONENTS_FILE=${COMPONENTS_FILE:-"${CONFIG_DIR}/ham/components.json"}
export LOCK_FILE=${LOCK_FILE:-"${CONFIG_DIR}/ham/components.json.lock"}

# Ensure necessary directories exist
mkdir -p "${CONFIG_DIR}/ham"
mkdir -p "${CONFIG_DIR}/www"
mkdir -p "${CONFIG_DIR}/custom_components"

# Create lock file if it doesn't exist
if [ ! -f "${LOCK_FILE}" ]; then
  echo "{}" > "${LOCK_FILE}"
fi

# Function to get filename from URL
get_filename_from_url() {
  local url=$1
  basename "$url"
}

# Function to detect file type from URL
detect_file_type() {
  local URL=$1
  if [[ "$URL" =~ \.git$ ]] || [[ "$URL" =~ ^git@ ]] || [[ "$URL" =~ ^https://github.com/ ]]; then
    echo "git"
  elif [[ "$URL" =~ \.(js|css|json)$ ]]; then
    echo "file"
  elif [[ "$URL" =~ \.zip$ ]]; then
    echo "zip"
  else
    echo "Error: Unable to detect file type from URL: $URL" >&2
    return 1
  fi
}

# Function to handle git repository cloning/updating
handle_git_download() {
  local NAME=$1
  local URL=$2
  local VERSION=$3
  local INSTALL_TYPE=$4
  local REPO_PATH=$5
  local TARGET_DIR="${CONFIG_DIR}/${INSTALL_TYPE}"
  local TEMP_DIR=$(mktemp -d)

  echo "Cloning/updating git repository for $NAME..."

  # Clone the repository
  if ! git clone --depth 1 -b "$VERSION" "$URL" "$TEMP_DIR/repo"; then
    echo "Error: Failed to clone repository $URL" >&2
    rm -rf "$TEMP_DIR"
    return 1
  fi

  local SOURCE_DIR="$TEMP_DIR/repo"
  if [ -n "$REPO_PATH" ]; then
    SOURCE_DIR="$TEMP_DIR/repo/$REPO_PATH"
  fi

  # Debug output
  echo "Checking source directory: $SOURCE_DIR"
  echo "Repository contents:"
  ls -R "$REPO_DIR" || echo "Failed to list repository contents"

  if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' not found in repository" >&2
    rm -rf "$TEMP_DIR"
    return 1
  fi

  local FINAL_TARGET="${TARGET_DIR}/${NAME}"

  # Clean up existing directory if it exists
  if [ -d "$FINAL_TARGET" ]; then
    rm -rf "$FINAL_TARGET"
  fi

  # Create target directory and copy files
  mkdir -p "$FINAL_TARGET"
  cp -r "$SOURCE_DIR"/* "$FINAL_TARGET"

  rm -rf "$TEMP_DIR"
  return 0
}

# Function to handle file downloads and processing based on type
handle_component_download() {
  local NAME=$1
  local URL=$2
  local TYPE=$3
  local INSTALL_TYPE=$4
  local REPO_PATH=$5
  local TARGET_DIR="${CONFIG_DIR}/${INSTALL_TYPE}"
  local TEMP_DIR=$(mktemp -d)

  case $TYPE in
    "git")
      handle_git_download "$NAME" "$URL" "$VERSION" "$INSTALL_TYPE" "$REPO_PATH"
      return $?
      ;;
    "file")
      if [ "$INSTALL_TYPE" != "www" ]; then
        echo "Error: Single files can only be installed to www directory" >&2
        return 1
      fi
      local FILENAME=$(get_filename_from_url "$URL")
      wget -O "${TARGET_DIR}/${FILENAME}" "$URL" || return 1
      ;;
    "zip")
      local ZIP_FILE="${TEMP_DIR}/${NAME}.zip"
      wget -O "$ZIP_FILE" "$URL" || return 1

      local EXTRACT_PATH="${TARGET_DIR}/${NAME}"

      # Clean up existing directory if it exists
      if [ -d "$EXTRACT_PATH" ]; then
        rm -rf "$EXTRACT_PATH"
      fi

      # Create extraction directory and extract
      mkdir -p "$EXTRACT_PATH"
      unzip -o "$ZIP_FILE" -d "$EXTRACT_PATH"
      ;;
    *)
      echo "Unsupported file type: $TYPE" >&2
      return 1
      ;;
  esac

  rm -rf "${TEMP_DIR}"
  return 0
}

# Generate lovelace_resources.yaml
generate_lovelace_resources() {
  echo "mode: yaml" > "${CONFIG_DIR}/lovelace_resources.yaml"
  echo "resources:" >> "${CONFIG_DIR}/lovelace_resources.yaml"

  jq -c '.[] | select(.install_type == "www")' "${COMPONENTS_FILE}" | while read -r component; do
    local NAME=$(echo "$component" | jq -r '.name')
    local TYPE=$(echo "$component" | jq -r '.type // "null"')
    local URL=$(echo "$component" | jq -r '.url')
    local VERSION=$(echo "$component" | jq -r '.version')
    local RESOURCE=$(echo "$component" | jq -r '.lovelace_resource // ""')

    # For file type, use filename from URL if lovelace_resource is not specified
    if [ -z "$RESOURCE" ] && [ "$TYPE" = "file" ]; then
      RESOURCE=$(get_filename_from_url "$URL")
    fi

    if [ -n "$RESOURCE" ]; then
      local RESOURCE_PATH="${CONFIG_DIR}/www/${RESOURCE}"
      if [ -f "$RESOURCE_PATH" ]; then
        echo "  - url: /local/${RESOURCE}?v=${VERSION}" >> "${CONFIG_DIR}/lovelace_resources.yaml"
        echo "    type: module" >> "${CONFIG_DIR}/lovelace_resources.yaml"
      fi
    fi
  done
}

# Validate component configuration
validate_component() {
  local NAME=$1
  local INSTALL_TYPE=$2
  local TYPE=$3
  local LOVELACE_RESOURCE=$4

  if [ "$INSTALL_TYPE" != "www" ] && [ "$INSTALL_TYPE" != "custom_components" ]; then
    echo "Error: Invalid install_type for $NAME. Must be 'www' or 'custom_components'" >&2
    return 1
  fi

  if [ "$INSTALL_TYPE" = "www" ] && [ "$TYPE" != "file" ] && [ -z "$LOVELACE_RESOURCE" ]; then
    echo "Error: Components with install_type 'www' must specify lovelace_resource unless type is 'file' ($NAME)" >&2
    return 1
  fi

  return 0
}

# Main function to process components
process_components() {
  if [ ! -f "${COMPONENTS_FILE}" ]; then
    echo "Error: components.json not found in expected location" >&2
    exit 1
  fi

  jq -c '.[]' "${COMPONENTS_FILE}" | while read -r component; do
    NAME=$(echo "$component" | jq -r '.name')
    URL=$(echo "$component" | jq -r '.url')
    TYPE=$(echo "$component" | jq -r '.type // "null"')
    VERSION=$(echo "$component" | jq -r '.version')
    INSTALL_TYPE=$(echo "$component" | jq -r '.install_type // "www"')
    LOVELACE_RESOURCE=$(echo "$component" | jq -r '.lovelace_resource // ""')
    REPO_PATH=$(echo "$component" | jq -r '.repo_path // ""')

    # Auto-detect type if not specified
    if [ "$TYPE" = "null" ]; then
      TYPE=$(detect_file_type "$URL") || continue
    fi

    # Validate component configuration
    if ! validate_component "$NAME" "$INSTALL_TYPE" "$TYPE" "$LOVELACE_RESOURCE"; then
      continue
    fi

    CACHED_VERSION=$(jq -r ".[\"$NAME\"]" "${LOCK_FILE}")

    if [ "$CACHED_VERSION" = "null" ] || [ "$CACHED_VERSION" != "$VERSION" ]; then
      echo "Downloading $NAME (version $VERSION) from $URL to $INSTALL_TYPE..."
      if handle_component_download "$NAME" "$URL" "$TYPE" "$INSTALL_TYPE" "$REPO_PATH"; then
        # Update lock file with just the version
        jq --arg name "$NAME" --arg version "$VERSION" \
           '.[$name] = $version' "${LOCK_FILE}" > "${LOCK_FILE}.tmp" && \
        mv "${LOCK_FILE}.tmp" "${LOCK_FILE}"
      else
        echo "Failed to download $NAME" >&2
      fi
    else
      echo "$NAME version $VERSION is up to date, skipping download..."
    fi
  done
}

# Main execution
main() {
  echo "Starting HAM..."
  process_components
  generate_lovelace_resources
  echo "Lovelace resources configuration generated based on components.json."
}

# Run main function if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
