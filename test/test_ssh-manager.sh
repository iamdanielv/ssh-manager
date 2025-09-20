#!/bin/bash
set -o pipefail

# This script must be run from the root of the `ssh-manager` directory.

# --- Test Setup ---

# Override config paths BEFORE sourcing the scripts.
# The `ssh-manager.sh` script will use these variables if they are set.
export TEST_DIR
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR" # Set HOME to test dir for predictable ~ expansion
export SSH_DIR="${TEST_DIR}/.ssh"
export SSH_CONFIG_PATH="${SSH_DIR}/config"

# Source the script we are testing
# shellcheck source=../ssh-manager.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/../ssh-manager.sh"; then
    echo "Error: Could not source ssh-manager.sh." >&2
    exit 1
fi

# --- Test Framework (from shared.sh) ---
test_count=0 # Global test counter
failures=0   # Global failure counter

# Initializes or resets the test suite counters.
initialize_test_suite() {
    test_count=0
    failures=0
}

printTestSectionHeader() {
  # Use printf with %b to interpret the leading \n as a newline.
  printf '%b\n' "\n${T_ULINE}${C_L_WHITE}    ${1}${T_RESET}"
}

# (Private) Helper to print a passing test message.
_test_passed() {
    printOkMsg "${C_L_GREEN}PASS${T_RESET}: ${1}"
}

# (Private) Helper to print a failing test message.
_test_failed() {
    local description="$1"
    local additional_info="$2"
    if [[ -n "$additional_info" ]]; then
        printErrMsg "${C_L_RED}FAIL${T_RESET}: ${description} (${additional_info})"
    else
        printErrMsg "${C_L_RED}FAIL${T_RESET}: ${description}"
    fi
}

# (Private) Helper to run a single string comparison test case.
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
        printErrMsg "Expected: ${sanitized_expected}"
        printErrMsg "Got:      ${sanitized_actual}"
        ((failures++))
    fi
}

