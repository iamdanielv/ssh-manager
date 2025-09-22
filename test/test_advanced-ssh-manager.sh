#!/bin/bash
set -o pipefail

# Source the shared test helpers
# shellcheck source=./test_helpers.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"; then
    echo "Error: Could not source test_helpers.sh." >&2
    exit 1
fi

# --- Test Setup ---

# This script must be run from the root of the `ssh-manager` directory.

# Initialize environment and source the script under test.
initialize_test_environment "advanced-ssh-manager.sh"

# --- Test Cases ---

test_edit_host_in_editor() {
    printTestSectionHeader "Testing edit_ssh_host_in_editor"

    reset_test_state
    MOCK_SELECT_HOST_RETURN="test-server-1"
    local mock_editor_path="${TEST_DIR}/mock_editor.sh"
    local new_block_content
    new_block_content=$(cat <<'EOF'
Host test-server-1
    HostName 192.168.1.99
    User new-editor-user
EOF
)
    cat > "$mock_editor_path" <<EOF
#!/bin/bash
echo "# vim: set filetype=sshconfig:" > "\$1"
echo "$new_block_content" >> "\$1"
EOF
    chmod +x "$mock_editor_path"
    export EDITOR="$mock_editor_path"

    edit_ssh_host_in_editor >/dev/null 2>&1

    local expected_config
    expected_config=$(cat <<EOF
Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key

$new_block_content
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should update config with content from editor"
    unset EDITOR
}

test_backup_ssh_config() {
    printTestSectionHeader "Testing backup_ssh_config"
    reset_test_state
    > "$MOCK_CP_CALL_LOG_FILE"

    backup_ssh_config >/dev/null 2>&1

    local -a MOCK_CP_CALLS
    mapfile -t MOCK_CP_CALLS < "$MOCK_CP_CALL_LOG_FILE"
    local expected_cp_call="${SSH_CONFIG_PATH} ${SSH_DIR}/backups/config_${MOCK_DATE_RETURN}.bak"
    _run_string_test "${MOCK_CP_CALLS[0]}" "$expected_cp_call" "Should call cp to create a timestamped backup"
}

test_export_ssh_hosts() {
    printTestSectionHeader "Testing export_ssh_hosts"
    reset_test_state

    MOCK_MULTI_SELECT_MENU_OUTPUT="1
3"

    local export_file_path="${TEST_DIR}/export.conf"
    MOCK_PROMPT_INPUTS=( ["export_file"]="$export_file_path" )

    export_ssh_hosts >/dev/null 2>&1

    local expected_export_content
    expected_export_content=$(cat <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key
EOF
)
    local actual_export_content
    actual_export_content=$(<"$export_file_path")
    _run_string_test "$(echo "$actual_export_content" | cat -s)" "$(echo "$expected_export_content" | cat -s)" "Should export selected host blocks to a file"
}

test_import_ssh_hosts() {
    printTestSectionHeader "Testing import_ssh_hosts"
    reset_test_state

    local import_file_path="${TEST_DIR}/import.conf"
    cat >"$import_file_path" <<'EOF'
Host new-server-1
    HostName new.server.com
    User newuser

Host test-server-2
    HostName server2.updated.com
    User user2-updated
EOF

    MOCK_PROMPT_INPUTS=( ["import_file"]="$import_file_path" )
    MOCK_PROMPT_RESULT=0

    import_ssh_hosts >/dev/null 2>&1

    local expected_config
    expected_config=$(cat <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key

Host new-server-1
    HostName new.server.com
    User newuser

Host test-server-2
    HostName server2.updated.com
    User user2-updated
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should import new hosts and overwrite existing ones"
}

# --- Main Test Runner ---

main() {
    trap teardown EXIT
    setup

    printTestSectionHeader "Running Tests for advanced-ssh-manager.sh"

    test_edit_host_in_editor
    test_backup_ssh_config
    test_export_ssh_hosts
    test_import_ssh_hosts

    print_test_summary "ssh" "cp" "date" "prompt_yes_no" "prompt_for_input" "select_ssh_host" "prompt_to_continue" "interactive_multi_select_menu"
}

main