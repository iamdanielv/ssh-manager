#!/bin/bash
# An interactive TUI for managing and connecting to SSH hosts.

# BUILD_INCLUDE_START: lib/tui.lib.sh
# This block is replaced by the build script.
# For development, it sources the library file.
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/tui.lib.sh"; then echo "Error: Could not source src/lib/tui.lib.sh." >&2; exit 1; fi
# BUILD_INCLUDE_END: lib/tui.lib.sh

# BUILD_INCLUDE_START: lib/ssh.lib.sh
# This block is replaced by the build script.
# For development, it sources the library file.
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/ssh.lib.sh"; then echo "Error: Could not source src/lib/ssh.lib.sh." >&2; exit 1; fi
# BUILD_INCLUDE_END: lib/ssh.lib.sh

#region Prerequisite & Sanity Checks
_check_command_exists() { command -v "$1" &>/dev/null; }
prereq_checks() {
    local missing_commands=(); printf '%s Running prereq checks' "${T_INFO_ICON}"
    for cmd in "$@"; do printf '%b.%b' "${C_L_BLUE}" "${T_RESET}"; if ! _check_command_exists "$cmd"; then missing_commands+=("$cmd"); fi; done; echo
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        clear_lines_up 1; printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"; done
        printMsg "${T_INFO_ICON} Please install the missing commands and try again."; exit 1
    fi; clear_lines_up 1
}
#endregion Prerequisite & Sanity Checks

#region Spinners
SPINNER_OUTPUT=""
_run_with_spinner_non_interactive() {
    local desc="$1"; shift; local cmd=("$@"); printMsgNoNewline "${desc} " >&2
    if SPINNER_OUTPUT=$("${cmd[@]}" 2>&1); then printf '%s\n' "${C_L_GREEN}Done.${T_RESET}" >&2; return 0
    else local exit_code=$?; printf '%s\n' "${C_RED}Failed.${T_RESET}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; return $exit_code; fi
}