# Prints summary for test suite.
print_test_summary() {
    printTestSectionHeader "Test Summary"

    if [[ $failures -eq 0 ]]; then
        printOkMsg "All ${test_count} tests passed!"
    else
        printErrMsg "${failures} of ${test_count} tests failed."
    fi

    # Unset any mock functions passed as arguments
    if [[ $# -gt 0 ]]; then
        unset -f -- "$@" &>/dev/null
    fi

    if [[ $failures -eq 0 ]]; then exit 0; else exit 1; fi
}

# --- Mocks & Test State ---

# Mock for the `ssh` command.
ssh() {
    if [[ "$1" == "-G" ]]; then
        local host_alias="$2"
        # This mock is dynamic and reads from the test config file, just like the real `ssh -G`.
        # This is crucial for tests that modify the config file and then check its state.
        # It uses the SUT's own helper function to extract the host block.
        local block
        block=$(_get_host_block_from_config "$host_alias" "$SSH_CONFIG_PATH")

        if [[ -n "$block" ]]; then
            # Parse the extracted block for key-value pairs. This is a simplified parser
            # sufficient for the tests. It correctly handles values with spaces and default port.
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
    # If called for anything else, print an error to fail tests unexpectedly using it.
    echo "ERROR: Unmocked call to ssh with args: $*" >&2
    return 127
}

# Mock for `mv`. It records calls to a log file to work across subshells
# used by functions like `run_with_spinner`.
MOCK_MV_CALL_LOG_FILE="${TEST_DIR}/mock_mv_calls.log"
mv() {
    # Append the call arguments as a single line to the log file.
    echo "$*" >> "$MOCK_MV_CALL_LOG_FILE"
}

# Mock for `prompt_for_input`.
# Usage: MOCK_PROMPT_INPUTS["var_name"]="value"
#        MOCK_PROMPT_CANCEL_ON_VAR="var_name_to_cancel_on"
declare -A MOCK_PROMPT_INPUTS
MOCK_PROMPT_CANCEL_ON_VAR=""
prompt_for_input() {
    local var_name="$2"
    local -n var_ref="$var_name"

    if [[ -n "$MOCK_PROMPT_CANCEL_ON_VAR" && "$var_name" == "$MOCK_PROMPT_CANCEL_ON_VAR" ]]; then
        return 1 # Simulate cancellation (ESC key)
    fi

    # Return mock value, or the default value if no mock is set.
    var_ref="${MOCK_PROMPT_INPUTS[$var_name]:-${3:-}}"
    return 0
}

# Mock for `select_ssh_host`
MOCK_SELECT_HOST_RETURN="test-server-1"
select_ssh_host() {
    echo "$MOCK_SELECT_HOST_RETURN"
    return 0
}

# Mock for `rm`. It will record what it was called with.
MOCK_RM_CALLS=()
rm() {
    MOCK_RM_CALLS+=("$*")
}

# Mock for `prompt_yes_no`.
# Usage: MOCK_PROMPT_RESULT=0 (yes), 1 (no), 2 (cancel)
MOCK_PROMPT_RESULT=0
prompt_yes_no() {
    # Just return the pre-configured result.
    return "$MOCK_PROMPT_RESULT"
}

# Mock for `prompt_to_continue` to avoid interactive waits in tests.
prompt_to_continue() {
    # Do nothing, just return success.
    return 0
}

# --- Test Harness ---

reset_test_state() {
    # Create the fake .ssh directory and a dummy config file
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
    # No port, should default to 22

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key
EOF
}

setup() {
    # Reset counters for the test suite
    initialize_test_suite
    reset_test_state
}

teardown() {
    # Clean up the temporary directory
    if [[ -d "$TEST_DIR" ]]; then
        # Use the real `rm` command, not the mock, to ensure cleanup.
        # The mock `rm` is still active when this EXIT trap runs.
        /bin/rm -rf "$TEST_DIR"
    fi
}

# --- Test Cases ---

test_get_ssh_hosts() {
    printTestSectionHeader "Testing get_ssh_hosts"
    local expected_hosts="test-server-1
test-server-2
test-server-3"
    local actual_hosts
    actual_hosts=$(get_ssh_hosts)
    _run_string_test "$actual_hosts" "$expected_hosts" "Should correctly parse all host aliases from config"
}

test_get_ssh_config_value() {
    printTestSectionHeader "Testing get_ssh_config_value (with mocked ssh -G)"
    local actual
    actual=$(get_ssh_config_value "test-server-1" "HostName")
    _run_string_test "$actual" "192.168.1.101" "Should get HostName for test-server-1"

    actual=$(get_ssh_config_value "test-server-1" "Port")
    _run_string_test "$actual" "2222" "Should get non-default Port for test-server-1"

    actual=$(get_ssh_config_value "test-server-2" "Port")
    _run_string_test "$actual" "22" "Should get default Port for test-server-2"

    actual=$(get_ssh_config_value "test-server-1" "IdentityFile")
    _run_string_test "$actual" "~/.ssh/id_test1" "Should get IdentityFile for test-server-1"

    actual=$(get_ssh_config_value "test-server-2" "IdentityFile")
    _run_string_test "$actual" "" "Should get empty IdentityFile for test-server-2"
}

test_process_ssh_config_blocks() {
    printTestSectionHeader "Testing _process_ssh_config_blocks and wrappers"

    # Test _get_host_block_from_config
    local expected_block
    expected_block=$(
        cat <<'EOF'
Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22
EOF
    )
    local actual_block
    actual_block=$(_get_host_block_from_config "test-server-2" "$SSH_CONFIG_PATH")
    _run_string_test "$actual_block" "$expected_block" "_get_host_block_from_config should extract the correct block"

    # Test _remove_host_block_from_config
    local expected_config_after_remove
    expected_config_after_remove=$(
        cat <<'EOF'
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
    local actual_config_after_remove
    # The function should now preserve the blank line between blocks correctly.
    actual_config_after_remove=$(_remove_host_block_from_config "test-server-2")
    # The awk script adds a final newline, which is desired. The heredoc for expected_config_after_remove also includes one.
    _run_string_test "$actual_config_after_remove" "$expected_config_after_remove" "_remove_host_block_from_config should remove the correct block"
}

test_remove_host() {
    # Reset the config file to a known state for this test function's scope
    reset_test_state

    printTestSectionHeader "Testing remove_ssh_host and _cleanup_orphaned_key"

    # Create a dummy key file that will be orphaned
    touch "${SSH_DIR}/id_test1"
    touch "${SSH_DIR}/id_test1.pub"

    # --- Case 1: Key is still in use by a host, so it should not be removed ---
    MOCK_RM_CALLS=() # Reset rm call log
    # At this point, the config still has test-server-1, which uses id_test1.
    # _cleanup_orphaned_key should see this and not attempt to remove the key.
    _cleanup_orphaned_key "~/.ssh/id_test1" >/dev/null 2>&1
    _run_string_test "${#MOCK_RM_CALLS[@]}" "0" "Should not attempt to remove a key that is still in use"

    # --- Now, actually orphan the key by removing the host from the config ---
    local config_without_host
    config_without_host=$(_remove_host_block_from_config "test-server-1")
    echo "$config_without_host" > "$SSH_CONFIG_PATH"

    # --- Case 2: Key is orphaned, but user answers 'no' to removal prompt ---
    MOCK_PROMPT_RESULT=1 # Answer "no"
    MOCK_RM_CALLS=()
    _cleanup_orphaned_key "~/.ssh/id_test1" >/dev/null 2>&1
    _run_string_test "${#MOCK_RM_CALLS[@]}" "0" "Should not call 'rm' when user answers 'no' to cleanup"

    # --- Case 3: Key is orphaned, and user answers 'yes' to removal prompt ---
    MOCK_PROMPT_RESULT=0 # Answer "yes"
    MOCK_RM_CALLS=()
    _cleanup_orphaned_key "~/.ssh/id_test1" >/dev/null 2>&1

    local expected_rm_call_1="-f ${SSH_DIR}/id_test1 ${SSH_DIR}/id_test1.pub"
    _run_string_test "${MOCK_RM_CALLS[0]}" "$expected_rm_call_1" "Should call 'rm' with correct private and public key paths"
}

test_edit_host() {
    printTestSectionHeader "Testing edit_ssh_host"

    # --- Case 1: Edit user and port ---
    reset_test_state # Reset config
    MOCK_PROMPT_CANCEL_ON_VAR="" # Ensure no cancellation is configured
    MOCK_SELECT_HOST_RETURN="test-server-1"
    MOCK_PROMPT_INPUTS=(
        ["new_hostname"]="192.168.1.101" # Keep same
        ["new_user"]="new_user"          # Change
        ["new_port"]="2223"              # Change
        ["new_identityfile"]="~/.ssh/id_test1" # Keep same
    )

    edit_ssh_host >/dev/null 2>&1 # Run the function

    local expected_config
    expected_config=$(cat <<'EOF'
Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key

Host test-server-1
    HostName 192.168.1.101
    User new_user
    Port 2223
    IdentityFile ~/.ssh/id_test1
    IdentitiesOnly yes
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    # Using `cat -s` to squeeze blank lines for a more robust comparison
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should edit user and port correctly"

    # --- Case 2: Change IdentityFile and trigger cleanup ---
    reset_test_state
    MOCK_PROMPT_CANCEL_ON_VAR=""
    # Create dummy key files
    touch "${SSH_DIR}/id_test1"
    touch "${SSH_DIR}/id_test1.pub"
    touch "${SSH_DIR}/id_newkey" # The new key must exist for validation

    MOCK_SELECT_HOST_RETURN="test-server-1"
    MOCK_PROMPT_INPUTS=(
        ["new_identityfile"]="~/.ssh/id_newkey"
    )
    MOCK_PROMPT_RESULT=0 # Answer "yes" to cleanup prompt
    MOCK_RM_CALLS=()

    edit_ssh_host >/dev/null 2>&1

    local expected_rm_call="-f ${SSH_DIR}/id_test1 ${SSH_DIR}/id_test1.pub"
    _run_string_test "${MOCK_RM_CALLS[0]}" "$expected_rm_call" "Should call rm to clean up old orphaned key"

    # --- Case 3: User cancels during prompt ---
    reset_test_state
    local initial_config; initial_config=$(<"$SSH_CONFIG_PATH")

    MOCK_SELECT_HOST_RETURN="test-server-1"
    MOCK_PROMPT_INPUTS=(
        ["new_hostname"]="should_not_be_applied"
    )
    MOCK_PROMPT_CANCEL_ON_VAR="new_user" # Cancel when prompted for the user

    edit_ssh_host >/dev/null 2>&1

    local final_config; final_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$final_config" "$initial_config" "Should not modify config file if user cancels"
}

test_rename_host() {
    printTestSectionHeader "Testing rename_ssh_host"

    # --- Case 1: Simple rename, no key involved ---
    reset_test_state
    MOCK_PROMPT_CANCEL_ON_VAR=""
    MOCK_SELECT_HOST_RETURN="test-server-2"
    # The `rename_ssh_host` function calls `_prompt_for_unique_host_alias`,
    # which uses a local nameref variable `out_alias_var` to call `prompt_for_input`.
    # Our mock for `prompt_for_input` uses the variable name as the key, so we must use `out_alias_var`.
    MOCK_PROMPT_INPUTS=( ["out_alias_var"]="renamed-server-2" )

    rename_ssh_host >/dev/null 2>&1

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

Host renamed-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should rename host alias correctly"

    # --- Case 2: Rename host and its conventionally-named key ---
    reset_test_state
    MOCK_PROMPT_CANCEL_ON_VAR=""
    # Modify config to use a conventional key for test-server-1
    sed -i "s|~/.ssh/id_test1|${SSH_DIR}/test-server-1_id_ed25519|" "$SSH_CONFIG_PATH"
    # Create the dummy key files
    touch "${SSH_DIR}/test-server-1_id_ed25519"
    touch "${SSH_DIR}/test-server-1_id_ed25519.pub"

    # Clear the mock log file before the test run
    > "$MOCK_MV_CALL_LOG_FILE"

    MOCK_SELECT_HOST_RETURN="test-server-1"
    MOCK_PROMPT_INPUTS=( ["out_alias_var"]="renamed-server-1" )
    MOCK_PROMPT_RESULT=0 # Answer "yes" to rename key

    rename_ssh_host >/dev/null 2>&1

    # Read the logged calls from the file into an array for assertion
    local -a MOCK_MV_CALLS
    mapfile -t MOCK_MV_CALLS < "$MOCK_MV_CALL_LOG_FILE"

    # Check that mv was called correctly for both private and public keys
    local expected_mv_call_1="${SSH_DIR}/test-server-1_id_ed25519 ${SSH_DIR}/renamed-server-1_id_ed25519"
    local expected_mv_call_2="${SSH_DIR}/test-server-1_id_ed25519.pub ${SSH_DIR}/renamed-server-1_id_ed25519.pub"
    _run_string_test "${MOCK_MV_CALLS[0]}" "$expected_mv_call_1" "Should call 'mv' to rename private key"
    _run_string_test "${MOCK_MV_CALLS[1]}" "$expected_mv_call_2" "Should call 'mv' to rename public key"
}

test_clone_host() {
    printTestSectionHeader "Testing clone_ssh_host"

    # --- Case 1: Clone a host ---
    reset_test_state
    MOCK_PROMPT_CANCEL_ON_VAR=""
    MOCK_SELECT_HOST_RETURN="test-server-1"
    MOCK_PROMPT_INPUTS=( ["out_alias_var"]="cloned-server-1" )

    clone_ssh_host >/dev/null 2>&1

    local expected_config
    expected_config=$(cat <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key

Host cloned-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1
EOF
)
    local actual_config
    actual_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$(echo "$actual_config" | cat -s)" "$(echo "$expected_config" | cat -s)" "Should clone host and append it to the config"
}

test_edit_host_in_editor() {
    printTestSectionHeader "Testing edit_ssh_host_in_editor"

    # --- Case 1: Successful edit ---
    reset_test_state # Reset config

    # Mock the host selection
    MOCK_SELECT_HOST_RETURN="test-server-1"

    # Create a mock editor script that will "edit" the temp file
    local mock_editor_path="${TEST_DIR}/mock_editor.sh"
    # The new block we want the "editor" to save.
    local new_block_content
    new_block_content=$(cat <<'EOF'
Host test-server-1
    HostName 192.168.1.99
    User new-editor-user
    # This comment was added by the editor
EOF
)
    # The mock editor script takes the temp file path ($1) and overwrites it.
    # It must also preserve the modeline that the function under test adds.
    cat > "$mock_editor_path" <<EOF
#!/bin/bash
echo "# vim: set filetype=sshconfig:" > "\$1"
echo "$new_block_content" >> "\$1"
EOF
    chmod +x "$mock_editor_path"
    export EDITOR="$mock_editor_path"

    # Run the function
    edit_ssh_host_in_editor >/dev/null 2>&1

    # The expected final config file content
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

    # --- Case 2: No changes made in editor ---
    reset_test_state
    local initial_config; initial_config=$(<"$SSH_CONFIG_PATH")
    MOCK_SELECT_HOST_RETURN="test-server-1"

    # This time, the mock editor makes no changes. It just exits.
    # The function should detect this and not modify the config.
    echo -e '#!/bin/bash\nexit 0' > "$mock_editor_path"
    chmod +x "$mock_editor_path"

    edit_ssh_host_in_editor >/dev/null 2>&1

    local final_config; final_config=$(<"$SSH_CONFIG_PATH")
    _run_string_test "$final_config" "$initial_config" "Should not modify config if editor makes no changes"

    # Unset the editor override for other tests
    unset EDITOR
}

# --- Main Test Runner ---

main() {
    # Ensure cleanup happens even if tests fail
    trap teardown EXIT

    # Run setup once
    setup

    # Execute all test functions
    test_get_ssh_hosts
    test_get_ssh_config_value
    test_process_ssh_config_blocks
    test_remove_host
    test_edit_host
    test_rename_host
    test_clone_host
    test_edit_host_in_editor

    # Print summary and exit with appropriate code
    print_test_summary "ssh" "rm" "mv" "prompt_yes_no" "prompt_for_input" "select_ssh_host" "prompt_to_continue"
}

main