#!/usr/bin/env bats

setup() {
    export TEMP_DIR="$(mktemp -d)"
    export CONFIG_DIR="${TEMP_DIR}/config"
    export COMPONENTS_FILE="${CONFIG_DIR}/www/components.json"
    export LOCK_FILE="${CONFIG_DIR}/www/components.json.lock"
    export TEST_MODE="true"
    
    mkdir -p "${CONFIG_DIR}/www"
    cp entrypoint.sh "${TEMP_DIR}/"
    echo '{"test-component": "https://example.com/test-component.js"}' > "${COMPONENTS_FILE}"
    echo '{}' > "${LOCK_FILE}"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

@test "calculate_sha function works correctly" {
    echo "test content" > "${TEMP_DIR}/test_file"
    expected_sha=$(sha256sum "${TEMP_DIR}/test_file" | awk '{ print $1 }')
    
    source "${TEMP_DIR}/entrypoint.sh"
    result=$(calculate_sha "${TEMP_DIR}/test_file")
    
    [ "$result" = "$expected_sha" ]
}

@test "generate_lovelace_resources creates correct YAML structure" {
    touch "${CONFIG_DIR}/www/test-component.js"
    
    source "${TEMP_DIR}/entrypoint.sh"
    generate_lovelace_resources
    
    [ -f "${CONFIG_DIR}/lovelace_resources.yaml" ]
    first_line=$(head -n 1 "${CONFIG_DIR}/lovelace_resources.yaml")
    [ "$first_line" = "mode: yaml" ]
}

@test "script handles missing components.json" {
    rm "${COMPONENTS_FILE}"
    
    run bash "${TEMP_DIR}/entrypoint.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: components.json not found in expected location"* ]]
}

@test "script downloads new components" {
    # Mock wget to create a file instead of actually downloading
    wget() {
        touch "$2"
    }
    export -f wget
    
    source "${TEMP_DIR}/entrypoint.sh"
    process_components
    
    [ -f "${CONFIG_DIR}/www/test-component.js" ]
}

@test "script updates lock file after downloading" {
    # Mock wget to create a file instead of actually downloading
    wget() {
        touch "$2"
    }
    export -f wget
    
    source "${TEMP_DIR}/entrypoint.sh"
    process_components
    
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"test-component"* ]]
}