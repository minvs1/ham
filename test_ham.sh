#!/bin/bash
set -e

# Test configuration
readonly TEST_DIR=$(mktemp -d)
readonly CONFIG_DIR="${TEST_DIR}/config"
readonly COMPONENTS_FILE="${CONFIG_DIR}/ham/components.json"
readonly LOCK_FILE="${CONFIG_DIR}/ham/components.json.lock"
readonly LOVELACE_FILE="${CONFIG_DIR}/lovelace_resources.yaml"

readonly EXPECTED_LOVELACE_YAML='- url: /local/vacuum-card.js?v=2.10.1
  type: module
- url: /local/auto-entities.js?v=1.13.0
  type: module'

# Test components configuration
readonly TEST_COMPONENTS='[
  {
    "name": "vacuum-card",
    "url": "https://github.com/denysdovhan/vacuum-card/releases/download/v2.10.1/vacuum-card.js",
    "version": "2.10.1",
    "type": "file",
    "install_type": "www"
  },
  {
    "name": "browser-mod",
    "url": "https://github.com/thomasloven/hass-browser_mod",
    "version": "2.3.3",
    "type": "git",
    "install_type": "custom_components",
    "remote_resource_path": "custom_components/browser_mod"
  },
  {
    "name": "lovelace-auto-entities",
    "url": "https://github.com/thomasloven/lovelace-auto-entities",
    "version": "1.13.0",
    "type": "git",
    "install_type": "www",
    "remote_resource_path": "auto-entities.js"
  }
]'

# Initialize test environment
setup_test_env() {
    echo "Setting up test environment in ${TEST_DIR}..."
    
    # Create directory structure
    mkdir -p "${CONFIG_DIR}/ham"
    mkdir -p "${CONFIG_DIR}/www"
    mkdir -p "${CONFIG_DIR}/custom_components"
    
    # Create components.json
    echo "${TEST_COMPONENTS}" > "${COMPONENTS_FILE}"
    
    # Export required environment variables
    export CONFIG_DIR
    export COMPONENTS_FILE
    export LOCK_FILE
    export LOG_LEVEL=0
}

# Cleanup function
cleanup() {
    echo "Cleaning up test environment..."
    # rm -rf "${TEST_DIR}"
}

# Test assertion helpers
assert() {
    local message=$1
    local condition=$2
    
    if eval "${condition}"; then
        echo "✅ ${message}"
    else
        echo "❌ ${message}"
        echo "Assertion failed: ${condition}"
        cleanup
        exit 1
    fi
}

assert_file_exists() {
    local file=$1
    local message=${2:-"File exists: ${file}"}
    assert "${message}" "[ -f '${file}' ]"
}

assert_dir_exists() {
    local dir=$1
    local message=${2:-"Directory exists: ${dir}"}
    assert "${message}" "[ -d '${dir}' ]"
}

assert_file_contains() {
    local file=$1
    local pattern=$2
    local message=${3:-"File contains pattern: ${pattern}"}
    assert "${message}" "grep -q '${pattern}' '${file}'"
}

assert_yaml_matches() {
    local actual_file=$1
    local expected_content=$2
    local message=${3:-"YAML content matches expected structure"}
    
    # Create temporary files for comparison
    local tmp_expected
    local tmp_actual
    tmp_expected=$(mktemp)
    tmp_actual=$(mktemp)
    
    # Normalize and save expected content
    echo "${expected_content}" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "${tmp_expected}"
    
    # Normalize and save actual content
    sed '/^[[:space:]]*$/d' "${actual_file}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "${tmp_actual}"
    
    # Compare files
    if diff "${tmp_expected}" "${tmp_actual}" > /dev/null; then
        echo "✅ ${message}"
    else
        echo "❌ ${message}"
        echo "Expected YAML:"
        cat "${tmp_expected}"
        echo "Actual YAML:"
        cat "${tmp_actual}"
        echo "Diff:"
        diff "${tmp_expected}" "${tmp_actual}" || true
        rm -f "${tmp_expected}" "${tmp_actual}"
        cleanup
        exit 1
    fi
    
    # Cleanup temporary files
    rm -f "${tmp_expected}" "${tmp_actual}"
}

# Main test function
run_tests() {
    echo "Running HAM tests..."
    echo "Test components configuration:"
    echo "${TEST_COMPONENTS}" | jq '.'
    echo "----------------------------"
    
    # Setup test environment
    setup_test_env
    
    # Run HAM script (assuming it's in the PATH or current directory)
    echo "Executing HAM script..."
    ./ham.sh
    
    echo "Verifying directory structure..."
    assert_dir_exists "${CONFIG_DIR}/www"
    assert_dir_exists "${CONFIG_DIR}/custom_components"
    assert_dir_exists "${CONFIG_DIR}/ham"
    
    echo "Verifying components installation..."
    # Check vacuum-card
    assert_file_exists "${CONFIG_DIR}/www/vacuum-card.js" \
        "vacuum-card.js is installed"
    
    # Check browser-mod
    assert_dir_exists "${CONFIG_DIR}/custom_components/browser-mod" \
        "browser_mod component is installed"
    
    # Check auto-entities
    assert_file_exists "${CONFIG_DIR}/www/auto-entities.js" \
        "auto-entities component is installed"
    
    echo "Verifying lovelace_resources.yaml..."
    assert_file_exists "${LOVELACE_FILE}" \
        "lovelace_resources.yaml is created"
    
    # Check lovelace resources content
    assert_file_contains "${LOVELACE_FILE}" "url: /local/vacuum-card.js?v=2.10.1" \
        "vacuum-card resource is configured"
    assert_file_contains "${LOVELACE_FILE}" "url: /local/auto-entities.js?v=1.13.0" \
        "auto-entities resource is configured"
    
    echo "Verifying lock file..."
    assert_file_exists "${LOCK_FILE}" \
        "Lock file is created"
    
    # Verify exact YAML content
    assert_yaml_matches "${LOVELACE_FILE}" "${EXPECTED_LOVELACE_YAML}" \
        "lovelace_resources.yaml has correct structure and content"
    
    # Verify lock file contents using jq
    for component in "vacuum-card" "browser-mod" "lovelace-auto-entities"; do
        assert "Lock file contains ${component}" \
            "jq -e '.\"${component}\"' '${LOCK_FILE}' > /dev/null"
    done
    
    echo "All tests passed! 🎉"
}

# Run tests with cleanup
trap cleanup EXIT
run_tests