_run_with_spinner_interactive() {
    local desc="$1"; shift; local cmd=("$@"); local temp_output_file; temp_output_file=$(mktemp)
    if [[ ! -f "$temp_output_file" ]]; then printErrMsg "Failed to create temp file."; return 1; fi
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"; local i=0; "${cmd[@]}" &> "$temp_output_file" &
    local pid=$!; printMsgNoNewline "${T_CURSOR_HIDE}" >&2; trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >&2; rm -f "$temp_output_file"; exit 130' INT TERM
    while ps -p $pid > /dev/null; do
        printf '\r\033[2K' >&2; local line; line=$(tail -n 1 "$temp_output_file" 2>/dev/null | tr -d '\r' || true)
        printf ' %s%s%s  %s' "${C_L_BLUE}" "${spinner_chars:$i:1}" "${T_RESET}" "${desc}" >&2
        if [[ -n "$line" ]]; then printf ' %s[%s]%s' "${C_GRAY}" "${line:0:70}" "${T_RESET}" >&2; fi
        i=$(((i + 1) % ${#spinner_chars})); sleep 0.1; done
    wait $pid; local exit_code=$?; SPINNER_OUTPUT=$(<"$temp_output_file"); rm "$temp_output_file";
    printMsgNoNewline "${T_CURSOR_SHOW}" >&2; trap - INT TERM; clear_current_line >&2
    if [[ $exit_code -eq 0 ]]; then printOkMsg "${desc}" >&2
    else printErrMsg "Task failed: ${desc}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; fi
    return $exit_code
}

run_with_spinner() {
    if [[ ! -t 1 ]]; then _run_with_spinner_non_interactive "$@"; else _run_with_spinner_interactive "$@"; fi
}

wait_for_pids_with_spinner() {
    local desc="$1"; shift; local pids_to_wait_for=("$@")
    if [[ ! -t 1 ]]; then
        printMsgNoNewline "    ${T_INFO_ICON} ${desc}... " >&2;
        if wait "${pids_to_wait_for[@]}"; then printf '%s\n' "${C_L_GREEN}Done.${T_RESET}" >&2; return 0
        else local exit_code=$?; printf '%s\n' "${C_RED}Failed (wait command exit code: $exit_code).${T_RESET}" >&2; return $exit_code; fi
    fi
    _spinner() {
        local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"; local i=0;
        while true; do printf '\r\033[2K' >&2; printf '    %s%s%s %s' "${C_L_BLUE}" "${spinner_chars:$i:1}" "${T_RESET}" "${desc}" >&2; i=$(((i + 1) % ${#spinner_chars})); sleep 0.1; done;
    }
    printMsgNoNewline "${T_CURSOR_HIDE}" >&2
    _spinner &
    local spinner_pid=$!
    trap 'kill "$spinner_pid" &>/dev/null; printMsgNoNewline "${T_CURSOR_SHOW}" >&2; exit 130' INT TERM
    wait "${pids_to_wait_for[@]}"; local exit_code=$?
    kill "$spinner_pid" &>/dev/null; printMsgNoNewline "${T_CURSOR_SHOW}" >&2; trap - INT TERM; clear_current_line >&2
    if [[ $exit_code -eq 0 ]]; then printOkMsg "${desc}" >&2
    else printErrMsg "Wait command failed with exit code ${exit_code} for task: ${desc}" >&2; fi
    return $exit_code
}
#endregion Spinners

# --- Constants ---
SSH_DIR="${SSH_DIR:-${HOME}/.ssh}"
SSH_CONFIG_PATH="${SSH_CONFIG_PATH:-${SSH_DIR}/config}"
PORT_FORWARDS_CONFIG_PATH="${PORT_FORWARDS_CONFIG_PATH:-${SSH_DIR}/port_forwards.conf}"

# --- Script Functions ---

print_usage() {
    printBanner "SSH Connection Manager"
    printMsg "An interactive TUI to manage and connect to SSH hosts in:\n ${C_L_BLUE}${SSH_CONFIG_PATH}${T_RESET}"
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [option]"
    printMsg "\nThis script is fully interactive.\nRun without arguments to launch the main menu."
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-c, --connect${T_RESET}      Go directly to host selection for connecting"
    printMsg "  ${C_L_BLUE}-a, --add${T_RESET}          Go directly to the 'Add a new server' menu"
    printMsg "  ${C_L_BLUE}-p, --port-forward${T_RESET} Go directly to the 'Port Forwarding' menu"
    printMsg "  ${C_L_BLUE}-l, --list-hosts${T_RESET}    List all configured hosts and exit"
    printMsg "  ${C_L_BLUE}-f, --list-forwards${T_RESET}  List active port forwards and exit"
    printMsg "  ${C_L_BLUE}-t, --test [host|all]${T_RESET}  Test connection to a host, all hosts, or show menu"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}         Show this help message"
}

# (Private) Helper function to rename both private and public key files.
# This is designed to be called by `run_with_spinner`.
# Usage: _rename_key_pair <old_base_path> <new_base_path>
_rename_key_pair() {
    local old_base="$1"
    local new_base="$2"
    # The `&&` ensures we only try to move the public key if the private key move succeeds.
    mv "${old_base}" "${new_base}" && mv "${old_base}.pub" "${new_base}.pub"
}

# Helper function that does the actual ssh-copy-id work
copy_ssh_id_for_host() {
    local host_alias="$1"
    local key_file="$2"
    
    # By using the host_alias directly, ssh-copy-id will respect all settings
    # in the ~/.ssh/config file for that host, including User, HostName, and Port.
    # This is more robust than manually extracting values.
    printInfoMsg "Attempting to copy key to '${host_alias}'..."
    printMsg "You may be prompted for the password for the remote user."

    # ssh-copy-id is interactive, so we run it directly in the foreground.
    if ssh-copy-id -i "$key_file" "$host_alias"; then
        printOkMsg "Key successfully copied to '${host_alias}'."
    else
        printErrMsg "Failed to copy key to '${host_alias}'."
        printInfoMsg "Check your network connection, password, and server's SSH configuration."
        return 1
    fi
}

# (Private) Continues the key generation process after a type has been selected.
# This is designed to be called from the interactive view or the full-screen wizard.
# Usage: _generate_ssh_key_from_type "ed25519 (recommended)"
_generate_ssh_key_from_type() {
    local key_type_selection="$1"

    local key_type="ed25519" # Default
    local -a key_bits_args=()
    if [[ "$key_type_selection" == "rsa (legacy, 4096 bits)" ]]; then
        key_type="rsa"
        key_bits_args=("-b" "4096")
    fi

    local key_filename
    prompt_for_input "Enter filename for the new key\n (in ${SSH_DIR})" key_filename "id_${key_type}" || return
    local full_key_path="${SSH_DIR}/${key_filename}"

    if [[ -f "$full_key_path" ]]; then
        if ! prompt_yes_no "Key file '${full_key_path}' already exists. Overwrite it?" "n"; then
            printInfoMsg "Key generation cancelled."
            return
        fi
    fi

    local key_comment
    prompt_for_input "Enter a comment for the key" key_comment "${USER}@$(hostname)" || return

    if run_with_spinner "Generating new ${key_type} key..." \
        ssh-keygen -t "${key_type}" "${key_bits_args[@]}" -f "${full_key_path}" -N "" -C "${key_comment}"; then
        printInfoMsg "Key pair created:"
        printMsg "  Private key: ${C_L_BLUE}${full_key_path/#$HOME/\~}${T_RESET}"
        printMsg "  Public key:  ${C_L_BLUE}${full_key_path/#$HOME/\~}.pub${T_RESET}"
    else
        # run_with_spinner already prints the error details.
        printErrMsg "Failed to generate SSH key."
    fi
}

# (Private) Prompts for a port number and validates it is a valid integer (1-65535).
# Loops until a valid port is entered or the user cancels.
# Usage: _prompt_for_valid_port "Prompt text" "variable_name" ["allow_empty"]
# The variable's current value is used as the default.
# If allow_empty is true, an empty input will resolve to port 22.
# Returns 0 on success, 1 on cancellation.
_prompt_for_valid_port() {
    local prompt_text="$1"
    local var_name="$2"
    local allow_empty="${3:-false}"
    local -n var_ref="$var_name" # nameref to the caller's variable

    while true; do
        # prompt_for_input returns 1 on cancellation (ESC)
        # We allow empty input if the caller allows it.
        # The third argument to prompt_for_input is the default value. We pass the
        # variable's current value so the user sees what they last typed.
        if ! prompt_for_input "$prompt_text" "$var_name" "$var_ref" "$allow_empty"; then
            return 1 # User cancelled
        fi

        # Validate the input now held by the nameref
        if [[ "$allow_empty" == "true" && -z "$var_ref" ]]; then
            # If empty is allowed, treat it as the default port 22.
            var_ref="22"
            return 0
        elif [[ "$var_ref" =~ ^[0-9]+$ && "$var_ref" -ge 1 && "$var_ref" -le 65535 ]]; then
            return 0 # Valid port, success
        else
            local err_msg="Invalid port. Please enter a number between 1 and 65535."
            if [[ "$allow_empty" == "true" ]]; then
                err_msg="Invalid port. Please enter a number between 1-65535, or leave blank for default (22)."
            fi
            show_timed_message "${T_ERR_ICON} ${err_msg}" 2
        fi
    done
}
# (Private) A wrapper for _generate_ssh_key_from_type that adds a banner.
# This is intended to be called by `run_menu_action`.
_generate_ssh_key_from_type_with_banner() {
    printBanner "Add New SSH Key"
    _generate_ssh_key_from_type "$1"
}

# Adds a new SSH key pair without associating it with a host.
generate_ssh_key() {
    printBanner "Add New SSH Key"

    local -a key_types=("ed25519 (recommended)" "rsa (legacy, 4096 bits)")
    local selected_index
    selected_index=$(interactive_menu "single" "Select the type of key to generate:" "" "${key_types[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    # The worker function will now handle the rest of the prompts.
    _generate_ssh_key_from_type "${key_types[$selected_index]}"
}

# Prompts user to select a host and then copies the specified key.
copy_selected_ssh_key() {
    local selected_key="$1"
    printBanner "Copy SSH Key to Server"
    printInfoMsg "key: ${C_L_BLUE}${selected_key/#$HOME/\~}${T_RESET}"

    local selected_host
    selected_host=$(select_ssh_host "Select a host to copy this key to:")
    [[ $? -ne 0 ]] && return

    copy_ssh_id_for_host "$selected_host" "$selected_key"
}

# (Private) Handles inline deletion of an SSH key pair from a list view.
# Clears the footer, prompts for confirmation, and performs deletion.
# This is intended to be called from a key handler to provide an "in-place" action.
# Usage: _inline_remove_ssh_key <key_base_path> <footer_draw_func>
_inline_remove_ssh_key() {
    local key_base_path="$1"
    local footer_draw_func="$2"

    # Move cursor down past the list and its bottom divider.
    local footer_content; footer_content=$("$footer_draw_func"); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
    _clear_list_view_footer "$footer_lines"

    # Build the multi-line question for the prompt.
    local pub_key_path="${key_base_path}.pub"
    printBanner "${C_RED}Delete Key${T_RESET}"
    local question="Are you sure you want to delete this key pair?\n     Private: ${key_base_path/#$HOME/\~}"
    if [[ -f "$pub_key_path" ]]; then question+="\n     Public:  ${pub_key_path/#$HOME/\~}"; fi
    question+="\n\n${C_L_YELLOW}Note: This will move the key pair to ${C_L_BLUE}${SSH_DIR}/.trash/${T_RESET}"

    # Show the prompt in the cleared footer area.
    prompt_yes_no "$question" "n"
    local choice=$?
    if [[ $choice -eq 0 ]]; then
        run_with_spinner "Moving key pair to trash..." _move_key_pair_to_trash "$key_base_path"
        sleep 1
    elif [[ $choice -eq 1 ]]; then
        printInfoMsg "Key pair was ${C_YELLOW}not moved to trash${T_RESET}."
        sleep 1
    fi
}

# Deletes an SSH key pair (private and public files).
delete_ssh_key() {
    local key_base_path="$1"
    local pub_key_path="${key_base_path}.pub"
    printBanner "Delete SSH Key Pair"

    if ! [[ -f "$key_base_path" ]]; then
        printErrMsg "Private key not found: ${key_base_path}"
        return 1
    fi

    local question="Are you sure you want to delete this key pair?\n  Private: ${key_base_path}"
    if [[ -f "$pub_key_path" ]]; then
        question+="\n  Public:  ${pub_key_path}"
    else
        question+="\n  (Public key not found, will only delete private key)"
    fi
    question+="\n\n${C_L_YELLOW}Note: This will move the key pair to ${C_L_BLUE}${SSH_DIR}/.trash/${T_RESET}"

    prompt_yes_no "$question" "n"
    local choice=$?
    if [[ $choice -eq 0 ]]; then
        if run_with_spinner "Moving key pair to trash..." _move_key_pair_to_trash "$key_base_path"; then
            printOkMsg "Key pair moved to ${C_L_BLUE}${SSH_DIR}/.trash/${T_RESET}"
        else
            printErrMsg "Failed to move key pair to trash."
        fi
    elif [[ $choice -eq 1 ]]; then
        printInfoMsg "Key pair was ${C_YELLOW}not moved to trash${T_RESET}."
    fi
}

# Renames an SSH key pair.
rename_ssh_key() {
    local old_key_path="$1"
    printBanner "Rename SSH Key"
    local new_key_filename
    local old_filename; old_filename=$(basename "$old_key_path")
    prompt_for_input "Enter new filename for the key\n (in ${SSH_DIR})" new_key_filename "$old_filename" || return
    local new_key_path="${SSH_DIR}/${new_key_filename}"

    if [[ "$new_key_path" == "$old_key_path" ]]; then
        printInfoMsg "Filename is unchanged. No action taken."
        return
    fi
    if [[ -f "$new_key_path" || -f "${new_key_path}.pub" ]]; then
        printErrMsg "Target key file '${new_key_path/#$HOME/\~}' or its .pub already exists. Aborting."
        return 1
    fi

    if run_with_spinner "Renaming key files..." _rename_key_pair "$old_key_path" "$new_key_path"; then
        printOkMsg "Key renamed successfully."
        printInfoMsg "Note: You must manually update any SSH host configs that used the old key name."
    else
        printErrMsg "Failed to rename key files."
        return 1
    fi
}

# Displays the content of a public key file.
view_public_key() {
    local pub_key_path="$1"
    printBanner "View Public Key"
    if [[ ! -f "$pub_key_path" ]]; then printErrMsg "Public key file not found: ${pub_key_path/#$HOME/\~}"; return 1; fi
    printInfoMsg "Contents of ${C_L_BLUE}${pub_key_path/#$HOME/\~}${T_RESET}:"
    printMsg "${C_GRAY}${DIV}${T_RESET}"
    printMsg "${C_L_GRAY}$(cat "${pub_key_path}")${T_RESET}"
    printMsg "${C_GRAY}${DIV}${T_RESET}"
}

# (Private) Worker for regenerating a public key, for use with run_with_spinner.
_regenerate_public_key_worker() {
    # ssh-keygen -y reads from the private key file and writes the public key to stdout.
    ssh-keygen -y -f "$1" > "$2"
}

# Re-generates a public key from a private key file.
regenerate_public_key() {
    local private_key_path="$1"
    local public_key_path="${private_key_path}.pub"
    printBanner "Re-generate Public Key"

    if [[ ! -f "$private_key_path" ]]; then
        printErrMsg "Private key not found: ${private_key_path/#$HOME/\~}"
        return 1
    fi

    if [[ -f "$public_key_path" ]]; then
        if ! prompt_yes_no "Public key '${public_key_path/#$HOME/\~}' already exists. Overwrite it?" "n"; then
            printInfoMsg "Operation cancelled."
            return
        fi
    fi

    if run_with_spinner "Re-generating public key..." _regenerate_public_key_worker "$private_key_path" "$public_key_path"; then
        printOkMsg "Public key successfully generated at: ${C_L_BLUE}${public_key_path/#$HOME/\~}${T_RESET}"
    else
        printErrMsg "Failed to re-generate public key."
    fi
}

# (Private) Handles the logic for selecting an existing key.
# Returns the path to the selected key via a nameref.
# Usage: _select_and_get_existing_key identity_file_var
# Returns 0 on success, 1 on cancellation/failure.
_select_and_get_existing_key() {
    local -n out_identity_file="$1"
    local -a pub_keys
    mapfile -t pub_keys < <(find "$SSH_DIR" -maxdepth 1 -type f -name "*.pub")
    if [[ ${#pub_keys[@]} -eq 0 ]]; then
        printErrMsg "No existing SSH keys (.pub files) found in ${SSH_DIR}."
        return 1
    fi

    local -a private_key_paths
    local -a display_paths
    for pub_key in "${pub_keys[@]}"; do
        local private_key="${pub_key%.pub}"
        private_key_paths+=("$private_key")
        display_paths+=("${private_key/#$HOME/\~}")
    done

    local key_idx
    key_idx=$(interactive_menu "single" "Select the private key to use:" "" "${display_paths[@]}") || return 1
    out_identity_file="${private_key_paths[$key_idx]}"
    return 0
}

# (Private) Builds a host block as a string. Does not write to any file.
# Usage: _build_host_block_string <alias> <hostname> <user> <port> [identity_file]
_build_host_block_string() {
    local host_alias="$1"
    local host_name="$2"
    local user="$3"
    local port="$4"
    local identity_file="$5"
    local tags="$6"

    # Use a subshell to capture the output of multiple echo commands
    {
        echo "Host ${host_alias}"
        echo "    HostName ${host_name}"
        echo "    User ${user}"
        if [[ -n "$port" && "$port" != "22" ]]; then
            echo "    Port ${port}"
        fi
        if [[ -n "$identity_file" ]]; then
            echo "    IdentityFile ${identity_file}"
            echo "    IdentitiesOnly yes"
        fi
        if [[ -n "$tags" ]]; then
            echo "    # Tags: ${tags}"
        fi
    }
}

# (Private) Appends a fully formed host block to the SSH config file.
# Usage: _append_host_to_config <alias> <hostname> <user> <port> [identity_file]
_append_host_to_config() {
    local host_alias="$1"
    local host_name="$2"
    local user="$3"
    local port="$4"
    local identity_file="$5"
    local tags="$6"

    (
        echo "" # Separator
        _build_host_block_string "$host_alias" "$host_name" "$user" "$port" "$identity_file" "$tags"
    ) >> "$SSH_CONFIG_PATH"

    local key_msg=""
    if [[ -n "$identity_file" ]]; then
        key_msg=" with key ${identity_file/#$HOME/\~}"
    fi
    printOkMsg "Host '${host_alias}' added to ${SSH_CONFIG_PATH}${key_msg}."
}

# (Private) Prompts for a new, unique SSH host alias.
# It allows the user to re-enter an existing alias, which is treated as a no-op if it's the "old" one.
# Uses a nameref to return the value.
# Usage: _prompt_for_unique_host_alias alias_var [prompt_text] [old_alias_to_allow] [default_value]
# Returns 0 on success, 1 on cancellation.
_prompt_for_unique_host_alias() {
    local out_alias_var_name="$1"
    local -n out_alias_var="$out_alias_var_name" # Use a nameref for easier value access/modification internally.
    local prompt_text="${2:-Enter a short alias for the host}"
    local old_alias_to_allow="${3:-}"
    local default_value="${4:-}"

    while true; do
        # Pass the default value, which might be the old alias or the user's previous (invalid) input.
        prompt_for_input "$prompt_text" "$out_alias_var_name" "$default_value" || return 1

        # If renaming and the user entered the old name, it's a valid "no-op" choice.
        if [[ -n "$old_alias_to_allow" && "$out_alias_var" == "$old_alias_to_allow" ]]; then
            return 0
        fi

        # Check if host alias already exists in the main config file.
        if get_ssh_hosts | grep -qFx "$out_alias_var"; then
            show_timed_message "${T_ERR_ICON} Host alias '${out_alias_var}' already exists. Please choose another." 2
            # Set the default for the next loop iteration to what the user just typed, so they can edit it.
            default_value="$out_alias_var"
        else
            return 0 # Alias is unique, success
        fi
    done
}

# --- Host Editor Feature (Private Helpers) ---

# (Private) Formats a line for an interactive editor, showing a change indicator if needed.
# Assumes 'mode' variable is set in the calling scope.
# Usage: _editor_format_line <key> <label> <new_val> <original_val> [is_path] [is_clone_alias]
_editor_format_line() {
    local key="$1" label="$2" new_val="$3" original_val="$4"
    local is_path="${5:-false}"
    local is_clone_alias="${6:-false}"

    local display_val="${new_val}"
    if [[ "$is_path" == "true" ]]; then
        display_val="${new_val/#$HOME/\~}"
    fi
    if [[ -z "$display_val" ]]; then
        display_val="${C_GRAY}(not set)${T_RESET}"
    else
        display_val="${C_L_CYAN}${display_val}${T_RESET}"
    fi

    # Truncate the display value if it's too long to prevent UI overflow.
    # The total width is ~70, label is 15, prefix is ~8. Leaves ~47 for the value.
    local max_val_width=45
    display_val=$(_format_fixed_width_string "$display_val" "$max_val_width")

    local change_indicator=" "
    # In 'add' mode, there are no "changes" from an original, so no indicator.
    if [[ "$mode" != "add" ]]; then
        local val1="$new_val"
        local val2="$original_val"
        if [[ "$is_path" == "true" ]]; then
            val1="${new_val/#\~/$HOME}"
            val2="${original_val/#\~/$HOME}"
        fi
        if [[ "$val1" != "$val2" ]]; then
            change_indicator="${C_L_YELLOW}*${T_RESET}"
        fi
    fi

    # For clone mode, the alias is always considered a change.
    if [[ "$mode" == "clone" && "$is_clone_alias" == "true" ]]; then
        change_indicator="${C_L_YELLOW}*${T_RESET}"
    fi

    printf "  ${C_L_WHITE}%s)${T_RESET} %b %-15s: %s\n" "$key" "$change_indicator" "$label" "$display_val"
}

# (Private) A generic UI drawing function for editors.
# It prints a title, calls a function to draw the fields, and prints a footer.
# Usage: _draw_generic_editor_ui <title> <fields_draw_func>
_draw_generic_editor_ui() {
    local title="$1"
    local fields_draw_func="$2"

    printMsg "$title"

    # Call the function that draws the specific fields
    "$fields_draw_func"

    echo
    printMsg "  ${C_L_WHITE}c) ${C_L_YELLOW}(C)ancel/(D)iscard${T_RESET} all pending changes"
    printMsg "  ${C_L_WHITE}s) ${C_L_GREEN}(S)ave${T_RESET} and Quit"
    printMsg "  ${C_L_WHITE}q) ${C_L_YELLOW}(Q)uit${T_RESET} without saving (or press ${C_L_YELLOW}ESC${T_RESET})"
    echo
    printMsgNoNewline "${T_QST_ICON} Your choice: "
}

# (Private) Draws the fields for the host editor.
_host_editor_draw_fields() {
    _editor_format_line "1" "Host (Alias)" "$new_alias" "$original_alias" "false" "true"
    _editor_format_line "2" "HostName"     "$new_hostname" "$original_hostname"
    _editor_format_line "3" "User"         "$new_user" "$original_user"
    _editor_format_line "4" "Port"         "$new_port" "$original_port"
    _editor_format_line "5" "IdentityFile" "$new_identityfile" "$original_identityfile" "true" "false"
    _editor_format_line "6" "Tags"         "$new_tags" "$original_tags" "false" "false"
}

# (Private) Draws the fields for the port forward editor.
_port_forward_editor_draw_fields() {
    local p1_label="Local Port" h_label="Remote Host" p2_label="Remote Port"
    if [[ "$new_type" == "Remote" ]]; then
        p1_label="Remote Port" h_label="Local Host" p2_label="Local Port"
    fi

    _editor_format_line "1" "Type" "$new_type" "$original_type"
    _editor_format_line "2" "SSH Host" "$new_host" "$original_host"
    _editor_format_line "3" "${p1_label}" "$new_p1" "$original_p1"
    _editor_format_line "4" "${h_label}" "$new_h" "$original_h"
    _editor_format_line "5" "${p2_label}" "$new_p2" "$original_p2"
    _editor_format_line "6" "Description" "$new_desc" "$original_desc" "false" "false"
}

# (Private) Draws the UI for the interactive host editor.
# It assumes all 'new_*' and 'original_*' variables are set in the calling scope.
# It also expects 'mode' to be set.
_host_editor_draw_ui() {
    local title="${C_L_BLUE}┗ Configure the host details:"
    if [[ "$mode" == "add" ]]; then title="${C_L_BLUE}┗ Configure the new host:"; fi
    if [[ "$mode" == "clone" ]]; then title="${C_L_BLUE}┗ Configure the new cloned host:"; fi

    _draw_generic_editor_ui "$title" "_host_editor_draw_fields"
}

# (Private) Handles key presses for the interactive host editor's fields.
# Assumes all 'new_*' and 'original_*' variables are set in the calling scope.
# Returns 0 if the key was handled, 1 otherwise.
_host_editor_field_handler() {
    local key="$1"
    case "$key" in
        '1')
            # Edit Alias
            local prompt="Enter a short alias for the host"
            local old_alias_to_allow=""; clear_current_line
            if [[ "$mode" == "edit" ]]; then prompt="Enter New alias for host"; old_alias_to_allow="$original_alias"; fi
            if [[ "$mode" == "clone" ]]; then prompt="Enter New alias for cloned host"; fi
            _prompt_for_unique_host_alias "new_alias" "$prompt" "$old_alias_to_allow" "$new_alias"
            ;;
        '2') clear_current_line; prompt_for_input "HostName" "new_hostname" "$new_hostname" ;;
        '3') clear_current_line; prompt_for_input "User" "new_user" "$new_user" ;;
        '4') clear_current_line; _prompt_for_valid_port "Port" "new_port" "true" ;;
        '5') clear_screen; printBanner "Edit Host"; _prompt_for_identity_file_interactive "new_identityfile" "$new_identityfile" "$new_alias" "$new_user" "$new_hostname" ;;
        '6') clear_current_line; prompt_for_input "Tags (comma-separated)" "new_tags" "$new_tags" "true" ;;
        *) needs_redraw=false; return 1 ;; # Unhandled key
    esac
    return 0 # Handled key
}

# (Private) Checks if the host editor has unsaved changes.
# Assumes all 'new_*' and 'original_*' variables are set in the calling scope.
# Returns 0 if there are changes, 1 otherwise.
_host_editor_has_changes() {
    local expanded_new_idfile="${new_identityfile/#\~/$HOME}"
    local expanded_orig_idfile="${original_identityfile/#\~/$HOME}"
    if [[ "$new_alias" != "$original_alias" || "$new_hostname" != "$original_hostname" || "$new_user" != "$original_user" || "$new_port" != "$original_port" || "$expanded_new_idfile" != "$expanded_orig_idfile" || "$new_tags" != "$original_tags" ]]; then
        return 0 # true, has changes
    fi
    return 1 # false, no changes
}

# (Private) Resets the host editor fields to their original values.
# Assumes all 'new_*' and 'original_*' variables are set in the calling scope.
_host_editor_reset_fields() {
    new_alias="$original_alias"
    new_hostname="$original_hostname"
    new_user="$original_user"
    new_port="$original_port"
    new_identityfile="$original_identityfile"
    new_tags="$original_tags"
}

# (Private) Interactively prompts the user to select or create an IdentityFile when editing a host.
# This provides a menu-driven alternative to manually typing a file path.
# Usage: _prompt_for_identity_file_interactive <out_var> <current_path> <host_alias> <user> <hostname>
# Returns 0 on success, 1 on cancellation.
_prompt_for_identity_file_interactive() {
    local -n out_identity_file="$1"
    local current_identity_file="$2"
    local host_alias="$3"
    local user="$4"
    local hostname="$5"

    while true; do
        local -a menu_options=()
        local -a option_values=() # Parallel array to hold the real values

        # Option: Keep current
        if [[ -n "$current_identity_file" ]]; then
            menu_options+=("Keep current: ${C_L_GREEN}${current_identity_file/#$HOME/\~}${T_RESET}")
            option_values+=("$current_identity_file")
        fi

        # Option: Remove
        menu_options+=("Remove IdentityFile entry")
        option_values+=("__REMOVE__")

        # Option: Generate new
        menu_options+=("Generate a new dedicated key (ed25519)...")
        option_values+=("__GENERATE__")

        # Find existing private keys to offer as choices
        local -a existing_keys=()
        mapfile -t pub_keys < <(find "$SSH_DIR" -maxdepth 1 -type f -name "*.pub")
        if [[ ${#pub_keys[@]} -gt 0 ]]; then
            for pub_key in "${pub_keys[@]}"; do
                local private_key="${pub_key%.pub}"
                # Only add if it's not the currently selected key
                if [[ "$private_key" != "$current_identity_file" ]]; then
                    existing_keys+=("$private_key")
                fi
            done
        fi

        if [[ ${#existing_keys[@]} -gt 0 ]]; then
            menu_options+=("--- Select an existing key ---")
            option_values+=("__SEPARATOR__")
            for key in "${existing_keys[@]}"; do
                menu_options+=("  ${key/#$HOME/\~}")
                option_values+=("$key")
            done
    fi    

        local selected_index
        selected_index=$(interactive_menu "single" "Select an IdentityFile option for '${host_alias}':" "" "${menu_options[@]}")
        if [[ $? -ne 0 ]]; then return 1; fi # User cancelled

        local selected_value="${option_values[$selected_index]}"

        case "$selected_value" in
            "__SEPARATOR__") continue ;; # Loop to redraw menu
            "__REMOVE__") out_identity_file=""; return 0 ;;
            "__GENERATE__")
                local new_key_filename; local default_key_name="${host_alias}_id_ed25519"
                clear_screen; printBanner "Generate Key"; prompt_for_input "Enter filename for new key (in ${SSH_DIR})" new_key_filename "$default_key_name" || continue
                local new_key_path="${SSH_DIR}/${new_key_filename}"
                if [[ -f "$new_key_path" ]] && ! prompt_yes_no "Key file '${new_key_path}' already exists.\n    Overwrite?" "n"; then
                    printInfoMsg "Key generation cancelled."; continue
                fi
                if run_with_spinner "Generating new ed25519 key..." ssh-keygen -t ed25519 -f "$new_key_path" -N "" -C "${user}@${hostname}"; then
                    out_identity_file="$new_key_path"; return 0
                else printErrMsg "Failed to generate key."; prompt_to_continue; continue; fi ;;
            *) out_identity_file="$selected_value"; return 0 ;;
        esac
    done
}

# --- Host Lifecycle Functions ---

# Prompts user for details and adds a new host to the SSH config.
# This is the primary function for adding a host from scratch, used by both
# the interactive menu and the `-a` command-line flag.
add_ssh_host() {
    printBanner "Add New SSH Host"

    # --- Create from scratch logic ---
    local initial_alias="" initial_hostname="" initial_user="$USER" initial_port="22" initial_identityfile="" initial_tags=""
    local new_alias="$initial_alias" new_hostname="$initial_hostname" new_user="$initial_user" new_port="$initial_port" new_identityfile="$initial_identityfile" new_tags="$initial_tags"

    local banner_text="Add New SSH Host"

    # Call the shared editor loop. It will modify the 'new_*' variables.
    if ! _interactive_editor_loop "add" "$banner_text" \
        "_host_editor_draw_ui" "_host_editor_field_handler" \
        "_host_editor_has_changes" "_host_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    # --- Save Logic ---
    if [[ -z "$new_alias" || -z "$new_hostname" ]]; then
        clear_current_line
        printErrMsg "Host Alias and HostName cannot be empty."; sleep 2; return 1
    fi
    if get_ssh_hosts | grep -qFx "$new_alias"; then
        clear_current_line
        printErrMsg "Host alias '${new_alias}' already exists."; sleep 2; return 1
    fi

    _append_host_to_config "$new_alias" "$new_hostname" "$new_user" "$new_port" "$new_identityfile" "$new_tags"

    if [[ -n "$new_identityfile" ]]; then
        # When creating from scratch, it's more likely the user wants to copy the key immediately.
        if prompt_yes_no "Copy public key to the new server now?" "y"; then copy_ssh_id_for_host "$new_alias" "${new_identityfile}.pub"; fi
    fi
    if prompt_yes_no "Test the connection to '${new_alias}' now?" "y"; then echo; _test_connection_for_host "$new_alias"; fi
}

# (Private) Helper function to copy both private and public key files.
# This is designed to be called by `run_with_spinner`.
# Usage: _copy_key_pair <source_base_path> <dest_base_path>
_copy_key_pair() {
    local source_base="$1"
    local dest_base="$2"
    cp "${source_base}" "${dest_base}" && cp "${source_base}.pub" "${dest_base}.pub"
}

# Edits an existing host in the SSH config.
edit_ssh_host() {
    printBanner "Edit SSH Host"

    local original_alias="$1"
    if [[ -z "$original_alias" ]]; then
        original_alias=$(select_ssh_host "Select a host to edit:")
        [[ $? -ne 0 ]] && return
    fi

    # Get original values to compare against for changes.
    local original_hostname original_user original_port original_identityfile original_tags
    local details; details=$(_get_all_ssh_config_values_as_string "$original_alias")
    # Use parameter expansion to rename the 'current_*' variables from the helper to 'original_*'.
    eval "${details//current/original}" # Sets original_hostname, original_user, original_port
    original_identityfile=$(_get_explicit_ssh_config_value "$original_alias" "IdentityFile")
    original_tags=$(_get_tags_for_host "$original_alias")
    [[ -z "$original_port" ]] && original_port="22"

    # These variables will hold the values as they are being edited.
    local new_alias="$original_alias" new_hostname="$original_hostname" new_user="$original_user" new_port="$original_port" new_identityfile="$original_identityfile" new_tags="$original_tags"

    local banner_text="Edit SSH Host - ${C_L_CYAN}${original_alias}${C_BLUE}"
    if ! _interactive_editor_loop "edit" "$banner_text" \
        "_host_editor_draw_ui" "_host_editor_field_handler" \
        "_host_editor_has_changes" "_host_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    # --- Save Logic ---
    local expanded_new_idfile="${new_identityfile/#\~/$HOME}"; local expanded_orig_idfile="${original_identityfile/#\~/$HOME}"
    if [[ "$new_alias" == "$original_alias" && "$new_hostname" == "$original_hostname" && "$new_user" == "$original_user" && "$new_port" == "$original_port" && "$expanded_new_idfile" == "$expanded_orig_idfile" && "$new_tags" == "$original_tags" ]]; then
        clear_current_line
        printInfoMsg "No changes detected. Host configuration remains unchanged."; sleep 1; return 0
    fi

    # --- Handle Key Management if Alias Changed ---
    if [[ "$new_alias" != "$original_alias" && -n "$new_identityfile" ]]; then
        # This function will prompt the user and may update `new_identityfile`.
        if ! _handle_key_management_on_alias_change new_identityfile "$original_alias" "$new_alias" "$new_identityfile"; then
            printErrMsg "Host update aborted due to key management failure."; sleep 2
            return 1
        fi
    fi

    local config_without_host; config_without_host=$(_remove_host_block_from_config "$original_alias")
    local new_host_block; new_host_block=$(_build_host_block_string "$new_alias" "$new_hostname" "$new_user" "$new_port" "$new_identityfile" "$new_tags")
    printf '%s\n\n%s' "$config_without_host" "$new_host_block" | cat -s > "$SSH_CONFIG_PATH"
    clear_current_line
    if [[ "$new_alias" != "$original_alias" ]]; then
        printOkMsg "Host '${original_alias}' has been updated to '${new_alias}'."
    else
        printOkMsg "Host '${original_alias}' has been updated."
    fi

    if [[ -n "$original_identityfile" && "$expanded_new_idfile" != "$expanded_orig_idfile" ]]; then
        _cleanup_orphaned_key "$original_identityfile"
    fi
}

# (Private) Handles renaming or copying a key file when a host's alias is changed.
# If the key is shared, it offers to copy. If not, it offers to rename.
# The new key path is returned via a nameref.
# Usage: _handle_key_management_on_alias_change new_identityfile_var "$original_alias" "$new_alias" "$current_identityfile"
# Returns 0 on success, 1 on failure.
_handle_key_management_on_alias_change() {
    local -n out_new_identityfile_ref="$1"
    local original_alias="$2"
    local new_alias="$3"
    local current_identityfile="$4"

    # If no identity file is set, there's nothing to do.
    if [[ -z "$current_identityfile" ]]; then
        return 0
    fi

    local expanded_old_key_path="${current_identityfile/#\~/$HOME}"
    if [[ ! -f "$expanded_old_key_path" ]]; then
        # Key file doesn't exist, so nothing to rename/copy.
        return 0
    fi

    # Find if other hosts share this key.
    local -a hosts_sharing_key=()
    mapfile -t all_hosts < <(get_ssh_hosts)
    for other_host in "${all_hosts[@]}"; do
        if [[ "$other_host" != "$original_alias" ]]; then
            local other_host_key; other_host_key=$(_get_explicit_ssh_config_value "$other_host" "IdentityFile")
            if [[ "$other_host_key" == "$current_identityfile" ]]; then
                hosts_sharing_key+=("$other_host")
            fi
        fi
    done

    # Propose a new key name based on the new host alias (convention).
    local proposed_new_key_path="${SSH_DIR}/${new_alias}_id_ed25519"

    if [[ ${#hosts_sharing_key[@]} -gt 0 ]]; then
        # Key is shared, offer to COPY it.
        local question="The key '${current_identityfile/#$HOME/\~}' is shared by other hosts.\n    Do you want to create a dedicated COPY of this key for '${new_alias}'?\n    New key path: ${C_L_BLUE}${proposed_new_key_path/#$HOME/\~}${T_RESET}"
        if prompt_yes_no "$question" "y"; then
            if [[ -f "$proposed_new_key_path" || -f "${proposed_new_key_path}.pub" ]]; then printErrMsg "Cannot create key copy: target file '${proposed_new_key_path/#$HOME/\~}' or its .pub already exists."; return 1; fi
            if run_with_spinner "Copying key files..." _copy_key_pair "$expanded_old_key_path" "$proposed_new_key_path"; then
                out_new_identityfile_ref="$proposed_new_key_path" # Update the nameref to point to the new key path.
            else printErrMsg "Failed to copy key files."; return 1; fi
        fi
    elif [[ "$expanded_old_key_path" != "$proposed_new_key_path" ]]; then
        # Key is not shared, offer to RENAME it.
        local question="This host uses the key:\n    ${C_L_BLUE}${current_identityfile/#$HOME/\~}${T_RESET}\nDo you want to rename this key to match the new host alias?\n    New name: ${C_L_BLUE}${proposed_new_key_path/#$HOME/\~}${T_RESET}"
        if prompt_yes_no "$question" "y"; then
            if [[ -f "$proposed_new_key_path" || -f "${proposed_new_key_path}.pub" ]]; then printErrMsg "Cannot rename key: target file '${proposed_new_key_path/#$HOME/\~}' or its .pub already exists."; return 1; fi
            if run_with_spinner "Renaming key files..." _rename_key_pair "$expanded_old_key_path" "$proposed_new_key_path"; then
                out_new_identityfile_ref="$proposed_new_key_path" # Update the nameref to point to the new key path.
            else printErrMsg "Failed to rename key files."; return 1; fi
        fi
    fi
    return 0
}

# Clones an existing SSH host configuration to a new alias using an interactive UI.
# shellcheck disable=SC2120
clone_ssh_host() {
    local host_to_clone="$1"
    if [[ -z "$host_to_clone" ]]; then
        printBanner "Clone SSH Host"
        host_to_clone=$(select_ssh_host "Select a host to clone:")
        [[ $? -ne 0 ]] && return # select_ssh_host prints messages
    fi

    # Get original values from the source host.
    local original_hostname original_user original_port original_identityfile original_tags
    local details; details=$(_get_all_ssh_config_values_as_string "$host_to_clone")
    eval "${details//current/original}" # Sets original_hostname, original_user, original_port
    original_identityfile=$(_get_explicit_ssh_config_value "$host_to_clone" "IdentityFile")
    original_tags=$(_get_tags_for_host "$host_to_clone")
    [[ -z "$original_port" ]] && original_port="22"

    # These variables will hold the values for the new cloned host.
    local new_hostname="$original_hostname" new_user="$original_user" new_port="$original_port" new_identityfile="$original_identityfile" new_tags="$original_tags"
    # Propose a unique new alias.
    local new_alias i=1
    while true; do
        local proposed_alias="${host_to_clone}-clone"; [[ $i -gt 1 ]] && proposed_alias+="-${i}"
        if ! get_ssh_hosts | grep -qFx "$proposed_alias"; then new_alias="$proposed_alias"; break; fi
        ((i++))
    done

    local banner_text="Clone Host from ${C_L_CYAN}${host_to_clone}${C_BLUE}"
    if ! _interactive_editor_loop "clone" "$banner_text" \
        "_host_editor_draw_ui" "_host_editor_field_handler" \
        "_host_editor_has_changes" "_host_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    # --- Save Logic ---
    if get_ssh_hosts | grep -qFx "$new_alias"; then
        clear_current_line
        printErrMsg "Host alias '${new_alias}' already exists."; sleep 2; return 1
    fi

    _append_host_to_config "$new_alias" "$new_hostname" "$new_user" "$new_port" "$new_identityfile" "$new_tags"

    if [[ -n "$new_identityfile" ]] && prompt_yes_no "Copy public key to the new server now?" "n"; then
        copy_ssh_id_for_host "$new_alias" "${new_identityfile}.pub"
    fi

    if prompt_yes_no "Test the connection to '${new_alias}' now?" "y"; then
        echo; _test_connection_for_host "$new_alias"
    fi
}

# (Private) Checks for and offers to remove an orphaned key file.
# An orphaned key is one that is no longer referenced by any host in the SSH config.
# This is typically called after a host has been removed from the config.
# Usage: _cleanup_orphaned_key <path_to_key_file>
_cleanup_orphaned_key() {
    local key_file_path="$1"

    # 1. If no key file was associated with the host, there's nothing to do.
    if [[ -z "$key_file_path" ]]; then
        return
    fi

    # 2. Expand tilde to full path for checks.
    local expanded_key_path="${key_file_path/#\~/$HOME}"

    # 3. Check if the key file actually exists.
    if [[ ! -f "$expanded_key_path" ]]; then
        return
    fi

    # 4. Check if any other host in the *current* config uses this key.
    mapfile -t remaining_hosts < <(get_ssh_hosts)
    for host in "${remaining_hosts[@]}"; do
        local host_key_file; host_key_file=$(get_ssh_config_value "$host" "IdentityFile")
        local expanded_host_key_file="${host_key_file/#\~/$HOME}"

        if [[ "$expanded_host_key_file" == "$expanded_key_path" ]]; then
            printInfoMsg "The key '${key_file_path/#$HOME/\~}' is still in use by host '${host}'. It will not be removed."
            return # Key is in use, so we're done.
        fi
    done

    # 5. If we get here, the key is not used by any other host. Prompt for deletion.
    local question="The key '${key_file_path/#$HOME/\~}' is no longer referenced by any host.\n    Move it and its .pub file to the trash?"
    if prompt_yes_no "$question" "n"; then
        _move_key_pair_to_trash "$expanded_key_path"
        printOkMsg "Moved orphaned key files to ${C_L_BLUE}${SSH_DIR}/.trash/${T_RESET}"
    fi
}

# (Private) Worker function to perform the host removal and key cleanup.
# Does not prompt the user.
# Usage: _remove_host_and_cleanup <host_to_remove>
_remove_host_and_cleanup() {
    local host_to_remove="$1"

    # Get the IdentityFile path *before* removing the host from the config.
    local identity_file_to_check
    identity_file_to_check=$(_get_explicit_ssh_config_value "$host_to_remove" "IdentityFile")

    # Get the config content without the specified host block
    local new_config_content
    new_config_content=$(_remove_host_block_from_config "$host_to_remove")

    # Overwrite the config file with the new content, squeezing blank lines
    echo "$new_config_content" | cat -s > "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_remove}' has been ${C_RED}DELETED${T_RESET}."

    # Pass the actual key file path to the cleanup function.
    _cleanup_orphaned_key "$identity_file_to_check"
}

# (Private) Handles inline deletion of a host from a list view.
# Clears the footer, prompts for confirmation, and performs deletion.
# This is intended to be called from a key handler to provide an "in-place" action.
# Usage: _inline_remove_ssh_host <host_to_remove> <footer_draw_func>
_inline_remove_ssh_host() {
    local host_to_remove="$1"
    local footer_draw_func="$2"

    # Move cursor down past the list and its top divider.
    local footer_content; footer_content=$("$footer_draw_func"); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
    _clear_list_view_footer "$footer_lines"

    # Show the prompt in the cleared footer area.
    printBanner "${C_RED}Delete / Remove Host${T_RESET}"
    prompt_yes_no "Are you sure you want to ${C_RED}remove${T_RESET} '${host_to_remove}'?\n    This will permanently delete the host from your config." "n"
    local choice=$?
    if [[ $choice -eq 0 ]]; then
        # User confirmed deletion.
        _remove_host_and_cleanup "$host_to_remove"
        sleep 2 # Give user a moment to see the result.
    elif [[ $choice -eq 1 ]]; then
        printInfoMsg "Host '${host_to_remove}' was ${C_YELLOW}not deleted${T_RESET}."
        sleep 1
    fi
}

# Removes a host entry from the SSH config file.
remove_ssh_host() {
    printBanner "Remove SSH Host"

    local host_to_remove="$1"
    if [[ -z "$host_to_remove" ]]; then host_to_remove=$(select_ssh_host "Select a host to remove:"); [[ $? -ne 0 ]] && return; fi

    prompt_yes_no "Are you sure you want to remove '${host_to_remove}'?\n    This will permanently delete the host from your config." "n"
    local choice=$?
    if [[ $choice -eq 0 ]]; then _remove_host_and_cleanup "$host_to_remove";
    elif [[ $choice -eq 1 ]]; then printInfoMsg "Host '${host_to_remove}' was ${C_YELLOW}not deleted${T_RESET}."; fi
}

# (Private) Helper to test connection to a specific host using BatchMode.
# Usage: _test_connection_for_host <host_alias>
_test_connection_for_host() {
    local host_to_test="$1"
    # -o BatchMode=yes: Never ask for passwords.
    # -o ConnectTimeout=5: A shorter timeout is better for quick tests.
    # 'exit' is a simple command that immediately closes the connection upon success.
    if run_with_spinner "Testing connection to '${host_to_test}'..." \
        ssh -o BatchMode=yes -o ConnectTimeout=5 "${host_to_test}" 'exit'
    then
        # remove the spinner output to reduce visual clutter
        clear_lines_up 1
        printOkMsg "Connection to '${host_to_test}' was ${BG_GREEN}${C_BLACK} successful ${T_RESET}"
        return 0
    else
        # run_with_spinner prints the error details from ssh
        printInfoMsg "Check your SSH config, network, firewall rules, and ensure your public key is on the server."
        return 1
    fi
}

# (Private) Helper function to move a key pair to the trash directory.
# This is designed to be called by `run_with_spinner`.
# It ensures the trash directory exists and moves both private and public keys.
# Usage: _move_key_pair_to_trash <key_base_path>
_move_key_pair_to_trash() {
    local key_base_path="$1"
    local trash_dir="${SSH_DIR}/.trash"
    mkdir -p "$trash_dir"

    local key_filename; key_filename=$(basename "$key_base_path")
    local dest_path="${trash_dir}/${key_filename}"

    # Move the private key
    mv "$key_base_path" "$dest_path"

    # Move the public key if it exists
    local pub_key_path="${key_base_path}.pub"
    if [[ -f "$pub_key_path" ]]; then
        mv "$pub_key_path" "${dest_path}.pub"
    fi
}

# (Private) Handles inline connection test to a host from a list view.
# Clears the footer, runs the test, and displays results.
# This is intended to be called from a key handler to provide an "in-place" action.
# Usage: _inline_test_connection <host_to_test> <footer_draw_func>
_inline_test_connection() {
    local host_to_test="$1"
    local footer_draw_func="$2"

    {
        local footer_content; footer_content=$("$footer_draw_func"); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
        _clear_list_view_footer "$footer_lines"
        printBanner "Test SSH Connection"
        _test_connection_for_host "$host_to_test"
        sleep 2
    } >/dev/tty
}

# Tests the SSH connection to a selected server.
test_ssh_connection() {
    printBanner "Test SSH Connection"

    local host_to_test
    host_to_test=$(select_ssh_host "Select a host to test:")
    [[ $? -ne 0 ]] && return

    _test_connection_for_host "$host_to_test"
}

# (Private) The actual test logic for a single host, run in the background.
# It writes its result to a file in a temporary directory.
# Usage: _test_single_host_in_background <host> <result_dir>
_test_single_host_in_background() {
    local host_to_test="$1"
    local result_dir="$2"
    # The result file is named after the host, with slashes replaced to be safe.
    local result_file="${result_dir}/${host_to_test//\//_}"
 
    # Run ssh only ONCE, capturing stderr and checking the exit code.
    # This is much faster for failed connections than running it twice.
    # A shorter timeout (5s) is used to speed up the "all hosts" test.
    local error_output
    if error_output=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${host_to_test}" 'exit' 2>&1); then
        echo "success" > "$result_file"
    else
        # If the command failed but produced no output (e.g., timeout), provide a generic message.
        if [[ -z "$error_output" ]]; then
            echo "Connection timed out or failed without error message." > "$result_file"
        else
            echo "$error_output" > "$result_file"
        fi
    fi
}

# Tests all configured SSH hosts in parallel.
test_all_ssh_connections() {
    printBanner "Test All SSH Connections"

    mapfile -t hosts < <(get_ssh_hosts)
    if [[ ${#hosts[@]} -eq 0 ]]; then
        printInfoMsg "No hosts found in your SSH config file to test."
        return
    fi

    local result_dir
    result_dir=$(mktemp -d)
    # Ensure temp directory is cleaned up on exit or interrupt.
    trap 'rm -rf "$result_dir"' RETURN INT TERM

    local -a pids
    printInfoMsg "Starting tests for ${#hosts[@]} hosts in parallel..."
    for host in "${hosts[@]}"; do
        # Run the test for each host in the background.
        _test_single_host_in_background "$host" "$result_dir" &
        pids+=($!)
    done

    # Wait for all background jobs to complete, with a spinner.
    wait_for_pids_with_spinner "Running all connection tests" "${pids[@]}"

    # --- Print Summary ---
    printMsg "\n${T_ULINE}Test Results:${T_RESET}"
    local success_count=0
    local failure_count=0

    for host in "${hosts[@]}"; do
        local result_file="${result_dir}/${host//\//_}"
        local result
        result=$(<"$result_file")

        if [[ "$result" == "success" ]]; then
            ((success_count++))
            printOkMsg "Connection to '${host}' was ${BG_GREEN}${C_BLACK} successful ${T_RESET}"
        else
            ((failure_count++))
            printErrMsg "${host}"
            # Indent the error message for readability.
            while IFS= read -r line; do
                printMsg "    ${C_GRAY}${line}${T_RESET}"
            done <<< "$result"
        fi
    done

    # Final summary line
    echo
    local summary_msg
    if (( failure_count > 0 )); then
        summary_msg="Summary: ${C_L_GREEN}${success_count} successful${T_RESET}, ${C_L_RED}${failure_count} failed${T_RESET}."
        printErrMsg "$summary_msg"
    else
        summary_msg="Summary: ${C_L_GREEN}${success_count} successful${T_RESET}, ${C_GRAY}${failure_count} failed${T_RESET}."
        printOkMsg "$summary_msg"
    fi
}

# (Private) Reads saved port forwards from the config file.
# Populates arrays with their details.
# Usage: _get_saved_port_forwards types_array specs_array hosts_array descs_array
_get_saved_port_forwards() {
    local -n out_types="$1" out_specs="$2" out_hosts="$3" out_descs="$4"
    out_types=() out_specs=() out_hosts=() out_descs=()
    if [[ ! -f "$PORT_FORWARDS_CONFIG_PATH" ]]; then return 1; fi
    while IFS='|' read -r type spec host desc || [[ -n "$type" ]]; do
        [[ -z "$type" || "$type" =~ ^# ]] && continue
        out_types+=("$type"); out_specs+=("$spec"); out_hosts+=("$host"); out_descs+=("$desc")
    done < "$PORT_FORWARDS_CONFIG_PATH"
}

# (Private) Writes an array of port forward configurations to the file, overwriting it.
# Usage: _save_all_port_forwards types_array specs_array hosts_array descs_array
_save_all_port_forwards() {
    # Use ref_ prefix for namerefs to avoid circular reference if caller uses same variable names.
    local -n ref_types="$1" ref_specs="$2" ref_hosts="$3" ref_descs="$4"
    local temp_file; temp_file=$(mktemp)
    for i in "${!ref_types[@]}"; do echo "${ref_types[i]}|${ref_specs[i]}|${ref_hosts[i]}|${ref_descs[i]}" >> "$temp_file"; done
    mv "$temp_file" "$PORT_FORWARDS_CONFIG_PATH"
}

# --- Port Forwarding Editor Feature (Private Helpers) ---

# (Private) Draws the UI for the interactive port forward editor.
# It assumes all 'new_*' and 'original_*' variables are set in the calling scope.
# It also expects 'mode' to be set.
_port_forward_editor_draw_ui() {
    local title="${C_L_BLUE}┗ Choose an option to configure:"
    if [[ "$mode" == "add" ]]; then title="${C_L_BLUE}┗ Configure the new saved port forward:"; fi
    if [[ "$mode" == "clone" ]]; then title="${C_L_BLUE}┗ Configure the cloned port forward:"; fi

    _draw_generic_editor_ui "$title" "_port_forward_editor_draw_fields"
}

# (Private) Handles key presses for the interactive port forward editor's fields.
# Assumes all 'new_*' and 'original_*' variables are set in the calling scope.
# Returns 0 if the key was handled, 1 otherwise.
_port_forward_editor_field_handler() {
    local key="$1"
    case "$key" in
        '1')
            # Edit Type
            clear_current_line
            local -a type_options=("Local (-L)" "Remote (-R)")
            local type_idx; type_idx=$(interactive_menu "single" "Select forward type:" "" "${type_options[@]}")
            if [[ $? -eq 0 ]]; then if [[ "$type_idx" -eq 0 ]]; then new_type="Local"; else new_type="Remote"; fi; fi
            ;;
        '2')
            # Edit SSH Host
            clear_current_line
            local selected_host; selected_host=$(select_ssh_host "Select a new SSH host:" "true")
            if [[ $? -eq 0 ]]; then new_host="$selected_host"; fi
            ;;
        '3')
            # Edit Port 1
            clear_current_line
            local p1_label="Local Port"; if [[ "$new_type" == "Remote" ]]; then p1_label="Remote Port"; fi
            _prompt_for_valid_port "Enter the ${p1_label} to listen on" "new_p1"
            ;;
        '4')
            # Edit Host
            clear_current_line
            local h_prompt="Enter the REMOTE host to connect to (from ${new_host})"; if [[ "$new_type" == "Remote" ]]; then h_prompt="Enter the LOCAL host to connect to"; fi
            prompt_for_input "$h_prompt" "new_h" "$new_h"
            ;;
        '5')
            # Edit Port 2
            clear_current_line
            local p2_prompt="Enter the REMOTE port to connect to"; if [[ "$new_type" == "Remote" ]]; then p2_prompt="Enter the LOCAL port to connect to"; fi
            _prompt_for_valid_port "$p2_prompt" "new_p2"
            ;;
        '6')
            # Edit Description
            clear_current_line
            prompt_for_input "Enter a short description" "new_desc" "$new_desc" "true"
            ;;
        *) return 1 ;; # Unhandled key
    esac
    return 0 # Handled key
}

# (Private) Checks if the port forward editor has unsaved changes.
_port_forward_editor_has_changes() {
    if [[ "$new_type" != "$original_type" || "$new_p1" != "$original_p1" || "$new_h" != "$original_h" || "$new_p2" != "$original_p2" || "$new_host" != "$original_host" || "$new_desc" != "$original_desc" ]]; then return 0; fi
    return 1
}

# (Private) Resets the port forward editor fields to their original values.
_port_forward_editor_reset_fields() {
    new_type="$original_type"; new_p1="$original_p1"; new_h="$original_h"; new_p2="$original_p2"; new_host="$original_host"; new_desc="$original_desc"
}

# Adds a new port forward configuration to the saved list.
add_saved_port_forward() {
    printBanner "Add New Saved Port Forward"

    # Set up initial empty/default values for the new forward.
    local original_type="Local" original_p1="8080" original_h="localhost" original_p2="80" original_host="" original_desc=""

    # These variables will be modified by the editor loop.
    local new_type="$original_type" new_p1="$original_p1" new_h="$original_h" new_p2="$original_p2" new_host="$original_host" new_desc="$original_desc"

    local banner_text="Add New Saved Port Forward"
    if ! _interactive_editor_loop "add" "$banner_text" \
        "_port_forward_editor_draw_ui" "_port_forward_editor_field_handler" \
        "_port_forward_editor_has_changes" "_port_forward_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    # --- Save Logic ---
    if [[ -z "$new_host" || -z "$new_p1" || -z "$new_h" || -z "$new_p2" ]]; then
        clear_current_line
        printErrMsg "Host and all port/host specifiers are required."; sleep 2; return 1
    fi

    local new_spec="${new_p1}:${new_h}:${new_p2}"
    if [[ -z "$new_desc" ]]; then new_desc="${new_spec} on ${new_host}"; fi

    local -a all_types all_specs all_hosts all_descs; _get_saved_port_forwards all_types all_specs all_hosts all_descs
    all_types+=("$new_type"); all_specs+=("$new_spec"); all_hosts+=("$new_host"); all_descs+=("$new_desc")
    _save_all_port_forwards all_types all_specs all_hosts all_descs
    printOkMsg "Saved new port forward: ${new_desc}"
}

# Edits a saved port forward configuration.
edit_saved_port_forward() {
    local idx_to_edit="$1"
    local -a all_types all_specs all_hosts all_descs; _get_saved_port_forwards all_types all_specs all_hosts all_descs
    local original_type="${all_types[$idx_to_edit]}" original_spec="${all_specs[$idx_to_edit]}" original_host="${all_hosts[$idx_to_edit]}" original_desc="${all_descs[$idx_to_edit]}"

    # Deconstruct spec for editing
    local original_p1="${original_spec%%:*}"; local remote_part="${original_spec#*:}"
    local original_h="${remote_part%:*}"; local original_p2="${remote_part##*:}"

    # Set up variables for the editor loop
    local new_type="$original_type" new_host="$original_host" new_desc="$original_desc"
    local new_p1="$original_p1" new_h="$original_h" new_p2="$original_p2"

    local banner_text="Edit Saved Port Forward - ${C_L_CYAN}${original_desc}${C_BLUE}"
    if ! _interactive_editor_loop "edit" "$banner_text" \
        "_port_forward_editor_draw_ui" "_port_forward_editor_field_handler" \
        "_port_forward_editor_has_changes" "_port_forward_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    local new_spec="${new_p1}:${new_h}:${new_p2}"
    if [[ "$new_type" == "$original_type" && "$new_spec" == "$original_spec" && "$new_host" == "$original_host" && "$new_desc" == "$original_desc" ]]; then
        clear_current_line
        printInfoMsg "No changes detected. Configuration remains unchanged."; sleep 1
        return
    fi

    all_types[$idx_to_edit]="$new_type"
    all_specs[$idx_to_edit]="$new_spec"
    all_hosts[$idx_to_edit]="$new_host"
    all_descs[$idx_to_edit]="$new_desc"
    _save_all_port_forwards all_types all_specs all_hosts all_descs
    printOkMsg "Saved port forward has been updated."
}

# (Private) Handles inline deletion of a saved port forward from a list view.
# Clears the footer, prompts for confirmation, and performs deletion.
# This is intended to be called from a key handler to provide an "in-place" action.
# Usage: _inline_remove_port_forward <payload> <footer_draw_func>
_inline_remove_port_forward() {
    local payload="$1"
    local footer_draw_func="$2"
    local idx type spec host desc pid
    IFS='|' read -r idx type spec host desc pid <<< "$payload"

    # Move cursor down past the list and its top divider.
    local footer_content; footer_content=$("$footer_draw_func"); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
    _clear_list_view_footer "$footer_lines"

    # Show the prompt in the cleared footer area.
    printBanner "${C_RED}Delete / Remove Port Forward${T_RESET}"
    prompt_yes_no "Permanently ${C_RED}delete${T_RESET} saved forward\n     '${spec}' on '${host}'?" "n"
    local choice=$?
    if [[ $choice -eq 0 ]]; then
        delete_saved_port_forward "$idx"
        printOkMsg "${C_RED}Deleted${T_RESET} saved port forward."
        sleep 1
    elif [[ $choice -eq 1 ]]; then
        printInfoMsg "Port forward was ${C_YELLOW}not deleted${T_RESET}."
        sleep 1
    fi
}

# (Private) Handles inline activation/deactivation of a port forward.
# Clears the footer, prompts if needed, and starts/stops the ssh process.
# Usage: _inline_toggle_port_forward <payload> <footer_draw_func>
_inline_toggle_port_forward() {
    local payload="$1"
    local footer_draw_func="$2"
    local idx type spec host desc pid
    IFS='|' read -r idx type spec host desc pid <<< "$payload"

    # Move cursor down past the list and its top divider.
    local footer_content; footer_content=$("$footer_draw_func"); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
    _clear_list_view_footer "$footer_lines"

    if [[ -n "$pid" ]]; then
        # Action: Deactivate
        if prompt_yes_no "Stop port forward\n     ${spec} on ${host}?" "y"; then
            if run_with_spinner "Stopping port forward (PID: ${pid})..." kill "$pid"; then
                printOkMsg "Port forward stopped."
            else
                printErrMsg "Failed to stop port forward process."
            fi
            sleep 1
        fi
    else
        # Action: Activate
        local flag; if [[ "$type" == "Local" ]]; then flag="-L"; else flag="-R"; fi
        if run_with_spinner "Establishing port forward: ${spec}..." ssh -o ExitOnForwardFailure=yes -N -f "${flag}" "${spec}" "${host}"; then
            printOkMsg "Port forward activated in the background."
        else
            printErrMsg "Failed to activate port forward."
        fi
        sleep 1
    fi
}

# Deletes a saved port forward configuration.
# This function only performs the file modification; it does not prompt the user.
delete_saved_port_forward() {
    local idx_to_delete="$1"
    local -a all_types all_specs all_hosts all_descs; _get_saved_port_forwards all_types all_specs all_hosts all_descs
    local -a new_types new_specs new_hosts new_descs
    for i in "${!all_types[@]}"; do
        if [[ "$i" -ne "$idx_to_delete" ]]; then new_types+=("${all_types[i]}"); new_specs+=("${all_specs[i]}"); new_hosts+=("${all_hosts[i]}"); new_descs+=("${all_descs[i]}"); fi
    done
    _save_all_port_forwards new_types new_specs new_hosts new_descs
}

# Clones a saved port forward configuration.
clone_saved_port_forward() {
    local type_to_clone="$1" spec_to_clone="$2" host_to_clone="$3" desc_to_clone="$4"

    # Deconstruct spec for editing
    local original_p1="${spec_to_clone%%:*}"; local remote_part="${spec_to_clone#*:}"
    local original_h="${remote_part%:*}"; local original_p2="${remote_part##*:}"

    # Set up initial values for the new cloned forward
    local new_type="$type_to_clone" new_host="$host_to_clone" new_desc="Clone of ${desc_to_clone}"
    local new_p1=$((original_p1 + 1)) new_h="$original_h" new_p2="$original_p2"

    local banner_text="Clone Saved Port Forward - from ${C_L_CYAN}${desc_to_clone}${C_BLUE}"
    if ! _interactive_editor_loop "clone" "$banner_text" \
        "_port_forward_editor_draw_ui" "_port_forward_editor_field_handler" \
        "_port_forward_editor_has_changes" "_port_forward_editor_reset_fields"; then
        return 2 # User cancelled, signal to run_menu_action to not prompt.
    fi

    local new_spec="${new_p1}:${new_h}:${new_p2}"
    local -a all_types all_specs all_hosts all_descs; _get_saved_port_forwards all_types all_specs all_hosts all_descs
    all_types+=("$new_type"); all_specs+=("$new_spec"); all_hosts+=("$new_host"); all_descs+=("$new_desc")
    _save_all_port_forwards all_types all_specs all_hosts all_descs
    clear_current_line
    printOkMsg "Saved cloned port forward."
}

# (Private) Formats a line for displaying port forward information with colors.
# Usage: _format_port_forward_line <pid> <type> <spec> <host>
_format_port_forward_line() {
    local pid="$1"
    local type="$2"
    local spec="$3"
    local host="$4"

    local type_color=""
    if [[ "$type" == "Local" ]]; then
        type_color="$C_L_CYAN"
    elif [[ "$type" == "Remote" ]]; then
        type_color="$C_L_YELLOW"
    fi

    # PID is default, Type is colored, Spec is white, Host is cyan.
    printf "%-10s ${type_color}%-8s ${C_L_WHITE}%-30s ${C_L_CYAN}%s" \
        "$pid" \
        "$type" \
        "$spec" \
        "$host"
}
# (Private) Finds active port forwards and populates arrays with their details.
# Usage: _get_active_port_forwards pids_array types_array specs_array hosts_array
# Returns 0 if forwards are found, 1 otherwise.
_get_active_port_forwards() {
    local -n out_pids="$1"
    local -n out_types="$2"
    local -n out_specs="$3"
    local -n out_hosts="$4"

    # Clear output arrays
    out_pids=()
    out_types=()
    out_specs=()
    out_hosts=()

    local active_forwards
    # Use awk to find processes that are ssh and contain all the necessary flags for a backgrounded port forward.
    # This is more robust than a simple grep, as it is not dependent on the order of arguments (e.g., -o).
    # It looks for 'ssh', '-N', '-f', and either '-L' or '-R'.
    active_forwards=$(ps -eo pid,command | awk '/[s]sh/ && /-N/ && /-f/ && /-[LR]/')

    if [[ -z "$active_forwards" ]]; then
        return 1 # No forwards found
    fi

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}" # Use parameter expansion to trim leading whitespace
        local pid; pid=$(echo "$line" | cut -d' ' -f1)
        local cmd; cmd=$(echo "$line" | cut -d' ' -f2-)
        local type_flag current_spec current_host
        local -a parts=($cmd)
        for i in "${!parts[@]}"; do
            if [[ "${parts[$i]}" == "-L" || "${parts[$i]}" == "-R" ]]; then
                type_flag="${parts[$i]}"; current_spec="${parts[$i+1]}"; break
            fi
        done
        current_host="${parts[-1]}"
        local type_str="Unknown"
        [[ "$type_flag" == "-L" ]] && type_str="Local"
        [[ "$type_flag" == "-R" ]] && type_str="Remote"

        out_pids+=("$pid")
        out_types+=("$type_str")
        out_specs+=("$current_spec")
        out_hosts+=("$current_host")
    done <<< "$active_forwards"

    return 0
}

# Lists all active SSH port forwards found by the script.
list_active_port_forwards() {
    printBanner "Active Port Forwards"

    local -a pids types specs hosts
    if ! _get_active_port_forwards pids types specs hosts; then
        printInfoMsg "No active SSH port forwards started by this script were found."
        return
    fi

    local header; header=$(printf "%-10s %-8s %-30s %s" "PID" "TYPE" "FORWARD" "HOST")
    printMsg "  ${C_WHITE}${header}${T_RESET}"

    for i in "${!pids[@]}"; do
        printMsg "  $(_format_port_forward_line "${pids[i]}" "${types[i]}" "${specs[i]}" "${hosts[i]}")${T_RESET}"
    done

    # empty line for spacing
    printMsg ""
}

# Lists all configured SSH hosts with details.
list_all_hosts() {
    printBanner "List All Configured Hosts"

    local -a menu_options data_payloads
    # Get detailed host list, including key info.
    get_detailed_ssh_hosts_menu_options menu_options data_payloads "true" ""

    if [[ ${#menu_options[@]} -eq 0 ]]; then
        printInfoMsg "No hosts found in your SSH config file matching the current filter."
        return
    fi

    local header
    header=$(printf "%-20s %s" "HOST ALIAS" "user@hostname[:port]")
    printMsg "${C_WHITE}${header}${T_RESET}"
    printMsg "${C_GRAY}${DIV}${T_RESET}"

    for option in "${menu_options[@]}"; do
        # The menu options are already formatted with colors.
        printMsg "${option}${T_RESET}"
    done

    # add space
    printMsg ""
}

# --- Port Forwarding View Helpers ---

# (Private) Formats a line for displaying a saved port forward.
# Usage: _format_saved_port_forward_line <status> <pid> <type> <spec> <host> <desc>
_format_saved_port_forward_line() {
    local status="$1" pid="$2" type="$3" spec="$4" host="$5" desc="$6"; local type_color=""
    if [[ "$type" == "Local" ]]; then type_color="$C_L_BLUE"; elif [[ "$type" == "Remote" ]]; then type_color="$C_L_YELLOW"; fi
    local status_icon; if [[ "$status" == "active" ]]; then status_icon="${C_L_GREEN}[✓]"; else status_icon="${C_GRAY}[-]"; fi
    
    host=$(_format_fixed_width_string "$host" 20)
    spec=$(_format_fixed_width_string "$spec" 45)
    desc=$(_format_fixed_width_string "$desc" 45)

    local line1; line1=$(printf "${C_L_CYAN}%s${C_L_WHITE} %s" "$host" "$spec")

    # The second line is indented to appear nested under the first.
    local line2; line2=$(printf "%-3s %-8s${type_color} %-7s${C_L_WHITE} %s" "$status_icon" "${pid:-off}" "$type" "$desc")

    printf "%s\n%s${T_RESET}" "$line1" "$line2"
}

_port_forward_view_draw_header() {
    local header1 header2
    header1=$(printf "${C_L_BLUE}┃${T_RESET}  %-20s %-45s" "HOST" "FORWARD")
    # The second header line is indented to match the item's second line.
    header2=$(printf "${C_L_BLUE}┃${T_RESET}  %-3s %-8s %-7s %-45s" "[ ]" "PID" "TYPE" "DESCRIPTION")
    printMsg "${C_WHITE}${header1}${T_RESET}"
    printMsg "${C_WHITE}${header2}${T_RESET}"
}

_port_forward_view_draw_footer() {
    printMsg "  ${T_BOLD}Actions:${T_RESET}      ${C_L_GREEN}(A)dd${T_RESET} | ${C_L_RED}(D)elete${T_RESET} | ${C_L_CYAN}(E)dit${T_RESET} | ${C_L_BLUE}(C)lone${T_RESET} | ${C_L_GREEN}ENTER${T_RESET} Start/Stop"
    printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/j${T_RESET} Move Down | ${C_L_CYAN}↑/k${T_RESET} Move up${T_RESET}               │ ${C_L_YELLOW}Q/ESC${T_RESET} Back"
}

_port_forward_view_refresh() {
    local -n out_menu_options="$1" out_data_payloads="$2"; out_menu_options=(); out_data_payloads=()
    local -a saved_types saved_specs saved_hosts saved_descs; _get_saved_port_forwards saved_types saved_specs saved_hosts saved_descs
    local -a active_pids active_types active_specs active_hosts; _get_active_port_forwards active_pids active_types active_specs active_hosts
    local -A active_map
    for i in "${!active_pids[@]}"; do
        local key="${active_types[i]}|${active_specs[i]}|${active_hosts[i]}"; active_map["$key"]="${active_pids[i]}"
    done
    for i in "${!saved_types[@]}"; do
        local type="${saved_types[i]}" spec="${saved_specs[i]}" host="${saved_hosts[i]}" desc="${saved_descs[i]}"
        local key="${type}|${spec}|${host}"
        local status status_pid
        if [[ -n "${active_map[$key]}" ]]; then status="active"; status_pid="${active_map[$key]}"; else status="inactive"; status_pid=""; fi
        out_menu_options+=("$(_format_saved_port_forward_line "$status" "$status_pid" "$type" "$spec" "$host" "$desc")")
        out_data_payloads+=("$i|$type|$spec|$host|$desc|$status_pid")
    done
}

_port_forward_view_key_handler() {
    local key="$1"
    local selected_payload="$2"
    # local selected_index="$3" # Unused before move
    local -n current_option_ref="$4"
    local num_options="$5"
    local -n out_result="$6"

    out_result="noop"
    local idx type spec host desc pid
    if [[ -n "$selected_payload" ]]; then IFS='|' read -r idx type spec host desc pid <<< "$selected_payload"; fi
    case "$key" in
        'a'|'A') run_menu_action "add_saved_port_forward"; out_result="refresh" ;;
        'e'|'E') if [[ -n "$selected_payload" ]]; then run_menu_action "edit_saved_port_forward" "$idx"; out_result="refresh"; fi ;;
        'd'|'D')
            if [[ -n "$selected_payload" ]]; then
                _inline_remove_port_forward "$selected_payload" "_port_forward_view_draw_footer"
                out_result="refresh"
            fi ;;
        'c'|'C') if [[ -n "$selected_payload" ]]; then run_menu_action "clone_saved_port_forward" "$type" "$spec" "$host" "$desc"; out_result="refresh"; fi ;;
        "$KEY_ENTER")
            if [[ -n "$selected_payload" ]]; then
                _inline_toggle_port_forward "$selected_payload" "_port_forward_view_draw_footer"
                out_result="refresh"
            fi ;;
        "$KEY_ESC"|"q"|"Q") out_result="exit" ;; # Exit view
    esac
}

interactive_port_forward_view() {
    _interactive_list_view \
        "Saved ${C_L_CYAN}Port Forwards${C_BLUE}" \
        "_port_forward_view_draw_header" \
        "_port_forward_view_refresh" \
        "_port_forward_view_key_handler" \
        "_port_forward_view_draw_footer"
}

# --- Host-Centric Main View Helpers ---

_host_centric_view_draw_footer() {
    # This function now depends on _HOST_VIEW_FOOTER_EXPANDED being set in its calling scope.
    local filter_text=""
    if [[ -n "${_HOST_VIEW_CURRENT_FILTER:-}" ]]; then
        filter_text="${C_L_YELLOW}(F)ilter: ${_HOST_VIEW_CURRENT_FILTER}${T_RESET} | C(l)ear"
    else
        filter_text="${C_L_YELLOW}(F)ilter${T_RESET} by tag or alias"
    fi

    if [[ "${_HOST_VIEW_FOOTER_EXPANDED:-0}" -eq 1 ]]; then
        printMsg "  ${T_BOLD}Host Actions:${T_RESET} ${C_L_GREEN}(A)dd${T_RESET} | ${C_L_RED}(D)elete${T_RESET} | ${C_L_BLUE}(C)lone${T_RESET}           │ ${C_BLUE}? fewer options${T_RESET}"
        printMsg "  ${T_BOLD}Host Edit:${T_RESET}    ${C_L_CYAN}(E)dit${T_RESET} host details                  │ ${C_L_YELLOW}Q/ESC (Q)uit${T_RESET}"
        printMsg "  ${T_BOLD}Filter:${T_RESET}       ${filter_text}"
        printMsg "  ${T_BOLD}Manage:${T_RESET}       SSH ${C_MAGENTA}(K)eys${T_RESET} | ${C_L_CYAN}(P)ort${T_RESET} Forwards"
        printMsg "                ${C_L_BLUE}(O)pen${T_RESET} ssh config in editor"
        printMsg "  ${T_BOLD}Connection:${T_RESET}   ${C_L_YELLOW}ENTER${T_RESET} Connect | (${C_L_CYAN}t${T_RESET})est selected | (${C_L_CYAN}T${T_RESET})est all"
        printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/j${T_RESET} Move Down | ${C_L_CYAN}↑/k${T_RESET} Move up${T_RESET}"
    else
        printMsg "  ${T_BOLD}Host Actions:${T_RESET} ${C_L_GREEN}(A)dd${T_RESET} | ${C_L_RED}(D)elete${T_RESET} | ${C_L_BLUE}(C)lone${T_RESET}           │ ${C_BLUE}? more options${T_RESET}"
        printMsg "  ${T_BOLD}Host Edit:${T_RESET}    ${C_L_CYAN}(E)dit${T_RESET} host details                  │ ${C_L_YELLOW}Q/ESC (Q)uit${T_RESET}"
        printMsg "  ${T_BOLD}Filter:${T_RESET}       ${filter_text}"
    fi
}

_host_centric_view_key_handler() {
    local key="$1"
    local selected_host="$2"
    # local selected_index="$3" # Unused before move
    local -n current_option_ref="$4"
    local num_options="$5"
    local -n out_result="$6"

    out_result="noop"
    case "$key" in
        '/'|'?')
            # Delegate to the shared footer toggle handler.
            _handle_footer_toggle "_host_centric_view_draw_footer" "_HOST_VIEW_FOOTER_EXPANDED"
            out_result="partial_redraw"
            ;;
        "$KEY_ENTER")
            if [[ -n "$selected_host" ]]; then
                {
                    clear_screen
                    exec ssh "$selected_host"
                } >/dev/tty
                # If exec fails, we might get here. Redraw to be safe.
                    out_result="refresh"
            fi
            ;;
        'a'|'A')
            # `run_menu_action` clears the screen and `add_ssh_host`
            # handles the entire interactive flow for adding a new host from scratch.
            run_menu_action "add_ssh_host"
            out_result="refresh"
            ;;
        'e'|'E') if [[ -n "$selected_host" ]]; then run_menu_action "edit_ssh_host" "$selected_host"; out_result="refresh"; fi ;;
        'd'|'D')
            if [[ -n "$selected_host" ]]; then
                _inline_remove_ssh_host "$selected_host" "_host_centric_view_draw_footer"
                out_result="refresh"
            fi
            ;;
        'c'|'C') if [[ -n "$selected_host" ]]; then run_menu_action "clone_ssh_host" "$selected_host"; out_result="refresh"; fi ;;
        't')
            if [[ -n "$selected_host" ]]; then
                _inline_test_connection "$selected_host" "_host_centric_view_draw_footer"
                out_result="refresh"
            fi
            ;;
        'T')
            run_menu_action "test_all_ssh_connections"
            out_result="refresh" # Trigger a full redraw to restore the view.
            ;;
        'K')
            # This is a view change, not a simple action.
            # We don't use run_menu_action because it clears and prompts.
            # The sub-view will handle clearing the screen.
            interactive_key_management_view
            out_result="refresh" # Redraw main view when returning
            ;;
        'p'|'P')
            interactive_port_forward_view
            out_result="refresh"
            ;;
        'o'|'O')
            _launch_editor_for_config
            out_result="refresh"
            ;;
        'f'|'F')
            # Move cursor down past the list and its bottom divider.
            local footer_content; footer_content=$(_host_centric_view_draw_footer); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
            _clear_list_view_footer "$footer_lines"
            # Show cursor for input
            printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
            printBanner "Filter by Tag or Alias"
            prompt_for_input "Enter text to filter by (leave empty to clear)" "_HOST_VIEW_CURRENT_FILTER" "${_HOST_VIEW_CURRENT_FILTER:-}" "true"
            # Hide cursor again before redrawing the list view
            printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
            out_result="refresh"
            ;;
        'l'|'L')
            # Clear filter
            if [[ -n "${_HOST_VIEW_CURRENT_FILTER:-}" ]]; then
                _HOST_VIEW_CURRENT_FILTER=""
                out_result="refresh"
            fi
            ;;
        "$KEY_ESC"|"q"|"Q") out_result="exit" ;; # Exit script
    esac
}

