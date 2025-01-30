#!/usr/bin/env bats

setup() {
    export TEMP_DIR="$(mktemp -d)"
    export CONFIG_DIR="${TEMP_DIR}/config"
    export COMPONENTS_FILE="${CONFIG_DIR}/www/components.json"
    export LOCK_FILE="${CONFIG_DIR}/www/components.json.lock"
    export TEST_MODE="true"

    mkdir -p "${CONFIG_DIR}/www"
    cp entrypoint.sh "${TEMP_DIR}/"

    # Create test components.json with array structure
    cat > "${COMPONENTS_FILE}" << EOF
[
    {
        "name": "test-file",
        "url": "https://example.com/test.js",
        "version": "1.0.0",
        "install_type": "www"
    },
    {
        "name": "test-zip",
        "url": "https://example.com/test.zip",
        "type": "zip",
        "version": "1.0.0",
        "install_type": "www",
        "lovelace_resource": "test/main.js"
    },
    {
        "name": "test-git",
        "url": "https://github.com/test/repo.git",
        "version": "main",
        "install_type": "custom_components",
        "repo_path": "custom_components/test"
    }
]
EOF
    echo '{}' > "${LOCK_FILE}"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

@test "detect_file_type correctly identifies file types" {
    source "${TEMP_DIR}/entrypoint.sh"

    result=$(detect_file_type "https://example.com/file.js")
    [ "$result" = "file" ]

    result=$(detect_file_type "https://example.com/file.css")
    [ "$result" = "file" ]

    result=$(detect_file_type "https://example.com/file.zip")
    [ "$result" = "zip" ]

    result=$(detect_file_type "https://github.com/user/repo.git")
    [ "$result" = "git" ]

    run detect_file_type "https://example.com/file.unknown"
    [ "$status" -eq 1 ]
}

@test "get_filename_from_url works correctly" {
    source "${TEMP_DIR}/entrypoint.sh"

    result=$(get_filename_from_url "https://example.com/test.js")
    [ "$result" = "test.js" ]

    result=$(get_filename_from_url "https://example.com/path/to/style.css")
    [ "$result" = "style.css" ]
}

@test "generate_lovelace_resources creates correct YAML structure" {
    mkdir -p "${CONFIG_DIR}/www/test"

    # Create test files
    echo "test" > "${CONFIG_DIR}/www/test.js"
    echo "test" > "${CONFIG_DIR}/www/test/main.js"

    # Create a specific components.json for this test
    cat > "${COMPONENTS_FILE}" << EOF
[
    {
        "name": "test-js",
        "url": "https://example.com/test.js",
        "version": "1.0.0",
        "type": "file",
        "install_type": "www"
    },
    {
        "name": "test-main",
        "url": "https://example.com/main.js",
        "version": "1.0.0",
        "install_type": "www",
        "lovelace_resource": "test/main.js"
    }
]
EOF

    source "${TEMP_DIR}/entrypoint.sh"
    generate_lovelace_resources

    cat "${CONFIG_DIR}/lovelace_resources.yaml"
    grep -c "url:" "${CONFIG_DIR}/lovelace_resources.yaml"

    [ -f "${CONFIG_DIR}/lovelace_resources.yaml" ]
    [ "$(head -n 1 "${CONFIG_DIR}/lovelace_resources.yaml")" = "mode: yaml" ]
    [ "$(grep -c "url:" "${CONFIG_DIR}/lovelace_resources.yaml")" -eq 2 ]
}

@test "script handles missing components.json" {
    rm "${COMPONENTS_FILE}"

    run bash "${TEMP_DIR}/entrypoint.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: components.json not found in expected location"* ]]
}

@test "script correctly processes file components" {
    # Mock wget to create a file instead of actually downloading
    wget() {
        touch "$2"
    }
    export -f wget

    source "${TEMP_DIR}/entrypoint.sh"
    process_components

    [ -f "${CONFIG_DIR}/www/test.js" ]

    # Check lock file content
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"test-file"* ]]
    [[ "$lockfile_content" == *"1.0.0"* ]]
}

@test "script correctly processes ZIP components" {
    # Mock wget and unzip for testing
    wget() {
        echo "mock zip content" > "$2"
    }
    unzip() {
        mkdir -p "${CONFIG_DIR}/www/test-zip"
        touch "${CONFIG_DIR}/www/test-zip/main.js"
    }
    export -f wget unzip

    source "${TEMP_DIR}/entrypoint.sh"
    process_components

    [ -d "${CONFIG_DIR}/www/test-zip" ]
    [ -f "${CONFIG_DIR}/www/test-zip/main.js" ]

    # Check lock file content
    lockfile_content=$(cat "${LOCK_FILE}")
    [[ "$lockfile_content" == *"test-zip"* ]]
    [[ "$lockfile_content" == *"1.0.0"* ]]
}

@test "script correctly processes git components" {
    # Create test components.json specifically for git test
    cat > "${COMPONENTS_FILE}" << EOF
[
    {
        "name": "test-git",
        "url": "https://github.com/test/repo.git",
        "version": "main",
        "type": "git",
        "install_type": "custom_components",
        "repo_path": "test"
    }
]
EOF

    # Mock git clone and checkout
    git() {
        local cmd="$1"
        case "$cmd" in
            "clone")
                # Get the target directory (last argument)
                local target_dir="${@: -1}"
                echo "Mock git clone creating repository in: $target_dir"

                # Create the repo directory and content
                mkdir -p "$target_dir/test"
                echo "test" > "$target_dir/test/test.py"

                # Debug output
                echo "Created directory structure:"
                ls -R "$target_dir"
                return 0
                ;;
            "checkout")
                echo "Mock git checkout of version: $2"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    export -f git

    # Mock wget to avoid actual downloads
    wget() {
        return 0
    }
    export -f wget

    source "${TEMP_DIR}/entrypoint.sh"

    # Debug output before processing
    echo "Initial directory structure:"
    ls -R "${CONFIG_DIR}"

    process_components

    # Debug output after processing
    echo "Final directory structure:"
    ls -R "${CONFIG_DIR}"

    [ -d "${CONFIG_DIR}/custom_components/test-git" ]
    [ -f "${CONFIG_DIR}/custom_components/test-git/test.py" ]
}

@test "script skips download if version is current" {
    # Set the current version in lock file
    echo '{"test-file": "1.0.0"}' > "${LOCK_FILE}"

    source "${TEMP_DIR}/entrypoint.sh"

    # Capture the output of process_components
    output=$(process_components)

    [[ "$output" == *"is up to date, skipping"* ]]
}

@test "script updates when version changes" {
    # Set an old version in lock file
    echo '{"test-file": "0.9.0"}' > "${LOCK_FILE}"

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

@test "validate_component enforces correct configuration" {
    source "${TEMP_DIR}/entrypoint.sh"

    # Valid www file component
    run validate_component "test" "www" "file" ""
    [ "$status" -eq 0 ]

    # Valid www git component with resource
    run validate_component "test" "www" "git" "test.js"
    [ "$status" -eq 0 ]

    # Invalid install_type
    run validate_component "test" "invalid" "file" ""
    [ "$status" -eq 1 ]

    # www git component without resource
    run validate_component "test" "www" "git" ""
    [ "$status" -eq 1 ]
}
