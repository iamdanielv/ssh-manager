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
    if [[ "$new_block" == "$original_block" ]]; then printInfoMsg "No changes detected. Configuration for '${host_to_edit}' remains unchanged."; return; fi
    local config_without_host; config_without_host=$(_remove_host_block_from_config "$host_to_edit")
    printf '%s\n\n%s' "$config_without_host" "$new_block" | cat -s > "$SSH_CONFIG_PATH"
    printOkMsg "Host '${host_to_edit}' has been updated from editor."
}

interactive_reorder_menu() {
    if ! [[ -t 0 ]]; then printErrMsg "Not an interactive session." >&2; return 1; fi
    local prompt="$1"; shift; local -a current_items=("$@"); local num_items=${#current_items[@]}
    if [[ $num_items -eq 0 ]]; then printErrMsg "No items provided to reorder menu." >&2; return 1; fi
    local current_pos=0; local held_item_idx=-1
    _draw_reorder_menu() {
        local output=""; for i in "${!current_items[@]}"; do
            local pointer=" "; local highlight_start=""; local highlight_end=""
            if (( i == current_pos )); then pointer="${T_BOLD}${C_L_MAGENTA}❯${T_RESET}"; fi
            if (( i == held_item_idx )); then highlight_start="${T_REVERSE}"; highlight_end="${T_RESET}"; fi
            output+="  ${pointer} ${highlight_start}${current_items[i]}${T_CLEAR_LINE}${highlight_end}${T_RESET}"$'\n'; done;
        printf '%s' "$output"; }
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty; trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty' EXIT
    printf '%s\n' "${T_QST_ICON} ${prompt}" >/dev/tty; printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty
    _draw_reorder_menu >/dev/tty
    printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty
    printf '%s(%s↓/↑%s move, %sspace%s grab/drop, %senter%s save, %sq/esc%s cancel)%s\n' "${C_GRAY}" "${C_L_CYAN}" "${C_GRAY}" "${C_L_CYAN}" "${C_GRAY}" "${C_L_GREEN}" "${C_GRAY}" "${C_L_YELLOW}" "${C_GRAY}" "${T_RESET}" >/dev/tty

    move_cursor_up 2

    local key; local lines_above=2; local lines_below=2; while true; do
        move_cursor_up "$num_items"; key=$(read_single_char </dev/tty)
        case "$key" in
            "$KEY_UP"|"k")
                if (( held_item_idx != -1 )); then
                    if (( held_item_idx > 0 )); then local next_idx=$((held_item_idx - 1)); local tmp="${current_items[held_item_idx]}"; current_items[held_item_idx]="${current_items[next_idx]}"; current_items[next_idx]="$tmp"; held_item_idx=$next_idx; current_pos=$next_idx; fi
                else current_pos=$(( (current_pos - 1 + num_items) % num_items )); fi;;
            "$KEY_DOWN"|"j")
                if (( held_item_idx != -1 )); then
                    if (( held_item_idx < num_items - 1 )); then local next_idx=$((held_item_idx + 1)); local tmp="${current_items[held_item_idx]}"; current_items[held_item_idx]="${current_items[next_idx]}"; current_items[next_idx]="$tmp"; held_item_idx=$next_idx; current_pos=$next_idx; fi
                else current_pos=$(( (current_pos + 1) % num_items )); fi;;
            ' ') (( held_item_idx == current_pos )) && held_item_idx=-1 || held_item_idx=$current_pos ;;
            "$KEY_ENTER") clear_lines_down $((num_items + lines_below)); clear_lines_up "$lines_above"; printf "%s\n" "${current_items[@]}"; return 0;;
            "$KEY_ESC"|"q") clear_lines_down $((num_items + lines_below)); clear_lines_up "$lines_above"; return 1;;
        esac; _draw_reorder_menu >/dev/tty; done
}

