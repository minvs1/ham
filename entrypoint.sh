#!/bin/bash
set -e

# Environment variables with defaults
export CONFIG_DIR=${CONFIG_DIR:-"/config"}
export COMPONENTS_FILE=${COMPONENTS_FILE:-"${CONFIG_DIR}/www/components.json"}
export LOCK_FILE=${LOCK_FILE:-"${CONFIG_DIR}/www/components.json.lock"}
export HACS_VERSION=${HACS_VERSION:-"1.32.1"}

# Ensure necessary directories exist
mkdir -p "${CONFIG_DIR}/www"

# Create lock file if it doesn't exist
if [ ! -f "${LOCK_FILE}" ]; then
  echo "{}" > "${LOCK_FILE}"
fi

# Define the version comparison function
version_gt() {
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}

# Function to calculate SHA256 of a file
calculate_sha() {
  sha256sum "$1" | awk '{ print $1 }'
}

# Function to get zip filename without extension
get_zip_name() {
  local zipfile=$1
  basename "$zipfile" .zip
}

# Function to detect file type from URL
detect_file_type() {
  local URL=$1
  if [[ "$URL" =~ \.zip$ ]]; then
    echo "zip"
  elif [[ "$URL" =~ \.js$ ]]; then
    echo "js"
  else
    echo "Error: Unable to detect file type from URL: $URL" >&2
    return 1
  fi
}

# Function to handle file downloads and processing based on type
handle_component_download() {
  local NAME=$1
  local URL=$2
  local TYPE=$3
  local TARGET_DIR="${CONFIG_DIR}/www"
  local TEMP_DIR=$(mktemp -d)

  case $TYPE in
    "js")
      wget -O "${TARGET_DIR}/${NAME}.js" "$URL" || return 1
      ;;
    "zip")
      local ZIP_FILE="${TEMP_DIR}/${NAME}.zip"
      wget -O "$ZIP_FILE" "$URL" || return 1

      # Get directory name based on zip file name
      local EXTRACT_DIR=$(get_zip_name "$ZIP_FILE")
      local EXTRACT_PATH="${TARGET_DIR}/${EXTRACT_DIR}"

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

  jq -c 'to_entries[] | select(.value.lovelace_resource != null)' "${COMPONENTS_FILE}" | while read -r component; do
    local RESOURCE=$(echo "$component" | jq -r '.value.lovelace_resource')
    local RESOURCE_PATH="${CONFIG_DIR}/www/${RESOURCE}"

    if [ -f "$RESOURCE_PATH" ]; then
      local SHA=$(calculate_sha "$RESOURCE_PATH")
      echo "  - url: /local/${RESOURCE}?v=${SHA}" >> "${CONFIG_DIR}/lovelace_resources.yaml"
      echo "    type: module" >> "${CONFIG_DIR}/lovelace_resources.yaml"
    else
      echo "Warning: Resource file not found: ${RESOURCE}" >&2
    fi
  done
}

# Main function to process components
process_components() {
  if [ ! -f "${COMPONENTS_FILE}" ]; then
    echo "Error: components.json not found in expected location" >&2
    exit 1
  fi

  jq -c 'to_entries[]' "${COMPONENTS_FILE}" | while read -r component; do
    NAME=$(echo "$component" | jq -r '.key')
    URL=$(echo "$component" | jq -r '.value.url')
    TYPE=$(echo "$component" | jq -r '.value.type // "null"')
    VERSION=$(echo "$component" | jq -r '.value.version')

    # Auto-detect type if not specified
    if [ "$TYPE" = "null" ]; then
      TYPE=$(detect_file_type "$URL") || continue
    fi

    CACHED_VERSION=$(jq -r ".[\"$NAME\"]" "${LOCK_FILE}")

    if [ "$CACHED_VERSION" = "null" ] || [ "$CACHED_VERSION" != "$VERSION" ]; then
      echo "Downloading $NAME (version $VERSION) from $URL..."
      if handle_component_download "$NAME" "$URL" "$TYPE"; then
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

# Function to install HACS
install_hacs() {
  HACS_INSTALLED_VERSION=$(cat /config/custom_components/hacs/.version 2>/dev/null || echo "0")
  if [ ! -f "/config/custom_components/hacs/hacs_frontend/entrypoint.js" ] || version_gt "$HACS_VERSION" "$HACS_INSTALLED_VERSION"; then
    echo "Installing/Updating HACS to version $HACS_VERSION..."
    wget -O - https://get.hacs.xyz | bash -
    echo "$HACS_VERSION" > /config/custom_components/hacs/.version
  else
    echo "HACS version $HACS_INSTALLED_VERSION is up to date, skipping..."
  fi
}

# Main execution
main() {
  echo "Starting HACS plugins management..."

  # Only run HACS installation if not in test mode
  if [ "${TEST_MODE}" != "true" ]; then
    install_hacs
  fi

  process_components
  generate_lovelace_resources
  echo "Lovelace resources configuration generated based on components.json."
}

# Run main function if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
