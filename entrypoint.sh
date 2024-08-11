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

# Generate lovelace_resources.yaml
generate_lovelace_resources() {
  echo "mode: yaml" > "${CONFIG_DIR}/lovelace_resources.yaml"
  echo "resources:" >> "${CONFIG_DIR}/lovelace_resources.yaml"

  jq -c 'to_entries[]' "${COMPONENTS_FILE}" | while read -r component; do
    NAME=$(echo "$component" | jq -r '.key')
    if [ -f "${CONFIG_DIR}/www/${NAME}.js" ]; then
      SHA=$(calculate_sha "${CONFIG_DIR}/www/${NAME}.js")
      echo "  - url: /local/${NAME}.js?v=${SHA}" >> "${CONFIG_DIR}/lovelace_resources.yaml"
      echo "    type: module" >> "${CONFIG_DIR}/lovelace_resources.yaml"
    else
      echo "Warning: ${NAME}.js not found, skipping in Lovelace resources" >&2
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
    URL=$(echo "$component" | jq -r '.value')
    
    CACHED_URL=$(jq -r ".[\"$NAME\"]" "${LOCK_FILE}")
    
    if [ "$URL" != "$CACHED_URL" ]; then
      echo "Downloading $NAME from $URL..."
      if wget -O "${CONFIG_DIR}/www/${NAME}.js" "$URL"; then
        jq ".[\"$NAME\"] = \"$URL\"" "${LOCK_FILE}" > "${LOCK_FILE}.tmp" && mv "${LOCK_FILE}.tmp" "${LOCK_FILE}"
      else
        echo "Failed to download $NAME" >&2
      fi
    else
      echo "$NAME is up to date, skipping download..."
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