_reorder_ssh_hosts_worker() {
    local backup_file="$1"; shift; local -a new_ordered_hosts=("$@")
    local header_content; header_content=$(awk '/^[ \t]*[Hh][Oo][Ss][Tt][ \t]/ {exit} 1' "$backup_file")
    local footer_content; footer_content=$(_get_host_block_from_config "*" "$backup_file")
    local -A host_blocks; mapfile -t original_hosts < <(get_ssh_hosts); for host in "${original_hosts[@]}"; do host_blocks["$host"]=$(_get_host_block_from_config "$host" "$backup_file"); done
    echo -n "$header_content" > "$SSH_CONFIG_PATH"
    for host in "${new_ordered_hosts[@]}"; do printf '\n%s' "${host_blocks[$host]}" >> "$SSH_CONFIG_PATH"; done
    if [[ -n "$footer_content" ]]; then printf '\n%s' "${footer_content}" >> "$SSH_CONFIG_PATH"; fi
    local temp_file; temp_file=$(mktemp); cat -s "$SSH_CONFIG_PATH" > "$temp_file" && mv "$temp_file" "$SSH_CONFIG_PATH"
}

reorder_ssh_hosts() {
    printBanner "Re-order SSH Hosts"; mapfile -t original_hosts < <(get_ssh_hosts)
    if [[ ${#original_hosts[@]} -lt 2 ]]; then printInfoMsg "Fewer than two hosts found. Nothing to re-order."; return; fi
    local reordered_output; reordered_output=$(interactive_reorder_menu "Re-order hosts:" "${original_hosts[@]}"); [[ $? -ne 0 ]] && { printInfoMsg "Re-ordering cancelled."; return; }
    mapfile -t new_ordered_hosts <<< "$reordered_output"
    if [[ "${new_ordered_hosts[*]}" == "${original_hosts[*]}" ]]; then printInfoMsg "Order is unchanged. No action taken."; return; fi
    printWarnMsg "This action will rewrite your SSH config file to apply the new order."
    if ! prompt_yes_no "This may lose comments between hosts. A backup will be created.\n    Continue with re-ordering?" "n"; then printInfoMsg "Re-ordering cancelled."; return; fi
    local backup_dir="${SSH_DIR}/backups"; mkdir -p "$backup_dir"; local timestamp; timestamp=$(date +"%Y-%m-%d_%H-%M-%S"); local backup_file="${backup_dir}/config_reorder_${timestamp}.bak"
    cp "$SSH_CONFIG_PATH" "$backup_file"; printInfoMsg "Backup created at: ${C_L_BLUE}${backup_file/#$HOME/\~}${T_RESET}"
    if run_with_spinner "Applying new host order..." _reorder_ssh_hosts_worker "$backup_file" "${new_ordered_hosts[@]}"; then
        printOkMsg "SSH config file has been re-ordered successfully."
    else printErrMsg "Failed to re-order hosts. Your original config is safe."; printInfoMsg "The backup of your config is available at: ${backup_file/#$HOME/\~}"; fi
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
    printBanner "Backup SSH Config"
    if ! prompt_yes_no "Create a timestamped backup of your SSH config file?" "y"; then
        printInfoMsg "Backup cancelled."
        return
    fi
    local backup_dir="${SSH_DIR}/backups"; mkdir -p "$backup_dir"
    local timestamp; timestamp=$(date +"%Y-%m-%d_%H-%M-%S"); local backup_file="${backup_dir}/config_${timestamp}.bak"
    if run_with_spinner "Creating backup of ${SSH_CONFIG_PATH}..." cp "$SSH_CONFIG_PATH" "$backup_file"; then
        printInfoMsg "Backup saved to: ${C_L_BLUE}${backup_file/#$HOME/\~}${T_RESET}"
    else printErrMsg "Failed to create backup."; fi
}

run_menu_action() {
    local action_func="$1"; shift; clear
    printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    "$action_func" "$@"
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    prompt_to_continue
}

_setup_environment() {
    prereq_checks "$@"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"; touch "$SSH_CONFIG_PATH"; chmod 600 "$SSH_CONFIG_PATH"
}

# --- Main Menu View Helpers ---

_advanced_menu_view_draw_header() {
    printMsg "${T_QST_ICON} What would you like to do?"
}

_advanced_menu_view_draw_footer() {
    printMsg "  ${T_BOLD}Navigation:${T_RESET}   ${C_L_CYAN}↓/↑/j/k${T_RESET} Move | ${C_L_YELLOW}Q/ESC Quit${T_RESET}"
    printMsg "  ${T_BOLD}Shortcuts:${T_RESET}    ${C_BLUE}(O)pen${T_RESET} | ${C_BLUE}(E)dit${T_RESET} | ${C_MAGENTA}(R)e-order${T_RESET} | ${C_L_GREEN}(B)ackup${T_RESET}"
    printMsg "                ${C_YELLOW}E(x)port${T_RESET} | ${C_YELLOW}(I)mport${T_RESET} | ${C_YELLOW}Q)uit${T_RESET}"
}

_advanced_menu_view_refresh() {
    local -n out_menu_options="$1"
    local -n out_data_payloads="$2"
    local -a items=(
        "${C_L_BLUE}(O)pen${T_RESET} full SSH config in editor"
        "${C_L_BLUE}(E)dit${T_RESET} a specific host's block in editor"
        "${C_L_MAGENTA}(R)e-order${T_RESET} hosts in config"
        "${C_L_GREEN}(B)ackup${T_RESET} config"
        "${C_L_YELLOW}E(x)port${T_RESET} selected hosts to a new file"
        "${C_L_YELLOW}(I)mport${T_RESET} hosts from a file"
        "${C_L_YELLOW}(Q)uit${T_RESET}"
    )

    # Find the maximum visible length and store stripped items
    local max_len=0
    local -a stripped_items=()
    for item in "${items[@]}"; do
        local stripped_item; stripped_item=$(strip_ansi_codes "$item")
        stripped_items+=("$stripped_item")
        if (( ${#stripped_item} > max_len )); then
            max_len=$(( ${#stripped_item} + 1 ))
        fi
    done

    # Build the final menu options array, padding each item to the max length
    out_menu_options=()
    for i in "${!items[@]}"; do
        local padding_len=$(( max_len - ${#stripped_items[i]} ))
        local padded_item
        printf -v padded_item "%s%*s" "${items[i]}" "$padding_len" ""
        out_menu_options+=("$padded_item")
    done

    out_data_payloads=(
        "open"
        "edit"
        "reorder"
        "backup"
        "export"
        "import"
        "quit"
    )
}

_perform_advanced_menu_action() {
    local action="$1"
    local -n out_result_ref="$2"

    case "$action" in
        "open")
            clear; printBanner "Open SSH Config in Editor"
            local editor="${EDITOR:-nvim}"
            if ! command -v "${editor}" &>/dev/null; then
                printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."; prompt_to_continue
            else
                printInfoMsg "Opening ${SSH_CONFIG_PATH} in '${editor}'..."
                printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
                "${editor}" "${SSH_CONFIG_PATH}"
                printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
            fi
            ;;
        "edit") run_menu_action "edit_ssh_host_in_editor" ;;
        "reorder") run_menu_action "reorder_ssh_hosts" ;;
        "backup") run_menu_action "backup_ssh_config" ;;
        "export") run_menu_action "export_ssh_hosts" ;;
        "import") run_menu_action "import_ssh_hosts" ;;
        "quit") out_result_ref="exit" ;;
    esac

    if [[ "$out_result_ref" != "exit" ]]; then
        out_result_ref="refresh"
    fi
}

_advanced_menu_view_key_handler() {
    local key="$1"
    local selected_action="$2"
    # local selected_index="$3" # Unused
    local -n current_option_ref="$4"
    local num_options="$5"
    local -n out_result="$6"

    out_result="noop" # Default to redraw

    case "$key" in
        "$KEY_UP"|"k") if (( num_options > 0 )); then current_option_ref=$(( (current_option_ref - 1 + num_options) % num_options )); fi ;;
        "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option_ref=$(( (current_option_ref + 1) % num_options )); fi ;;
        "$KEY_ENTER") if [[ -n "$selected_action" ]]; then _perform_advanced_menu_action "$selected_action" out_result; fi ;;
        'o'|'O') _perform_advanced_menu_action "open" out_result ;;
        'e'|'E') _perform_advanced_menu_action "edit" out_result ;;
        'r'|'R') _perform_advanced_menu_action "reorder" out_result ;;
        'b'|'B') _perform_advanced_menu_action "backup" out_result ;;
        'x'|'X') _perform_advanced_menu_action "export" out_result ;;
        'i'|'I') _perform_advanced_menu_action "import" out_result ;;
        'q'|'Q'|"$KEY_ESC") _perform_advanced_menu_action "quit" out_result ;;
    esac
}

interactive_advanced_menu_view() {
    _interactive_list_view \
        "Advanced SSH Manager Tools" \
        "_advanced_menu_view_draw_header" \
        "_advanced_menu_view_refresh" \
        "_advanced_menu_view_key_handler" \
        "_advanced_menu_view_draw_footer"
}

main_loop() {
    interactive_advanced_menu_view
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