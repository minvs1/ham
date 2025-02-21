#!/bin/bash
# set -e

# ANSI color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RESET='\033[0m'

# Define log levels and colors
readonly LOG_ERROR=3    # Most critical, should always show
readonly LOG_WARN=2     # Show warnings and errors
readonly LOG_INFO=1     # Show info, warnings, and errors 
readonly LOG_DEBUG=0    # Show everything

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# Logging functions
log_error() { 
    [[ $LOG_ERROR -ge $LOG_LEVEL ]] && echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2 
}
log_warn() {
    [[ $LOG_WARN -ge $LOG_LEVEL ]] && echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}
log_info() {
    [[ $LOG_INFO -ge $LOG_LEVEL ]] && echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}
log_debug() {
    [[ $LOG_DEBUG -ge $LOG_LEVEL ]] && echo -e "${COLOR_GREEN}[DEBUG]${COLOR_RESET} $*"
}

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

# Function to handle file downloads and processing based on type
handle_component_download() {
  local NAME=$1
  local URL=$2
  local TYPE=$3
  local INSTALL_TYPE=$4
  local REPO_PATH=$5
  local TARGET_DIR="${CONFIG_DIR}/${INSTALL_TYPE}"
  
  log_debug "Starting component download handler for: $NAME"
  log_debug "Parameters:"
  log_debug "  URL: $URL"
  log_debug "  Type: $TYPE"
  log_debug "  Install Type: $INSTALL_TYPE"
  log_debug "  Target Directory: $TARGET_DIR"
  log_debug "  Repo Path: ${REPO_PATH:-<none>}"

  local TEMP_DIR=$(mktemp -d)
  log_debug "Created temporary directory: $TEMP_DIR"

  case $TYPE in
    "git")
      log_info "Processing git repository for $NAME"
      handle_git_download "$NAME" "$URL" "$VERSION" "$INSTALL_TYPE" "$REPO_PATH"
      local GIT_RESULT=$?
      if [ $GIT_RESULT -ne 0 ]; then
        log_error "Git download failed for $NAME"
        rm -rf "${TEMP_DIR}"
        return 1
      fi
      ;;
    "file")
      if [ "$INSTALL_TYPE" != "www" ]; then
        log_error "Single files can only be installed to www directory (component: $NAME)"
        rm -rf "${TEMP_DIR}"
        return 1
      fi
      local FILENAME=$(get_filename_from_url "$URL")
      log_info "Downloading file: $FILENAME"
      log_debug "Download target: ${TARGET_DIR}/${FILENAME}"
      
      if ! wget -O "${TARGET_DIR}/${FILENAME}" "$URL" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
          log_error "Download failed: $error_output"
        else
            log_error "Failed to download file for $NAME"
        fi

        rm -rf "${TEMP_DIR}"
        return 1
      fi
      log_info "Successfully downloaded file: $FILENAME"
      ;;
    "zip")
      local ZIP_FILE="${TEMP_DIR}/${NAME}.zip"
      log_info "Downloading zip archive for $NAME"
      log_debug "Download target: $ZIP_FILE"
      
      if ! wget -O "$ZIP_FILE" "$URL" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
          log_error "Download failed: $error_output"
        else
            log_error "Failed to download zip archive for $NAME"
        fi

        rm -rf "${TEMP_DIR}"
        return 1
      fi

      local EXTRACT_PATH="${TARGET_DIR}/${NAME}"
      log_debug "Extraction path: $EXTRACT_PATH"

      # Clean up existing directory if it exists
      if [ -d "$EXTRACT_PATH" ]; then
        log_debug "Removing existing directory: $EXTRACT_PATH"
        rm -rf "$EXTRACT_PATH"
      fi

      # Create extraction directory and extract
      log_debug "Creating extraction directory"
      mkdir -p "$EXTRACT_PATH"
      
      log_info "Extracting zip archive"
      if ! unzip -o "$ZIP_FILE" -d "$EXTRACT_PATH" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
            log_error "Extraction failed: $error_output"
        else
            log_error "Failed to extract zip archive for $NAME"
        fi

        rm -rf "${TEMP_DIR}"
        return 1
      fi
      log_info "Successfully extracted zip archive for $NAME"
      ;;
    *)
      log_error "Unsupported file type: $TYPE (component: $NAME)"
      rm -rf "${TEMP_DIR}"
      return 1
      ;;
  esac

  log_debug "Cleaning up temporary directory: $TEMP_DIR"
  rm -rf "${TEMP_DIR}"
  log_info "Successfully completed download and installation of $NAME"
  return 0
}