interactive_host_centric_view() {
    # This variable will be visible to the functions called by _interactive_list_view
    # because they are executed in the same shell process, not a subshell.
    local _HOST_VIEW_FOOTER_EXPANDED=0
    local _HOST_VIEW_CURRENT_FILTER=""

    _interactive_list_view \
        "SSH Manager" \
        "_common_host_view_draw_header" \
        "_common_host_view_refresh" \
        "_host_centric_view_key_handler" \
        "_host_centric_view_draw_footer"
}

# --- Key Management View Helpers ---

_key_view_draw_header() {
    local header; header=$(printf "%-25s %-10s %-6s %-23s" "KEY FILENAME" "TYPE" "BITS" "COMMENT")
    printMsg "${C_L_BLUE}┗${C_WHITE}  ${header}${T_RESET}"
}

_key_view_draw_footer() {
    printMsg "  ${T_BOLD}Key Actions:${T_RESET}  ${C_L_GREEN}(A)dd${T_RESET} | ${C_L_RED}(D)elete${T_RESET} | ${C_L_CYAN}(R)ename${T_RESET}               │ ${C_L_YELLOW}Q/ESC${T_RESET} Back"
    printMsg "                ${C_L_BLUE}(C)opy${T_RESET} to server | ${C_L_CYAN}(V)iew${T_RESET} public | Re-gen ${C_L_CYAN}(P)ublic${T_RESET}"
    printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/j${T_RESET} Move Down | ${C_L_CYAN}↑/k${T_RESET} Move up${T_RESET}"
}

