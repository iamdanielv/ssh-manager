#!/bin/bash
# Advanced tools for managing SSH configuration.


# Source the main script to inherit all shared utility functions.
# This makes this script dependent on `ssh-manager.sh` being in the same directory.
if ! source "$(dirname "${BASH_SOURCE[0]}")/ssh-manager.sh"; then
    echo "Error: Could not source ssh-manager.sh. Make sure it is in the same directory." >&2
    exit 1
fi

# --- Script Functions ---

print_usage() {
    printBanner "Advanced SSH Manager Tools"
    printMsg "A collection of advanced tools for managing your SSH configuration."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [option]"
    printMsg "\nThis script is fully interactive."
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}     Show this help message"
}

edit_ssh_host_in_editor() {
    printBanner "Edit Host Block in Editor"
    local host_to_edit="$1"; if [[ -z "$host_to_edit" ]]; then host_to_edit=$(select_ssh_host "Select a host to edit:"); [[ $? -ne 0 ]] && return; fi
    local original_block; original_block=$(_get_host_block_from_config "$host_to_edit" "$SSH_CONFIG_PATH")
    if [[ -z "$original_block" ]]; then printErrMsg "Could not find a configuration block for '${host_to_edit}'."; return 1; fi
    local temp_file; temp_file=$(mktemp --suffix=.sshconfig); trap 'rm -f "$temp_file"' RETURN
    echo "# vim: set filetype=sshconfig:" > "$temp_file"; echo "$original_block" >> "$temp_file"
    local editor="${EDITOR:-nvim}"; if ! command -v "${editor}" &>/dev/null; then printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."; return 1; fi
    printInfoMsg "Opening '${host_to_edit}' in '${editor}'..."; printInfoMsg "(Save and close the editor to apply changes,\n    or exit without saving to cancel)"; prompt_to_continue
    clear_lines_up 3; "${editor}" "$temp_file"
    local new_block; new_block=$(grep -v "vim: set filetype=sshconfig:" "$temp_file")
    if [[ "$new_block" == "$original_block" ]]; then printInfoMsg "No changes detected.\n    Configuration for '${host_to_edit}' remains unchanged."; return; fi
    local config_without_host; config_without_host=$(_remove_host_block_from_config "$host_to_edit")
    printf '%s\n\n%s' "$config_without_host" "$new_block" | cat -s > "$SSH_CONFIG_PATH"
    printOkMsg "Host '${host_to_edit}' has been updated from editor."
}

open_ssh_config_in_editor() {
    printBanner "Open SSH Config in Editor"
    local editor="${EDITOR:-nvim}"
    if ! command -v "${editor}" &>/dev/null; then
        printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."
    else
        printInfoMsg "Opening ${SSH_CONFIG_PATH} in '${editor}'..."
        # run_menu_action (the caller) handles showing/hiding cursor
        "${editor}" "${SSH_CONFIG_PATH}"
    fi
}

