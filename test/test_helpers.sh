#!/bin/bash

# This script is intended to be sourced by other test scripts.

# --- Test Framework ---
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
        # Also unset mock variables
        unset MOCK_PROMPT_INPUTS MOCK_PROMPT_CANCEL_ON_VAR MOCK_SELECT_HOST_RETURN MOCK_RM_CALL_LOG_FILE MOCK_PROMPT_RESULT MOCK_READ_SINGLE_CHAR_INPUTS MOCK_READ_SINGLE_CHAR_COUNTER MOCK_DATE_RETURN MOCK_MULTI_SELECT_MENU_OUTPUT
    fi

    if [[ $failures -eq 0 ]]; then exit 0; else exit 1; fi
}

# --- Mocks & Test State ---

# Mock for the `ssh` command.
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

# Mock for `mv`. It records calls to a log file.
MOCK_MV_CALL_LOG_FILE="${TEST_DIR}/mock_mv_calls.log"
mv() { echo "$*" >> "$MOCK_MV_CALL_LOG_FILE"; }

# Mock for `cp`. It records calls to a log file.
MOCK_CP_CALL_LOG_FILE="${TEST_DIR}/mock_cp_calls.log"
cp() { echo "$*" >> "$MOCK_CP_CALL_LOG_FILE"; }

# Mock for `rm`. It records calls to a log file.
MOCK_RM_CALL_LOG_FILE="${TEST_DIR}/mock_rm_calls.log"
rm() { echo "$*" >> "$MOCK_RM_CALL_LOG_FILE"; }

# Mock for `date`.
MOCK_DATE_RETURN="2023-01-01_12-00-00"
date() {
    if [[ "$1" == "+%Y-%m-%d_%H-%M-%S" ]]; then
        echo "$MOCK_DATE_RETURN"
    else
        /bin/date "$@"
    fi
}

# Mock for `prompt_for_input`.
declare -A MOCK_PROMPT_INPUTS
MOCK_PROMPT_CANCEL_ON_VAR=""
prompt_for_input() {
    local var_name="$2"
    local -n var_ref="$2"
    if [[ -n "$MOCK_PROMPT_CANCEL_ON_VAR" && "$var_name" == "$MOCK_PROMPT_CANCEL_ON_VAR" ]]; then return 1; fi
    var_ref="${MOCK_PROMPT_INPUTS[$var_name]:-${3:-}}"; return 0
}

# Mock for `select_ssh_host`
MOCK_SELECT_HOST_RETURN="test-server-1"
select_ssh_host() { echo "$MOCK_SELECT_HOST_RETURN"; return 0; }

# Mock for `prompt_yes_no`.
MOCK_PROMPT_RESULT=0
prompt_yes_no() { return "$MOCK_PROMPT_RESULT"; }

# Mock for `prompt_to_continue` to avoid interactive waits in tests.
prompt_to_continue() { return 0; }

# Mock for `read_single_char` to drive interactive menus.
MOCK_READ_SINGLE_CHAR_INPUTS=()
MOCK_READ_SINGLE_CHAR_COUNTER=0
read_single_char() {
    if (( MOCK_READ_SINGLE_CHAR_COUNTER < ${#MOCK_READ_SINGLE_CHAR_INPUTS[@]} )); then
        echo "${MOCK_READ_SINGLE_CHAR_INPUTS[MOCK_READ_SINGLE_CHAR_COUNTER]}"
        ((MOCK_READ_SINGLE_CHAR_COUNTER++))
    else
        echo "q" # Default to 'q' to prevent tests from hanging
    fi
}

# Mock for `interactive_multi_select_menu`.
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
        # Use the real `rm` command, not the mock, to ensure cleanup.
        /bin/rm -rf "$TEST_DIR"
    fi
}