# (Private) Verifies a file is a valid private key and extracts its details.
_get_key_details() {
    local key_file="$1"
    local details
    # Heuristic: A file whose first line looks like a public key is not a private key.
    if head -n 1 "$key_file" 2>/dev/null | grep -q -E '^(ssh-(rsa|dss|ed25519)|ecdsa-sha2-nistp(256|384|521)) '; then return 1; fi
    # Attempt to get the key fingerprint. If this fails, it's not a valid key file.
    details=$(ssh-keygen -l -f "$key_file" 2>/dev/null)
    if [[ -z "$details" || $(echo "$details" | wc -l) -ne 1 ]]; then return 1; fi
    local bits; bits=$(echo "$details" | awk '{print $1}')
    local type; type=$(echo "$details" | awk '{print $NF}' | tr -d '()')
    local comment; comment=$(echo "$details" | awk '{for(i=3;i<NF;i++) printf "%s ",$i}' | sed 's/ $//')
    comment="${comment% }" # Use parameter expansion to trim trailing space
    [[ -z "$comment" ]] && comment="(no comment)"
    echo "$type $bits $comment"
}

_key_view_refresh() {
    local -n out_menu_options="$1"
    local -n out_data_payloads="$2"
    out_data_payloads=()
    out_menu_options=()
    # Find all files in SSH_DIR that do NOT end in .pub, then verify they are valid private keys.
    while IFS= read -r key_path; do
        local details_str
        if details_str=$(_get_key_details "$key_path"); then
            out_data_payloads+=("$key_path")
            local filename; filename=$(basename "$key_path")
            local key_type key_bits key_comment
            read -r key_type key_bits key_comment <<< "$details_str"

            filename=$(_format_fixed_width_string "$filename" 25)
            key_comment=$(_format_fixed_width_string "$key_comment" 23)

            local formatted_string
            formatted_string=$(printf "${C_MAGENTA}%s ${C_YELLOW}%-10s ${C_WHITE}%-6s %s" "${filename}" "${key_type}" "${key_bits}" "${key_comment}")
            out_menu_options+=("$formatted_string")
        fi
    done < <(find "$SSH_DIR" -maxdepth 1 -type f ! -name "*.pub")
}