export_ssh_hosts() {
    printBanner "Export SSH Hosts"; mapfile -t hosts < <(get_ssh_hosts)
    if [[ ${#hosts[@]} -eq 0 ]]; then printInfoMsg "No hosts found to export."; return; fi
    local -a menu_options; get_detailed_ssh_hosts_menu_options menu_options
    local menu_output; local header; header=$(printf "     %-20s ${C_WHITE}%s${T_RESET}" "HOST ALIAS" "user@hostname[:port]")
    menu_output=$(interactive_multi_select_menu "Select hosts to export (space to toggle, enter to confirm):" "$header" "All" "${menu_options[@]}")
    if [[ $? -ne 0 ]]; then printInfoMsg "Export cancelled."; return; fi
    mapfile -t selected_indices < <(echo "$menu_output")
    if [[ ${#selected_indices[@]} -eq 0 ]]; then printInfoMsg "No hosts selected for export."; return; fi
    local -a hosts_to_export; for index in "${selected_indices[@]}"; do if (( index > 0 )); then hosts_to_export+=("${hosts[index-1]}"); fi; done
    if [[ ${#hosts_to_export[@]} -eq 0 ]]; then printInfoMsg "No hosts selected for export."; return; fi
    local export_file; prompt_for_input "Enter path for export file" export_file "ssh_hosts_export.conf"; local expanded_export_file="${export_file/#\~/$HOME}"
    true > "$expanded_export_file"; printInfoMsg "Exporting ${#hosts_to_export[@]} host(s)..."
    for host in "${hosts_to_export[@]}"; do echo "" >> "$expanded_export_file"; _get_host_block_from_config "$host" "$SSH_CONFIG_PATH" >> "$expanded_export_file"; done
    # Remove the initial blank line that was added before the first block.
    # This is a pure-bash alternative to `sed -i '1{/^$/d;}'`.
    local temp_file; temp_file=$(mktemp)
    {
        read -r first_line # Read the first line (which should be blank)
        # If the first line was NOT blank (edge case), print it back.
        if [[ -n "$first_line" ]]; then echo "$first_line"; fi
        cat # Print the rest of the file.
    } < "$expanded_export_file" > "$temp_file" && mv "$temp_file" "$expanded_export_file"
    printOkMsg "Successfully exported ${#hosts_to_export[@]} host(s) to ${C_L_BLUE}${expanded_export_file/#$HOME/\~}${T_RESET}."
}

import_ssh_hosts() {
    printBanner "Import SSH Hosts";
    printMsg "    ${C_YELLOW}ESC${T_RESET} to cancel"
    local import_file; prompt_for_input "Enter path of file to import from" import_file; local expanded_import_file="${import_file/#\~/$HOME}"
    if [[ ! -f "$expanded_import_file" ]]; then printErrMsg "Import file not found: ${expanded_import_file/#$HOME/\~}"; return 1; fi
    local -a hosts_to_import; mapfile -t hosts_to_import < <(awk '/^[Hh]ost / && $2 != "*" {for (i=2; i<=NF; i++) print $i}' "$expanded_import_file")
    if [[ ${#hosts_to_import[@]} -eq 0 ]]; then printInfoMsg "No valid 'Host' entries found in ${expanded_import_file/#$HOME/\~}."; return; fi
    printInfoMsg "Found ${#hosts_to_import[@]} host(s) to import: ${C_L_CYAN}${hosts_to_import[*]}${T_RESET}"
    local imported_count=0 overwritten_count=0 skipped_count=0
    for host in "${hosts_to_import[@]}"; do
        if grep -q -E "^\s*Host\s+${host}\s*$" "$SSH_CONFIG_PATH"; then
            prompt_yes_no "Host '${host}' already exists. Overwrite it?" "n"; local choice=$?
            case $choice in
                0) local config_without_host; config_without_host=$(_remove_host_block_from_config "$host"); local new_block; new_block=$(_get_host_block_from_config "$host" "$expanded_import_file"); printf '%s\n\n%s' "$config_without_host" "$new_block" | cat -s > "$SSH_CONFIG_PATH"; ((overwritten_count++)) ;;
                1) printInfoMsg "Skipping existing host '${host}'."; ((skipped_count++)) ;;
                2) printInfoMsg "Import operation cancelled by user."; break ;;
            esac
        else echo "" >> "$SSH_CONFIG_PATH"; _get_host_block_from_config "$host" "$expanded_import_file" >> "$SSH_CONFIG_PATH"; ((imported_count++)); fi
    done
    local summary="Import complete. Added: ${imported_count}, Overwrote: ${overwritten_count}, Skipped: ${skipped_count}."; printOkMsg "$summary"
}

backup_ssh_config() {
    if ! prompt_yes_no "Create a timestamped backup of your SSH config file?" "y" >/dev/tty; then
        printInfoMsg "Backup cancelled."
        return
    fi
    local backup_dir="${SSH_DIR}/backups"; mkdir -p "$backup_dir"
    local timestamp; timestamp=$(date +"%Y-%m-%d_%H-%M-%S"); local backup_file="${backup_dir}/config_${timestamp}.bak"
    if run_with_spinner "Creating backup of ${SSH_CONFIG_PATH}..." cp "$SSH_CONFIG_PATH" "$backup_file"; then
        printInfoMsg "Backup saved to: ${C_L_BLUE}${backup_file/#$HOME/\~}${T_RESET}"
    else printErrMsg "Failed to create backup."; fi
}

_setup_environment() {
    prereq_checks "$@"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"; touch "$SSH_CONFIG_PATH"; chmod 600 "$SSH_CONFIG_PATH"
}

# --- Main Menu View Helpers ---

_advanced_host_view_draw_footer() {
    if [[ "${_ADVANCED_VIEW_FOOTER_EXPANDED:-0}" -eq 1 ]]; then
        printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/↑/j/k${T_RESET} Move | ${C_L_YELLOW}Q/ESC (Q)uit${T_RESET} | ${C_BLUE}? for fewer options${T_RESET}"
        printMsg "  ${T_BOLD}Shortcuts:${T_RESET}    ${C_L_BLUE}(O)pen${T_RESET} ssh config in editor"
        printMsg "                ${C_L_CYAN}ENTER/E (E)dit${T_RESET} Selected"
        printMsg "                ${C_L_GREEN}(B)ackup${T_RESET} config"
        printMsg "                ${C_L_YELLOW}E(x)port${T_RESET} to file | ${C_L_YELLOW}(I)mport${T_RESET} from file"
    else
        printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/↑/j/k${T_RESET} Move | ${C_L_YELLOW}Q/ESC (Q)uit${T_RESET} | ${C_BLUE}? for more options${T_RESET}"
    fi
}

_advanced_host_view_key_handler() {
    local key="$1"
    local selected_host="$2"
    # local selected_index="$3" # Unused
    local -n current_option_ref="$4"
    local num_options="$5"
    local -n out_result="$6"

    out_result="noop" # Default to redraw

    case "$key" in
        '/'|'?')
            {
                local old_footer_content; old_footer_content=$(_advanced_host_view_draw_footer)
                local old_footer_lines; old_footer_lines=$(echo -e "$old_footer_content" | wc -l)

                # Toggle the state. The variable is defined in the calling scope of _interactive_list_view.
                _ADVANCED_VIEW_FOOTER_EXPANDED=$(( 1 - ${_ADVANCED_VIEW_FOOTER_EXPANDED:-0} ))

                # --- Perform the partial redraw without a full refresh ---
                # The cursor is at the end of the list, before the divider. Move down into the footer area.
                printf '\n'

                # Clear the old footer area (the footer text + the final bottom divider).
                clear_lines_down $(( old_footer_lines + 1 ))

                # Now, print the new footer and its final bottom divider.
                _advanced_host_view_draw_footer
                printMsg "${C_GRAY}${DIV}${T_RESET}"

                # Move the cursor back to where the main loop expects it (end of list).
                local new_footer_lines; new_footer_lines=$(echo -e "$(_advanced_host_view_draw_footer)" | wc -l)
                move_cursor_up $(( new_footer_lines + 2 ))
            } >/dev/tty
            ;;
        "$KEY_ENTER"|'e'|'E')
            if [[ -n "$selected_host" ]]; then
                run_menu_action "edit_ssh_host_in_editor" "$selected_host"
                out_result="refresh"
            fi
            ;;
        'o'|'O')
            run_menu_action "open_ssh_config_in_editor"
            out_result="refresh"
            ;;
        'b'|'B')
            {
                _clear_list_view_footer "_advanced_host_view_draw_footer"
                printMsgNoNewline "${T_CURSOR_SHOW}"
                printBanner "Backup SSH Config"

                backup_ssh_config

                printMsgNoNewline "${T_CURSOR_HIDE}"
                # Wait a moment for the user to see the result before redrawing.
                sleep 1
            } >/dev/tty
            out_result="refresh" # Redraw the view
            ;;
        'x'|'X')
            run_menu_action "export_ssh_hosts"
            out_result="refresh"
            ;;
        'i'|'I')
            run_menu_action "import_ssh_hosts"
            out_result="refresh"
            ;;
        'q'|'Q'|"$KEY_ESC")
            out_result="exit"
            ;;
    esac
}

interactive_advanced_host_view() {
    # This variable is visible to the key handler and footer functions called by _interactive_list_view.
    local _ADVANCED_VIEW_FOOTER_EXPANDED=0

    _interactive_list_view \
        "Advanced SSH Manager" \
        "_common_host_view_draw_header" \
        "_common_host_view_refresh" \
        "_advanced_host_view_key_handler" \
        "_advanced_host_view_draw_footer"
}

main_loop() {
    interactive_advanced_host_view
    clear
    printOkMsg "Goodbye!"
}

main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help) print_usage; exit 0 ;;
            *) print_usage; echo; printErrMsg "Unknown option: $1"; exit 1 ;;
        esac
    fi
    _setup_environment "ssh" "awk" "cat" "grep" "rm" "mktemp" "cp" "date"
    main_loop
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi