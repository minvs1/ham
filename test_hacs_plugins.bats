#!/usr/bin/env bats

setup() {
    export TEMP_DIR="$(mktemp -d)"
    export CONFIG_DIR="${TEMP_DIR}/config"
    export COMPONENTS_FILE="${CONFIG_DIR}/www/components.json"
    export LOCK_FILE="${CONFIG_DIR}/www/components.json.lock"
    export TEST_MODE="true"

    mkdir -p "${CONFIG_DIR}/www"
    cp entrypoint.sh "${TEMP_DIR}/"

    # Create test components.json with both explicit and implicit types
    cat > "${COMPONENTS_FILE}" << EOF
{
    "test-js": {
        "url": "https://example.com/test.js",
        "version": "1.0.0",
        "lovelace_resource": "test.js"
    },
    "test-zip": {
        "url": "https://example.com/test.zip",
        "type": "zip",
        "version": "1.0.0",
        "lovelace_resource": "test/main.js"
    },
    "test-no-resource": {
        "url": "https://example.com/test2.js",
        "version": "1.0.0",
        "lovelace_resource": null
    }
}
EOF
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

@test "detect_file_type correctly identifies file types" {
    source "${TEMP_DIR}/entrypoint.sh"

    result=$(detect_file_type "https://example.com/file.js")
    [ "$result" = "js" ]

    result=$(detect_file_type "https://example.com/file.zip")
    [ "$result" = "zip" ]

    run detect_file_type "https://example.com/file.unknown"
    [ "$status" -eq 1 ]
}

@test "generate_lovelace_resources creates correct YAML structure" {
    mkdir -p "${CONFIG_DIR}/www/test"
    touch "${CONFIG_DIR}/www/test.js"
    touch "${CONFIG_DIR}/www/test/main.js"

    source "${TEMP_DIR}/entrypoint.sh"
    generate_lovelace_resources

    [ -f "${CONFIG_DIR}/lovelace_resources.yaml" ]

    # Check basic structure
    first_line=$(head -n 1 "${CONFIG_DIR}/lovelace_resources.yaml")
    [ "$first_line" = "mode: yaml" ]

    # Check that only components with lovelace_resource are included
    resource_count=$(grep -c "url:" "${CONFIG_DIR}/lovelace_resources.yaml")
    [ "$resource_count" -eq 2 ]  # test.js and test/main.js

    # Verify null lovelace_resource is not included
    ! grep -q "test2.js" "${CONFIG_DIR}/lovelace_resources.yaml"
}

@test "script handles missing components.json" {
    rm "${COMPONENTS_FILE}"

    run bash "${TEMP_DIR}/entrypoint.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: components.json not found in expected location"* ]]
}

@test "script correctly processes JS components" {
    # Mock wget to create a file instead of actually downloading
    wget() {
        touch "$2"
    }
    export -f wget

    source "${TEMP_DIR}/entrypoint.sh"
    process_components

    [ -f "${CONFIG_DIR}/www/test-js.js" ]

    # Check lock file content
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"test-js"* ]]
    [[ "$lockfile_content" == *"1.0.0"* ]]
}

@test "script correctly processes ZIP components" {
    # Mock wget and unzip for testing
    wget() {
        echo "mock zip content" > "$2"
    }
    unzip() {
        mkdir -p "${CONFIG_DIR}/www/test"
        touch "${CONFIG_DIR}/www/test/main.js"
    }
    export -f wget unzip

    source "${TEMP_DIR}/entrypoint.sh"
    process_components

    [ -d "${CONFIG_DIR}/www/test" ]
    [ -f "${CONFIG_DIR}/www/test/main.js" ]

    # Check lock file content
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"test-zip"* ]]
    [[ "$lockfile_content" == *"1.0.0"* ]]
}

@test "script skips download if version is current" {
    # First, set the current version in lock file
    echo '{"test-js": "1.0.0"}' > "${LOCK_FILE}"

    source "${TEMP_DIR}/entrypoint.sh"

    # Capture the output of process_components
    output=$(process_components)

    [[ "$output" == *"is up to date, skipping"* ]]
}

@test "script updates when version changes" {
    # Set an old version in lock file
    echo '{"test-js": "0.9.0"}' > "${LOCK_FILE}"

    # Mock wget
    wget() {
        touch "$2"
    }
    export -f wget

    source "${TEMP_DIR}/entrypoint.sh"
    process_components

    # Verify the lock file was updated to the new version
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"1.0.0"* ]]
}