_key_view_key_handler() {
    local key="$1"
    local selected_key_path="$2"
    # local selected_index="$3" # Unused before move
    local -n current_option_ref="$4"
    local num_options="$5"
    local -n out_result="$6"

    out_result="noop"
    case "$key" in
        'a'|'A')
            # Move cursor down past the list and its bottom divider.
            local footer_content; footer_content=$(_key_view_draw_footer); local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)
            _clear_list_view_footer "$footer_lines"
            # Show the prompt in the cleared footer area.
            printBanner "${C_GREEN}Add New SSH Key${T_RESET}"
            local -a key_types=("ed25519 (recommended)" "rsa (legacy, 4096 bits)")
            local selected_index
            selected_index=$(interactive_menu "single" "Select the type of key to generate:" "" "${key_types[@]}")

            if [[ $? -eq 0 ]]; then
                # A selection was made. Now clear the screen and run the rest of the wizard.
                run_menu_action "_generate_ssh_key_from_type_with_banner" "${key_types[$selected_index]}"
            fi
            out_result="refresh" ;;
        'c'|'C')
            if [[ -n "$selected_key_path" ]]; then
                if [[ -f "${selected_key_path}.pub" ]]; then
                    run_menu_action "copy_selected_ssh_key" "${selected_key_path}.pub"
                else
                    # This path doesn't use run_menu_action, so we handle the UI manually.
                    clear_screen; printErrMsg "Public key for '${selected_key_path/#$HOME/\~}' not found."; prompt_to_continue
                fi
                # In either case, the screen was cleared, so a full refresh is needed.
                out_result="refresh"
            fi ;;
        'd'|'D')
            if [[ -n "$selected_key_path" ]]; then
                _inline_remove_ssh_key "$selected_key_path" "_key_view_draw_footer"
                out_result="refresh"
            fi ;;
        'r'|'R')
            if [[ -n "$selected_key_path" ]]; then run_menu_action "rename_ssh_key" "$selected_key_path"; out_result="refresh"; fi ;;
        'v'|'V')
            if [[ -n "$selected_key_path" ]]; then
                if [[ -f "${selected_key_path}.pub" ]]; then
                    run_menu_action "view_public_key" "${selected_key_path}.pub"
                else
                    clear_screen; printErrMsg "Public key for '${selected_key_path/#$HOME/\~}' not found."; prompt_to_continue
                fi
                out_result="refresh"
            fi ;;
        'p'|'P')
            if [[ -n "$selected_key_path" ]]; then run_menu_action "regenerate_public_key" "$selected_key_path"; out_result="refresh"; fi ;;
        "$KEY_ESC"|"q"|"Q")
            out_result="exit" ;; # Exit view
    esac
}