# Function to handle git repository cloning/updating
handle_git_download() {
    local NAME=$1
    local URL=$2
    local VERSION=$3
    local INSTALL_TYPE=$4
    local REPO_PATH=$5
    local TARGET_DIR="${CONFIG_DIR}/${INSTALL_TYPE}"
    local TEMP_DIR
    local REPO_DIR
    
    log_info "Processing git repository for $NAME"
    log_debug "Configuration:"
    log_debug "  URL: $URL"
    log_debug "  Version: $VERSION"
    log_debug "  Install Type: $INSTALL_TYPE"
    log_debug "  Repo Path: ${REPO_PATH:-<root>}"
    log_debug "  Target Directory: $TARGET_DIR"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d) || {
        log_error "Failed to create temporary directory"
        return 1
    }
    REPO_DIR="${TEMP_DIR}/repo"
    
    # Ensure cleanup on exit or error
    trap 'log_debug "Cleaning up temporary directory: $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT

    # Clone the repository
    log_info "Cloning repository: $URL"
    if ! git clone --quiet "$URL" "$REPO_DIR" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
            log_error "Clone failed: $error_output"
        else
            log_error "Failed to clone repository: $URL"
        fi

        return 1
    fi

    # Version checkout strategy
    log_debug "Attempting to checkout version: $VERSION"
    (cd "$REPO_DIR" && {
        local version_found=false
        local version_attempts=(
            "$VERSION"
            "v${VERSION}"
            "tags/${VERSION}"
            "refs/tags/${VERSION}"
        )

        for attempt in "${version_attempts[@]}"; do
            log_debug "Trying version format: $attempt"
            if git checkout --quiet "$attempt" 2>/dev/null; then
                log_info "Successfully checked out version: $attempt"
                version_found=true
                break
            fi
        done

        if ! $version_found; then
            log_error "Failed to find version $VERSION"
            log_error "Attempted formats:"
            for attempt in "${version_attempts[@]}"; do
                log_error "  - $attempt"
            done
            return 1
        fi
    }) || return 1

    # Handle repository path
    local SOURCE_DIR="$REPO_DIR"
    if [ -n "$REPO_PATH" ]; then
        SOURCE_DIR="$REPO_DIR/$REPO_PATH"
        log_debug "Using repository subfolder: $REPO_PATH"
    fi

    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        if [ -n "$REPO_PATH" ]; then
            log_error "Available directories in repository root:"
            ls -la "$REPO_DIR" | grep "^d" | awk '{print $9}' | while read -r dir; do
                log_error "  - $dir"
            done
        fi
        return 1
    fi

    local FINAL_TARGET="${TARGET_DIR}/${NAME}"
    log_debug "Preparing target directory: $FINAL_TARGET"

    # Clean up existing directory
    if [ -d "$FINAL_TARGET" ]; then
        log_debug "Removing existing directory: $FINAL_TARGET"
        rm -rf "$FINAL_TARGET" || {
            log_error "Failed to remove existing directory: $FINAL_TARGET"
            return 1
        }
    fi

    # Create target directory and copy files
    log_debug "Creating target directory and copying files"
    if ! mkdir -p "$FINAL_TARGET"; then
        log_error "Failed to create target directory: $FINAL_TARGET"
        return 1
    fi

    if ! cp -r "$SOURCE_DIR"/* "$FINAL_TARGET" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
            log_error "Copy failed: $error_output"
        else
            log_error "Failed to copy files to target directory"
        fi

        return 1
    fi

    log_info "Successfully installed $NAME to $FINAL_TARGET"
    return 0
}

# Generate lovelace_resources.yaml
handle_git_download() {
    local NAME=$1
    local URL=$2
    local VERSION=$3
    local INSTALL_TYPE=$4
    local REPO_PATH=$5
    local TARGET_DIR="${CONFIG_DIR}/${INSTALL_TYPE}"
    local REMOTE_RESOURCE_PATH=$(echo "$component" | jq -r '.remote_resource_path // ""')
    local TEMP_DIR
    local REPO_DIR
    
    log_info "Processing git repository for $NAME"
    log_debug "Configuration:"
    log_debug "  URL: $URL"
    log_debug "  Version: $VERSION"
    log_debug "  Install Type: $INSTALL_TYPE"
    log_debug "  Repo Path: ${REPO_PATH:-<root>}"
    log_debug "  Remote Resource Path: ${REMOTE_RESOURCE_PATH:-<none>}"
    log_debug "  Target Directory: $TARGET_DIR"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d) || {
        log_error "Failed to create temporary directory"
        return 1
    }
    REPO_DIR="${TEMP_DIR}/repo"
    
    # Ensure cleanup on exit or error
    trap 'log_debug "Cleaning up temporary directory: $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT

    # Clone the repository
    log_info "Cloning repository: $URL"
    if ! git clone --quiet "$URL" "$REPO_DIR" 2> >(error_output=$(cat)); then
        if [ -n "$error_output" ]; then
            log_error "Clone failed: $error_output"
        else
            log_error "Failed to clone repository: $URL"
        fi
        return 1
    fi

    # Version checkout strategy
    log_debug "Attempting to checkout version: $VERSION"
    (cd "$REPO_DIR" && {
        local version_found=false
        local version_attempts=(
            "$VERSION"
            "v${VERSION}"
            "tags/${VERSION}"
            "refs/tags/${VERSION}"
        )

        for attempt in "${version_attempts[@]}"; do
            log_debug "Trying version format: $attempt"
            if git checkout --quiet "$attempt" 2>/dev/null; then
                log_info "Successfully checked out version: $attempt"
                version_found=true
                break
            fi
        done

        if ! $version_found; then
            log_error "Failed to find version $VERSION"
            log_error "Attempted formats:"
            for attempt in "${version_attempts[@]}"; do
                log_error "  - $attempt"
            done
            return 1
        fi
    }) || return 1

    # Handle repository path
    local SOURCE_DIR="$REPO_DIR"
    if [ -n "$REPO_PATH" ]; then
        SOURCE_DIR="$REPO_DIR/$REPO_PATH"
        log_debug "Using repository subfolder: $REPO_PATH"
    fi

    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        if [ -n "$REPO_PATH" ]; then
            log_error "Available directories in repository root:"
            ls -la "$REPO_DIR" | grep "^d" | awk '{print $9}' | while read -r dir; do
                log_error "  - $dir"
            done
        fi
        return 1
    fi

    # Determine if we're handling a single file based on remote_resource_path
    if [ -n "$REMOTE_RESOURCE_PATH" ] && [[ "$REMOTE_RESOURCE_PATH" =~ \.(js|css|json)$ ]]; then
        log_debug "Remote resource path indicates a single file: $REMOTE_RESOURCE_PATH"
        
        # Extract filename from remote_resource_path
        local FILENAME=$(basename "$REMOTE_RESOURCE_PATH")
        local SOURCE_FILE
        
        # Search for the file in the repository
        SOURCE_FILE=$(find "$SOURCE_DIR" -type f -name "$FILENAME" | head -n 1)
        
        if [ -z "$SOURCE_FILE" ]; then
            log_error "Could not find source file $FILENAME in repository"
            return 1
        fi
        
        local FINAL_TARGET="${TARGET_DIR}/${REMOTE_RESOURCE_PATH}"
        
        # Create parent directory if it doesn't exist
        mkdir -p "$(dirname "$FINAL_TARGET")"
        
        # Copy single file
        log_debug "Copying single file to: $FINAL_TARGET"
        if ! cp "$SOURCE_FILE" "$FINAL_TARGET" 2> >(error_output=$(cat)); then
            if [ -n "$error_output" ]; then
                log_error "Copy failed: $error_output"
            else
                log_error "Failed to copy file to target path"
            fi
            return 1
        fi
    else
        # Handle as directory (original behavior)
        local FINAL_TARGET="${TARGET_DIR}/${NAME}"
        
        if [ -d "$FINAL_TARGET" ]; then
            log_debug "Removing existing directory: $FINAL_TARGET"
            rm -rf "$FINAL_TARGET" || {
                log_error "Failed to remove existing directory: $FINAL_TARGET"
                return 1
            }
        fi

        # Create target directory and copy files
        log_debug "Creating target directory and copying files"
        if ! mkdir -p "$FINAL_TARGET"; then
            log_error "Failed to create target directory: $FINAL_TARGET"
            return 1
        fi

        if ! cp -r "$SOURCE_DIR"/* "$FINAL_TARGET" 2> >(error_output=$(cat)); then
            if [ -n "$error_output" ]; then
                log_error "Copy failed: $error_output"
            else
                log_error "Failed to copy files to target directory"
            fi
            return 1
        fi
    fi

    log_info "Successfully installed $NAME to $FINAL_TARGET"
    return 0
}

# Generate lovelace_resources.yaml
generate_lovelace_resources() {
  echo "" > "${CONFIG_DIR}/lovelace_resources.yaml"
   
  jq -c '.[] | select(.install_type == "www")' "${COMPONENTS_FILE}" | while read -r component; do
    local NAME=$(echo "$component" | jq -r '.name')
    local TYPE=$(echo "$component" | jq -r '.type // "null"')
    local URL=$(echo "$component" | jq -r '.url')
    local VERSION=$(echo "$component" | jq -r '.version')
    local RESOURCE=$(echo "$component" | jq -r '.remote_resource_path // ""')

    # For file type, use filename from URL if remote_resource_path is not specified
    if [ -z "$RESOURCE" ] && [ "$TYPE" = "file" ]; then
      RESOURCE=$(get_filename_from_url "$URL")
    fi

    if [ -n "$RESOURCE" ]; then
      local RESOURCE_PATH="${CONFIG_DIR}/www/${RESOURCE}"
      if [ -f "$RESOURCE_PATH" ]; then
        echo "- url: /local/${RESOURCE}?v=${VERSION}" >> "${CONFIG_DIR}/lovelace_resources.yaml"
        echo "  type: module" >> "${CONFIG_DIR}/lovelace_resources.yaml"
      fi
    fi
  done
}

# Validate component configuration
validate_component() {
    local NAME=$1
    local INSTALL_TYPE=$2
    local TYPE=$3
    local REMOTE_RESOURCE_PATH=$4

    log_debug "Validating component: $NAME"
    log_debug "Parameters:"
    log_debug "  Install Type: $INSTALL_TYPE"
    log_debug "  Type: $TYPE"
    log_debug "  Remote Resource PAth: ${REMOTE_RESOURCE_PATH:-<empty>}"

    # Validate install type
    local valid_install_types=("www" "custom_components")
    if [[ ! " ${valid_install_types[@]} " =~ " ${INSTALL_TYPE} " ]]; then
        log_error "Invalid install_type '$INSTALL_TYPE' for $NAME"
        log_error "Must be one of: ${valid_install_types[*]}"
        return 1
    fi

    # Validate www components
    if [ "$INSTALL_TYPE" = "www" ]; then
        if [ "$TYPE" != "file" ] && [ -z "$REMOTE_RESOURCE_PATH" ]; then
            log_error "Invalid configuration for www component: $NAME"
            log_error "Components with install_type 'www' must either:"
            log_error "  - Have type 'file' OR"
            log_error "  - Specify a remote_resource_path"
            return 1
        fi
    fi

    log_debug "Validation successful for component: $NAME"
    return 0
}

# Main function to process components
process_components() {
  if [ ! -f "${COMPONENTS_FILE}" ]; then
    echo "Error: components.json not found in expected location" >&2
    exit 1
  fi

  log_info "Starting component processing..."
  log_debug "Using components file: ${COMPONENTS_FILE}"
  log_debug "Using lock file: ${LOCK_FILE}"

  jq -c '.[]' "${COMPONENTS_FILE}" | while read -r component; do
    NAME=$(echo "$component" | jq -r '.name')
    URL=$(echo "$component" | jq -r '.url')
    TYPE=$(echo "$component" | jq -r '.type // "null"')
    VERSION=$(echo "$component" | jq -r '.version')
    INSTALL_TYPE=$(echo "$component" | jq -r '.install_type // "www"')
    REMOTE_RESOURCE_PATH=$(echo "$component" | jq -r '.remote_resource_path // ""')

    log_debug "Processing component: $NAME"
    log_debug "Configuration:"
    log_debug "  URL: $URL"
    log_debug "  Type: $TYPE"
    log_debug "  Version: $VERSION"
    log_debug "  Install Type: $INSTALL_TYPE"

    # Auto-detect type if not specified
    if [ "$TYPE" = "null" ]; then
        log_info "Type not specified for $NAME, attempting auto-detection..."
        TYPE=$(detect_file_type "$URL") || {
            log_error "Failed to auto-detect type for $NAME"
            continue
        }
        log_info "Detected type: $TYPE"
    fi

    # Validate component configuration
    if ! validate_component "$NAME" "$INSTALL_TYPE" "$TYPE" "$REMOTE_RESOURCE_PATH"; then
        log_error "Validation failed for component $NAME"
        continue
    fi

    CACHED_VERSION=$(jq -r ".[\"$NAME\"]" "${LOCK_FILE}")

    if [ "$CACHED_VERSION" = "null" ]; then
        log_info "Installing new component: $NAME (version $VERSION)"
    elif [ "$CACHED_VERSION" != "$VERSION" ]; then
        log_info "Updating $NAME from version $CACHED_VERSION to $VERSION"
    else
        log_info "Component $NAME is already at version $VERSION, skipping..."
        continue
    fi

    if handle_component_download "$NAME" "$URL" "$TYPE" "$INSTALL_TYPE" "$REPO_PATH"; then
        log_debug "Updating lock file for $NAME"
        if jq --arg name "$NAME" --arg version "$VERSION" \
            '.[$name] = $version' "${LOCK_FILE}" > "${LOCK_FILE}.tmp" && \
            mv "${LOCK_FILE}.tmp" "${LOCK_FILE}"; then
            log_info "Successfully installed/updated $NAME to version $VERSION"
        else
            log_error "Failed to update lock file for $NAME"
        fi
    else
        log_error "Failed to download component $NAME"
    fi

    log_info "Component processing completed"
  done
}

# Main execution
main() {
  log_info "Starting HAM..."
  process_components
  generate_lovelace_resources
  log_info "Lovelace resources configuration generated based on components.json."
}

# Run main function if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
