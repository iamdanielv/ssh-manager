#!/bin/bash
set -o pipefail

# This script must be run from the root of the `ssh-manager` directory.

# --- Test Setup ---

# Override config paths BEFORE sourcing the scripts.
export TEST_DIR
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR" # Set HOME to test dir for predictable ~ expansion
export SSH_DIR="${TEST_DIR}/.ssh"
export SSH_CONFIG_PATH="${SSH_DIR}/config"

# --- Test Framework ---
test_count=0 # Global test counter
failures=0   # Global failure counter

initialize_test_suite() {
    test_count=0
    failures=0
}

printTestSectionHeader() {
  printf '%b\n' "\n${T_ULINE}${C_L_WHITE}    ${1}${T_RESET}"
}

_test_passed() {
    # Source colors if not already sourced by the main script
    [[ -z "$C_L_GREEN" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../advanced-ssh-manager.sh"
    printf '%s\n' "${T_OK_ICON} ${C_L_GREEN}PASS${T_RESET}: ${1}"
}

_test_failed() {
    [[ -z "$C_L_RED" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../advanced-ssh-manager.sh"
    local description="$1"
    local additional_info="$2"
    if [[ -n "$additional_info" ]]; then
        printf '%s\n' "${T_ERR_ICON} ${C_L_RED}FAIL${T_RESET}: ${description} (${additional_info})"
    else
        printf '%s\n' "${T_ERR_ICON} ${C_L_RED}FAIL${T_RESET}: ${description}"
    fi
}

_run_string_test() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    ((test_count++))

    if [[ "$actual" == "$expected" ]]; then
        _test_passed "${description}"
    else
        local sanitized_expected sanitized_actual
        sanitized_expected=$(printf '%q' "$expected")
        sanitized_actual=$(printf '%q' "$actual")
        _test_failed "${description}"
        _test_failed "Expected: ${sanitized_expected}" "FAIL"
        _test_failed "Got:      ${sanitized_actual}" "FAIL"
        ((failures++))
    fi
}

print_test_summary() {
    printTestSectionHeader "Test Summary"

    if [[ $failures -eq 0 ]]; then
        _test_passed "All ${test_count} tests passed!"
    else
        _test_failed "${failures} of ${test_count} tests failed."
    fi

    if [[ $# -gt 0 ]]; then
        unset -f -- "$@" &>/dev/null
        unset MOCK_PROMPT_INPUTS MOCK_SELECT_HOST_RETURN MOCK_PROMPT_RESULT MOCK_DATE_RETURN MOCK_REORDER_MENU_OUTPUT MOCK_MULTI_SELECT_MENU_OUTPUT
    fi

    if [[ $failures -eq 0 ]]; then exit 0; else exit 1; fi
}

# --- Mocks & Test State ---

ssh() {
    if [[ "$1" == "-G" ]]; then
        local host_alias="$2"
        local block
        block=$(_get_host_block_from_config "$host_alias" "$SSH_CONFIG_PATH")
        if [[ -n "$block" ]]; then
            echo "$block" | awk '
                BEGIN { has_port=0 }
                function get_val() { val = ""; for (i=2; i<=NF; i++) { val = (val ? val " " : "") $i }; return val }
                /^[ \t]*[Hh]ost[Nn]ame/ {print "hostname", get_val()}
                /^[ \t]*[Uu]ser/ {print "user", get_val()}
                /^[ \t]*[Pp]ort/ {print "port", get_val(); has_port=1}
                /^[ \t]*[Ii]dentity[Ff]ile/ {print "identityfile", get_val()}
                END { if (!has_port) { print "port 22" } }
            '
        fi
        return 0
    fi
    echo "ERROR: Unmocked call to ssh with args: $*" >&2
    return 127
}

MOCK_CP_CALL_LOG_FILE="${TEST_DIR}/mock_cp_calls.log"
cp() {
    echo "$*" >> "$MOCK_CP_CALL_LOG_FILE"
}

MOCK_DATE_RETURN="2023-01-01_12-00-00"
date() {
    if [[ "$1" == "+%Y-%m-%d_%H-%M-%S" ]]; then
        echo "$MOCK_DATE_RETURN"
    else
        /bin/date "$@"
    fi
}

declare -A MOCK_PROMPT_INPUTS
prompt_for_input() {
    local var_name="$2"
    local -n var_ref="$var_name"
    var_ref="${MOCK_PROMPT_INPUTS[$var_name]:-${3:-}}"
    return 0
}

MOCK_SELECT_HOST_RETURN="test-server-1"
select_ssh_host() {
    echo "$MOCK_SELECT_HOST_RETURN"
    return 0
}

MOCK_PROMPT_RESULT=0
prompt_yes_no() {
    return "$MOCK_PROMPT_RESULT"
}

prompt_to_continue() {
    return 0
}

MOCK_REORDER_MENU_OUTPUT=""
interactive_reorder_menu() {
    echo -e "$MOCK_REORDER_MENU_OUTPUT"
    if [[ -n "$MOCK_REORDER_MENU_OUTPUT" ]]; then return 0; else return 1; fi
}

MOCK_MULTI_SELECT_MENU_OUTPUT=""
interactive_multi_select_menu() {
    echo -e "$MOCK_MULTI_SELECT_MENU_OUTPUT"
    if [[ -n "$MOCK_MULTI_SELECT_MENU_OUTPUT" ]]; then return 0; else return 1; fi
}

# --- Test Harness ---

reset_test_state() {
    mkdir -p "$SSH_DIR"
    cat >"$SSH_CONFIG_PATH" <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-2
    HostName server2.example.com
    User user2

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key
EOF
}

setup() {
    initialize_test_suite
    reset_test_state
}

teardown() {
    if [[ -d "$TEST_DIR" ]]; then
        /bin/rm -rf "$TEST_DIR"
    fi
}

# --- Test Cases ---

test_edit_host_in_editor() {
    # Source the script we are testing inside the first test
    # to ensure setup variables are respected.
    # shellcheck source=../advanced-ssh-manager.sh
    if ! source "$(dirname "${BASH_SOURCE[0]}")/../advanced-ssh-manager.sh"; then
        echo "Error: Could not source advanced-ssh-manager.sh." >&2
        exit 1
    fi
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

test_reorder_ssh_hosts() {
    printTestSectionHeader "Testing reorder_ssh_hosts"
    reset_test_state
    > "$MOCK_CP_CALL_LOG_FILE"
    MOCK_PROMPT_RESULT=0

    MOCK_REORDER_MENU_OUTPUT="test-server-3
test-server-1
test-server-2"

    reorder_ssh_hosts >/dev/null 2>&1

    local -a MOCK_CP_CALLS
    mapfile -t MOCK_CP_CALLS < "$MOCK_CP_CALL_LOG_FILE"
    _run_string_test "${#MOCK_CP_CALLS[@]}" "1" "Should create a backup before reordering"

    local expected_config
    expected_config=$(cat <<'EOF'
Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key

Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-2
    HostName server2.example.com
    User user2
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should rewrite the config file with the new host order"
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
    test_reorder_ssh_hosts
    test_export_ssh_hosts
    test_import_ssh_hosts

    print_test_summary "ssh" "cp" "date" "prompt_yes_no" "prompt_for_input" "select_ssh_host" "prompt_to_continue" "interactive_reorder_menu" "interactive_multi_select_menu"
}

main