interactive_key_management_view() {
    _interactive_list_view \
        "${C_MAGENTA}Key${C_BLUE} Management" \
        "_key_view_draw_header" \
        "_key_view_refresh" \
        "_key_view_key_handler" \
        "_key_view_draw_footer"
}

# Bypasses the main menu and goes directly to the host selection for a direct connection.
direct_connect() {
    local selected_host
    selected_host=$(select_ssh_host "Select a host to connect to:")
    if [[ $? -eq 0 ]]; then
        # Clear the screen before exec'ing to avoid leaving the TUI visible.
        clear_screen; exec ssh "$selected_host"
    fi
    # If selection is cancelled, the script will just exit.
    # select_ssh_host prints a cancellation message, so we exit with a non-zero status
    # to indicate the requested action was not completed.
    exit 1
}

# Bypasses the main menu and goes directly to testing connections.
# Handles interactive selection, a specific host, or all hosts.
direct_test() {
    local target="$1"

    if [[ -z "$target" ]]; then
        # No target specified, run interactive selection.
        # This function already has a banner, so we just call it.
        test_ssh_connection
        return
    fi

    if [[ "$target" == "all" ]]; then
        # Target is 'all', test all connections.
        test_all_ssh_connections
        return
    fi

    # Target is a specific host. First, validate it exists.
    # Use grep with -F (fixed string) and -x (exact line match) for robust validation.
    if get_ssh_hosts | grep -qFx "$target"; then
        printBanner "Test SSH Connection"
        _test_connection_for_host "$target"
    else
        printErrMsg "Host '${target}' not found in your SSH config."
        return 1
    fi
}

