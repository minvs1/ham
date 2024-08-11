#!/bin/bash
set -e

# Function to calculate SHA256 of a file
calculate_sha() {
  sha256sum "$1" | awk '{ print $1 }'
}

# Generate lovelace_resources.yaml
generate_lovelace_resources() {
  echo "mode: yaml" > /config/lovelace_resources.yaml
  echo "resources:" >> /config/lovelace_resources.yaml

  echo "$COMPONENTS" | jq -c 'to_entries[]' | while read component; do
    NAME=$(echo $component | jq -r '.key')
    if [ -f "/config/www/${NAME}.js" ]; then
      SHA=$(calculate_sha "/config/www/${NAME}.js")
      echo "  - url: /local/${NAME}.js?v=${SHA}" >> /config/lovelace_resources.yaml
      echo "    type: module" >> /config/lovelace_resources.yaml
    else
      echo "Warning: ${NAME}.js not found, skipping in Lovelace resources"
    fi
  done
}

# Define the version comparison function
version_gt() { 
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}

# Set HACS_VERSION if not already set
HACS_VERSION=${HACS_VERSION:-"1.32.1"} 

# Install HACS
HACS_INSTALLED_VERSION=$(cat /config/custom_components/hacs/.version 2>/dev/null || echo "0")
if [ ! -f "/config/custom_components/hacs/hacs_frontend/entrypoint.js" ] || version_gt "$HACS_VERSION" "$HACS_INSTALLED_VERSION"; then
  echo "Installing/Updating HACS to version $HACS_VERSION..."
  wget -O - https://get.hacs.xyz | bash -
  echo "$HACS_VERSION" > /config/custom_components/hacs/.version
else
  echo "HACS version $HACS_INSTALLED_VERSION is up to date, skipping..."
fi

# Ensure www directory exists
mkdir -p /config/www

# Read components configuration
if [ -f "/config/www/components.json" ]; then
  COMPONENTS=$(jq -c . /config/www/components.json)
else
  echo "Error: components.json not found in expected locations"
  exit 1
fi

# Use a writable directory for the lock file
LOCK_FILE="/config/www/components.json.lock"
[ -f "$LOCK_FILE" ] || echo "{}" > "$LOCK_FILE"

# Check if COMPONENTS is valid JSON
if ! echo "$COMPONENTS" | jq empty; then
  echo "Error: Invalid JSON in components.json"
  exit 1
fi

# Process each component
echo "$COMPONENTS" | jq -c 'to_entries[]' | while read component; do
  NAME=$(echo $component | jq -r '.key')
  URL=$(echo $component | jq -r '.value')
  
  CACHED_URL=$(jq -r ".[\"$NAME\"]" "$LOCK_FILE")
  
  if [ "$URL" != "$CACHED_URL" ]; then
    echo "Downloading $NAME from $URL..."
    if wget -O "/config/www/$NAME.js" "$URL"; then
      jq ".[\"$NAME\"] = \"$URL\"" "$LOCK_FILE" > "$LOCK_FILE.tmp" && mv "$LOCK_FILE.tmp" "$LOCK_FILE"
    else
      echo "Failed to download $NAME"
    fi
  else
    echo "$NAME is up to date, skipping download..."
  fi
done

# Remove files not in the current configuration
for file in /config/www/*.js; do
  [ -e "$file" ] || continue  # Skip if no files match
  filename=$(basename "$file" .js)
  if ! echo "$COMPONENTS" | jq -e "has(\"$filename\")" > /dev/null; then
    echo "Removing $filename.js as it's no longer in the configuration..."
    rm "$file"
    jq "del([\"$filename\"])" "$LOCK_FILE" > "$LOCK_FILE.tmp" && mv "$LOCK_FILE.tmp" "$LOCK_FILE"
  fi
done

generate_lovelace_resources

echo "Lovelace resources configuration generated based on components.json."