# (Private) Ensures core prerequisites are met and SSH directory/config are set up.
_setup_core_environment() {
    _ensure_ssh_dir_and_config
    prereq_checks "$@"
}

# (Private) Ensures prerequisites are met and SSH directory/config are set up.
# Usage: _setup_environment "cmd1" "cmd2" ...
_setup_environment() {
    _ensure_ssh_dir_and_config
    prereq_checks "$@"
    touch "$PORT_FORWARDS_CONFIG_PATH"; chmod 600 "$PORT_FORWARDS_CONFIG_PATH"
}

# Main application loop.
main_loop() {
    interactive_host_centric_view
    clear_screen
    printOkMsg "Goodbye!"
}

main() {
    # Handle flags first
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -a|--add)
                # Prereqs for add mode
                _setup_environment "ssh" "ssh-keygen" "ssh-copy-id" "awk" "grep"
                # The add_ssh_host function is fully interactive and self-contained.
                add_ssh_host
                exit 0
                ;;
            -p|--port-forward)
                # Prereqs for port forwarding. ps and kill are for managing forwards.
                _setup_environment "ssh" "awk" "grep" "ps" "kill"
                # The view is self-contained and has its own loop.
                interactive_port_forward_view
                exit 0
                ;;
            -l|--list-hosts)
                # Prereqs for listing hosts.
                _setup_environment "ssh" "awk" "grep"
                list_all_hosts
                exit 0
                ;;
            -f|--list-forwards)
                # Prereqs for listing port forwards.
                _setup_environment "ps" "grep"
                list_active_port_forwards
                exit 0
                ;;
            -c|--connect | -t|--test)
                # Prereqs for connect and test modes are the same
                _setup_environment "ssh" "awk" "grep" "tput"
                if [[ "$1" == "-c" || "$1" == "--connect" ]]; then
                    direct_connect
                    # direct_connect either execs or exits, so we shouldn't get here.
                    exit 1
                else
                    # The second argument ($2) is the target for the test.
                    direct_test "$2"
                    exit $?
                fi
                ;;
            *)
                print_usage
                echo
                printErrMsg "Unknown option: $1"
                exit 1
                ;;
        esac
    fi

    # Default interactive mode (no flags)
    _setup_environment "ssh" "ssh-keygen" "ssh-copy-id" "awk" "cat" "grep" "rm" "mktemp" "cp" "date" "tput" "wc"

    main_loop
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
