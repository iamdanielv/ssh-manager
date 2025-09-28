#!/bin/bash
# An interactive TUI for managing and connecting to SSH hosts.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# --- Shared Utilities ---

#region Colors and Styles
export C_RED=$'\033[31m'
export C_GREEN=$'\033[32m'
export C_YELLOW=$'\033[33m'
export C_BLUE=$'\033[34m'
export C_MAGENTA=$'\033[35m'
export C_CYAN=$'\033[36m'
export C_WHITE=$'\033[37m'
export C_GRAY=$'\033[38;5;244m'
export C_L_RED=$'\033[31;1m'
export C_L_GREEN=$'\033[32m'
export C_L_YELLOW=$'\033[33m'
export C_L_BLUE=$'\033[34m'
export C_L_MAGENTA=$'\033[35m'
export C_L_CYAN=$'\033[36m'
export C_L_WHITE=$'\033[37;1m'
export C_L_GRAY=$'\033[38;5;252m'

# Background Colors
export BG_BLACK=$'\033[40;1m'
export BG_RED=$'\033[41m'
export BG_GREEN=$'\033[42;1m'
export BG_YELLOW=$'\033[43m'
export BG_BLUE=$'\033[44m'

export C_BLACK=$'\033[30;1m'

export T_RESET=$'\033[0m'
export T_BOLD=$'\033[1m'
export T_ULINE=$'\033[4m'
export T_REVERSE=$'\033[7m'
export T_CLEAR_LINE=$'\033[K'
export T_CURSOR_HIDE=$'\033[?25l'
export T_CURSOR_SHOW=$'\033[?25h'
export T_FG_RESET=$'\033[39m' # Reset foreground color only
export T_BG_RESET=$'\033[49m' # Reset background color only

export T_ERR="${T_BOLD}${C_L_RED}"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
export T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"
#endregion Colors and Styles

export DIV="──────────────────────────────────────────────────────────────────────"

#region Key Codes
export KEY_ESC=$'\033'
export KEY_UP=$'\033[A'
export KEY_DOWN=$'\033[B'
export KEY_RIGHT=$'\033[C'
export KEY_LEFT=$'\033[D'
export KEY_ENTER="ENTER"
export KEY_TAB=$'\t'
export KEY_BACKSPACE=$'\x7f' # ASCII DEL character for backspace
export KEY_HOME=$'\033[H'
export KEY_END=$'\033[F'
export KEY_DELETE=$'\033[3~'
#endregion Key Codes

#region Logging & Banners
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }

strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

generate_banner_string() {
    local text="$1"; local total_width=70; local prefix="┏"; local line
    printf -v line '%*s' "$((total_width - 1))"; line="${line// /━}"; printf '%s' "${C_L_BLUE}${prefix}${line}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$text" $((total_width - 3)))
    printf '%s' "${C_L_BLUE}${prefix} ${text_to_print} ${T_RESET}"
}

_format_fixed_width_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then
        local padding_needed=$(( max_len - len ))
        printf "%s%*s" "$input_str" "$padding_needed" ""
    else
        _truncate_string "$input_str" "$max_len" "$trunc_char"
    fi
}

format_menu_lines() {
    local -a lines=("$@"); local -a formatted_lines=(); local total_width=70
    for line in "${lines[@]}"; do formatted_lines+=("$(_format_fixed_width_string "   ${line}" "$total_width")"); done
    (IFS=$'\n'; echo "${formatted_lines[*]}")
}

printBanner() { printMsg "$(generate_banner_string "$1")"; }
#endregion Logging & Banners

#region Terminal Control
clear_screen() { printf '\033[H\033[J' >/dev/tty; }
clear_current_line() { printf '\033[2K\r' >/dev/tty; }
clear_lines_up() {
    local lines=${1:-1}; for ((i = 0; i < lines; i++)); do printf '\033[1A\033[2K'; done; printf '\r'
} >/dev/tty
clear_lines_down() {
    local lines=${1:-1}; if (( lines <= 0 )); then return; fi
    for ((i = 0; i < lines; i++)); do printf '\033[2K\n'; done; printf '\033[%sA' "$lines"
} >/dev/tty
move_cursor_up() {
    local lines=${1:-1}; if (( lines > 0 )); then for ((i = 0; i < lines; i++)); do printf '\033[1A'; done; fi; printf '\r'
} >/dev/tty
#endregion Terminal Control

#region User Input
read_single_char() {
    local char; local seq; IFS= read -rsn1 char
    if [[ -z "$char" ]]; then echo "$KEY_ENTER"; return; fi
    if [[ "$char" == "$KEY_ESC" ]]; then
        while IFS= read -rsn1 -t 0.001 seq; do char+="$seq"; done
    fi
    echo "$char"
}

prompt_to_continue() {
    printInfoMsg "Press any key to continue..." >/dev/tty
    read_single_char >/dev/null </dev/tty
    clear_lines_up 1
}

# Prints a message for a fixed duration, then clears it. Does not wait for user input.
# Useful for brief status updates that don't require user acknowledgement.
# Usage: show_timed_message "My message" [duration]
show_timed_message() {
    local message="$1"
    local duration="${2:-1.5}"

    # Calculate how many lines the message will take up to clear it correctly.
    # This is important for multi-line messages (e.g., from terminal wrapping).
    local message_lines; message_lines=$(echo -e "$message" | wc -l)

    printMsg "$message" >/dev/tty
    sleep "$duration"
    # Also redirect to /dev/tty to ensure it works when stdout is captured.
    clear_lines_up "$message_lines" >/dev/tty
}

# (Private) Clears the footer area of an interactive list view.
# The cursor is expected to be at the end of the list content (before the divider).
# The function leaves the cursor at the start of the now-cleared footer area.
# Usage: _clear_list_view_footer <footer_draw_func_name>
_clear_list_view_footer() {
    local footer_draw_func="$1"

    # The cursor is at the end of the list content.
    # Move down one line to be past the list's bottom divider.
    printf '\n' >/dev/tty

    # Calculate how many lines the footer is currently using by calling its draw function.
    local footer_content; footer_content=$("$footer_draw_func")
    local footer_lines; footer_lines=$(echo -e "$footer_content" | wc -l)

    # The area to clear is the footer text + the final bottom divider line.
    local lines_to_clear=$(( footer_lines + 1 ))
    clear_lines_down "$lines_to_clear" >/dev/tty

    # The cursor is now at the start of where the footer text was, ready for new output.
}

# (Private) Handles the common keypress logic for toggling an expanded footer in a list view.
# It assumes the cursor is at the end of the list content, before the divider.
# It uses a nameref to modify the caller's state variable.
# Usage: _handle_footer_toggle footer_draw_func_name expanded_state_var_name
_handle_footer_toggle() {
    local footer_draw_func="$1"
    local -n is_expanded_ref="$2" # Nameref to the state variable

    {
        local old_footer_content; old_footer_content=$("$footer_draw_func")
        local old_footer_lines; old_footer_lines=$(echo -e "$old_footer_content" | wc -l)

        # Toggle the state
        is_expanded_ref=$(( 1 - is_expanded_ref ))

        # --- Perform the partial redraw without a full refresh ---
        # The cursor is at the end of the list, before the divider. Move down into the footer area.
        printf '\n'

        # Clear the old footer area (the footer text + the final bottom divider).
        clear_lines_down $(( old_footer_lines + 1 ))

        # Now, print the new footer.
        "$footer_draw_func"

        # Move the cursor back to where the main loop expects it (end of list).
        local new_footer_lines; new_footer_lines=$(echo -e "$("$footer_draw_func")" | wc -l) # The +1 is for the divider we removed
        move_cursor_up $(( new_footer_lines + 1 ))
    } >/dev/tty
}
#endregion User Input

#region Error Handling & Traps
script_exit_handler() { printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; }
trap 'script_exit_handler' EXIT
script_interrupt_handler() {
    trap - INT; clear_screen; printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"; exit 130
}
trap 'script_interrupt_handler' INT
#endregion Error Handling & Traps

#region Interactive Menus

# (Private) Draws a single item for an interactive menu or list.
# This function encapsulates the complex logic for single-line, multi-line,
# and highlighted rendering, promoting DRY principles.
#
# Usage: _draw_menu_item <is_current> <is_selected> <is_multi_select> <option_text>
_draw_menu_item() {
    local is_current="$1" is_selected="$2" is_multi_select="$3" option_text="$4"
    local output=""

    # Determine checkbox and pointer display
    local pointer=" "
    local checkbox=" " # one space for alignment
    if [[ "$is_multi_select" == "true" ]]; then
        checkbox="_" # Default unchecked state
        if [[ "$is_selected" == "true" ]]; then
            checkbox="${T_BOLD}${C_GREEN}✓${T_RESET}"
        fi
    fi
    if [[ "$is_current" == "true" ]]; then
        pointer="${T_BOLD}${C_L_MAGENTA}❯${T_RESET}"
        if [[ "$is_multi_select" == "true" ]]; then
            # Override color for highlighted checkbox
            if [[ "$is_selected" == "true" ]]; then checkbox="${C_GREEN}✓${T_RESET}"; else checkbox="_"; fi
        fi
    fi

    # Handle single vs. multi-line items
    if [[ "$option_text" != *$'\n'* ]]; then
        # --- Single-line item ---
        local formatted_line; formatted_line=$(_format_fixed_width_string "$option_text" 67)
        if [[ "$is_current" == "true" ]]; then
            formatted_line="${formatted_line//${T_REVERSE}/}"
            formatted_line="${formatted_line//${T_FG_RESET}/${C_L_BLUE}}"
            # formatted_line="${C_L_BLUE}${formatted_line}${T_FG_RESET}"
            formatted_line="${formatted_line//${T_RESET}/${T_RESET}${C_L_BLUE}${T_REVERSE}}"
            output+="${pointer}${checkbox}${T_REVERSE}${C_L_BLUE}╶${formatted_line}${T_CLEAR_LINE}${T_RESET}"$'\n'
        else
            output+="${pointer}${checkbox}╶${formatted_line}${T_CLEAR_LINE}${T_RESET}"$'\n'
        fi
    else
        # --- Multi-line item ---
        local -a lines; mapfile -t lines <<< "$option_text"
        for j in "${!lines[@]}"; do
            local line_prefix="│"
            if (( j == 0 )); then line_prefix="┌"; fi
            if (( j == ${#lines[@]} - 1 )); then line_prefix="└"; fi
            if (( ${#lines[@]} == 1 )); then line_prefix=" "; fi

            local formatted_line; formatted_line=$(_format_fixed_width_string "${lines[j]}" 67)
            local current_pointer=" "; local current_checkbox=" "
            if (( j == 0 )); then current_pointer="$pointer"; current_checkbox="$checkbox"; fi

            if [[ "$is_current" == "true" ]]; then
                formatted_line="${formatted_line//${T_REVERSE}/}"
                formatted_line="${formatted_line//${T_FG_RESET}/${C_L_BLUE}}"
                # formatted_line="${C_L_BLUE}${formatted_line}${T_FG_RESET}"
                formatted_line="${formatted_line//${T_RESET}/${T_RESET}${C_L_BLUE}${T_REVERSE}}"
                output+="${current_pointer}${current_checkbox}${T_REVERSE}${C_L_BLUE}${line_prefix}${formatted_line}${T_CLEAR_LINE}${T_RESET}"$'\n'
            else
                output+="${current_pointer}${current_checkbox}${line_prefix}${formatted_line}${T_CLEAR_LINE}${T_RESET}"$'\n'
            fi
        done
    fi
    printf '%b' "$output"
}

# Generic interactive menu function.
interactive_menu() {
    local mode="$1"; local prompt="$2"; local header="$3"; shift 3; local -a options=("$@")

    if ! [[ -t 0 ]]; then printErrMsg "Not an interactive session." >&2; return 1; fi
    local num_options=${#options[@]}; if [[ $num_options -eq 0 ]]; then printErrMsg "No options provided to menu." >&2; return 1; fi

    local current_option=0; local -a selected_options=()
    if [[ "$mode" == "multi" ]]; then for ((i=0; i<num_options; i++)); do selected_options[i]=0; done; fi

    local header_lines=0
    if [[ -n "$header" ]]; then header_lines=$(echo -e "$header" | wc -l); fi

    local menu_content_lines=0
    if (( num_options > 0 )); then
        menu_content_lines=$(printf "%s\n" "${options[@]}" | wc -l)
    fi

    _draw_menu_options() {
        for i in "${!options[@]}"; do
            local is_current="false"; if (( i == current_option )); then is_current="true"; fi
            local is_selected="false"; if [[ "$mode" == "multi" && ${selected_options[i]} -eq 1 ]]; then is_selected="true"; fi
            local is_multi="false"; if [[ "$mode" == "multi" ]]; then is_multi="true"; fi
            _draw_menu_item "$is_current" "$is_selected" "$is_multi" "${options[i]}"
        done
    }

    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty; trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty' EXIT
    printf '%s\n' "${T_QST_ICON} ${prompt}" >/dev/tty; printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty
    if [[ -n "$header" ]]; then printf '  %s%s\n' "${header}" "${T_RESET}" >/dev/tty; fi
    _draw_menu_options >/dev/tty
    printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty

    local movement_keys="↓/↑"; local select_action="${C_L_GREEN}SPACE/ENTER${C_WHITE} to confirm"
    if [[ "$mode" == "multi" ]]; then select_action="${C_L_CYAN}SPACE${C_WHITE} to select | ${C_L_GREEN}ENTER${C_WHITE} to confirm"; fi
    printf '  %s%s%s Move | %s | %s%s%s to cancel%s\n' "${C_L_CYAN}" "${movement_keys}" "${C_WHITE}" "${select_action}" "${C_L_YELLOW}" "Q/ESC" "${C_GRAY}" "${T_RESET}" >/dev/tty

    move_cursor_up 2

    local key; local lines_above=$((1 + header_lines)); local lines_below=2
    while true; do
        move_cursor_up "$menu_content_lines"; key=$(read_single_char </dev/tty)
        case "$key" in
            "$KEY_UP"|"k") current_option=$(( (current_option - 1 + num_options) % num_options ));;
            "$KEY_DOWN"|"j") current_option=$(( (current_option + 1) % num_options ));;
            "$KEY_ESC"|"q") clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"; return 1;;
            "$KEY_ENTER")
                clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"
                if [[ "$mode" == "multi" ]]; then
                    local has_selection=0
                    for i in "${!options[@]}"; do if [[ ${selected_options[i]} -eq 1 ]]; then has_selection=1; echo "$i"; fi; done
                    if [[ $has_selection -eq 1 ]]; then return 0; else return 1; fi
                else echo "$current_option"; return 0; fi
                ;;
            ' ')
                if [[ "$mode" == "multi" ]]; then
                    selected_options[current_option]=$(( 1 - selected_options[current_option] ))
                    if [[ "${options[0]}" == "All" ]]; then
                        if (( current_option == 0 )); then local all_state=${selected_options[0]}; for i in "${!options[@]}"; do selected_options[i]=$all_state; done
                        else local all_selected=1; for ((i=1; i<num_options; i++)); do if (( selected_options[i] == 0 )); then all_selected=0; break; fi; done; selected_options[0]=$all_selected; fi
                    fi
                else
                    clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"
                    echo "$current_option"; return 0
                fi
                ;;
        esac; _draw_menu_options >/dev/tty; done
}

interactive_multi_select_menu() {
    local prompt="$1"; local header="$2"; shift 2
    interactive_menu "multi" "$prompt" "$header" "$@"
}

_interactive_list_view() {
    local banner="$1" header_func="$2" refresh_func="$3" key_handler_func="$4" footer_func="$5"

    local current_option=0; local -a menu_options=(); local -a data_payloads=(); local num_options=0
    local list_lines=0; local footer_lines=0

    _refresh_data() {
        "$refresh_func" menu_options data_payloads; num_options=${#menu_options[@]}
        if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi
        if (( current_option < 0 )); then current_option=0; fi
        if (( num_options > 0 )); then list_lines=$(printf "%s\n" "${menu_options[@]}" | wc -l); else list_lines=1; fi
    }

    _draw_list() {
        if [[ $num_options -gt 0 ]]; then
            for i in "${!menu_options[@]}"; do
                local is_current="false"; if (( i == current_option )); then is_current="true"; fi
                # _interactive_list_view doesn't have a concept of "selected", so pass false.
                _draw_menu_item "$is_current" "false" "false" "${menu_options[i]}"
            done
        else
            printf "  %b" "${C_YELLOW}(No items found)${T_CLEAR_LINE}${T_RESET}\n"
        fi
    }

    _draw_full_view() {
        clear_screen; printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty; printBanner "$banner"; "$header_func"; printMsg "${C_GRAY}${DIV}${T_RESET}"; _draw_list
        printMsg "${C_GRAY}${DIV}${T_RESET}"
        local footer_content; footer_content=$("$footer_func")
        footer_lines=$(echo -e "$footer_content" | wc -l)
        printMsg "$footer_content"
    }

    _refresh_data
    _draw_full_view

    local lines_below_list=$(( footer_lines + 1 ))
    move_cursor_up "$lines_below_list"

    while true; do
        local key; key=$(read_single_char)
        local handler_result="noop"

        case "$key" in
            "$KEY_UP"|"k") if (( num_options > 0 )); then current_option=$(( (current_option - 1 + num_options) % num_options )); fi ;;
            "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option=$(( (current_option + 1) % num_options )); fi ;;
            *)
                local selected_payload=""
                if (( num_options > 0 )); then selected_payload="${data_payloads[$current_option]}"; fi
                "$key_handler_func" "$key" "$selected_payload" "$current_option" current_option "$num_options" handler_result
                ;;
        esac

        if [[ "$handler_result" == "exit" ]]; then break
        elif [[ "$handler_result" == "refresh" ]]; then
            _refresh_data; _draw_full_view
            lines_below_list=$(( footer_lines + 1 )); move_cursor_up "$lines_below_list"
        elif [[ "$handler_result" == "partial_redraw" ]]; then : # The handler already did the drawing and cursor positioning.
        else move_cursor_up "$list_lines"; _draw_list; fi
    done
}
#endregion Interactive Menus

# --- Playground Examples ---

run_single_select_example() {
    clear_screen
    printBanner "Single-Select Menu Example"
    local -a options=(
        "Option A"
        "Option B"$'\n'"Something ${C_GREEN}else${T_RESET} goes here"
        "Option C (with a long ${C_YELLOW}description${T_RESET} that might need wrapping or truncation)"
        "Option D"$'\n'"This is line 2"$'\n'"This is line 3"
    )
    local selected_index
    selected_index=$(interactive_menu "single" "Choose one option:" "HEADER: Options" "${options[@]}")

    if [[ $? -eq 0 ]]; then
        printOkMsg "You selected index ${selected_index}, which is: '${options[$selected_index]}'"
    else
        printInfoMsg "Single-select menu was cancelled."
    fi
    prompt_to_continue
}

run_multi_select_example() {
    clear_screen
    printBanner "Multi-Select Menu Example"
    local -a options=("All" "Apple" "Banana"$'\n'"A tasty yellow fruit" "Cherry" "Date some ${C_RED}really long (with color!)${T_RESET} text that should be ${C_YELLOW}truncated because${T_RESET} it is super long")
    local selected_indices_output
    selected_indices_output=$(interactive_multi_select_menu "Choose your favorite fruits:" "" "${options[@]}")

    if [[ $? -eq 0 ]]; then
        local -a selected_indices
        mapfile -t selected_indices < <(echo "$selected_indices_output")
        printOkMsg "You selected ${#selected_indices[@]} item(s):"
        for index in "${selected_indices[@]}"; do
            printMsg "  - Index ${index}: ${options[$index]}"
        done
    else
        printInfoMsg "Multi-select menu was cancelled or no items were selected."
    fi
    prompt_to_continue
}

# --- List View Example ---

_list_view_example_header() {
    printf "   ${C_WHITE}%-15s %-20s %s${T_RESET}\n" "ID" "NAME" "STATUS"
}

_list_view_example_footer() {
    if [[ "${_LIST_VIEW_EXPANDED:-0}" -eq 1 ]]; then
        printMsg " ${T_BOLD}Actions:${T_RESET}  ${C_L_GREEN}ENTER${T_RESET} to 'process' item | ${C_L_BLUE}(R)efresh${T_RESET} view  │ ${C_BLUE}? fewer options${T_RESET}"
        printMsg " ${T_BOLD}Movement:${T_RESET} ${C_L_CYAN}↓/j${T_RESET} Down | ${C_L_CYAN}↑/k${T_RESET} Up                         │ ${C_L_YELLOW}Q/ESC${T_RESET} Back"
        printMsg " ${T_BOLD}Extra:${T_RESET}    This is an extra line that appears when expanded."
    else
        printMsg " ${T_BOLD}Actions:${T_RESET}  ${C_L_GREEN}ENTER${T_RESET} to 'process' item | ${C_L_BLUE}(R)efresh${T_RESET} view  │ ${C_BLUE}? more options${T_RESET}"
        printMsg " ${T_BOLD}Movement:${T_RESET} ${C_L_CYAN}↓/j${T_RESET} Down | ${C_L_CYAN}↑/k${T_RESET} Up                         │ ${C_L_YELLOW}Q/ESC${T_RESET} Back"
    fi
}

_list_view_example_refresh() {
    local -n out_menu_options="$1"
    local -n out_data_payloads="$2"
    out_menu_options=()
    out_data_payloads=()

    # Static data for the example
    local -a names=(
        "alpha-service"
        "beta-database"
        "gamma-worker"
        "delta-proxy"
        "epsilon-long-name-service-that-will-most-definitely-need-truncation-to-fit"
        "zeta-multiline-service"
    )
    local -a statuses=(
        "${C_L_GREEN}Running${T_RESET}" "${C_L_GREEN}Running${T_RESET}" "${C_YELLOW}Degraded${T_RESET}" "${C_L_RED}Failed${T_RESET}"
        "${C_L_GREEN}Running${T_RESET}" "${C_L_BLUE}Initializing${T_RESET}"
    )

    for i in "${!names[@]}"; do
        local id="id-$(printf "%03d" $((i+1)))"
        local name="${names[i]}"
        local status="${statuses[i]}"

        # The 'status' variable contains its own T_RESET, which will now be handled correctly by the new logic.
        if (( i == 2 )); then # Make the "Degraded" item multi-line for testing
            out_data_payloads+=("$id|$name|$status")
            out_menu_options+=("ID: $id"$'\n'" Name: ${C_L_CYAN}${name}${T_RESET}"$'\n'" Status: ${status}")
        elif (( i == 5 )); then # Make the "zeta" item multi-line with long lines
            out_data_payloads+=("$id|$name|$status")
            out_menu_options+=("ID: $id - This is a very long first line that will need to be truncated for sure."$'\n'" Name: ${C_L_CYAN}${name}${T_RESET} - This is another very long line that will also be truncated."$'\n'" Status: ${status} - And a final long line for good measure to test truncation.")
        else
            out_data_payloads+=("$id|$name|$status")
            out_menu_options+=("ID: $id | Name: ${C_L_CYAN}${name}${T_RESET} | Status: ${status}")
        fi
    done
}

_list_view_example_key_handler() {
    local key="$1"
    local selected_payload="$2"
    local -n out_result="$6"

    out_result="noop"

    case "$key" in
        '/'|'?')
            # Delegate to the shared footer toggle handler.
            _handle_footer_toggle "_list_view_example_footer" "_LIST_VIEW_EXPANDED"
            out_result="partial_redraw"
            ;;
        'r'|'R')
            # we are at the bottom of the list, go down one line
            printMsg ""
            clear_current_line
            show_timed_message "${T_INFO_ICON} Refreshing data..." 1.5
            out_result="refresh"
            ;;
        "$KEY_ENTER")
            if [[ -n "$selected_payload" ]]; then
                clear_screen
                printBanner "Processing Item"
                printInfoMsg "You chose to process the item with payload:"
                printMsg "  ${C_L_CYAN}${selected_payload}${T_RESET}"
                prompt_to_continue
                out_result="refresh" # Refresh the view after returning
            fi
            ;;
        "$KEY_ESC"|"q"|"Q")
            out_result="exit"
            ;;
    esac
}

run_list_view_example() {
    # This variable will be visible to the footer and key handler functions.
    local _LIST_VIEW_EXPANDED=0

    _interactive_list_view \
        "Interactive List View Example" \
        "_list_view_example_header" \
        "_list_view_example_refresh" \
        "_list_view_example_key_handler" \
        "_list_view_example_footer"
}

run_format_menu_lines_example() {
    clear_screen
    printBanner "format_menu_lines Example"

    local -a input_lines=(
        "This is a short line."
        "This is a much, much, much, much, much, much, much, much, much, much, much longer line that will definitely be truncated."
        "${C_L_GREEN}This line has color${T_RESET} and should be handled correctly."
        ""
        "Another short one."
    )

    printInfoMsg "Input array:"
    printf "  - %s\n" "${input_lines[@]}"
    printInfoMsg "\nOutput of format_menu_lines (wrapped in a box for clarity):"
    local formatted_output; formatted_output=$(format_menu_lines "${input_lines[@]}")
    printMsg "${C_GRAY}${DIV}${T_RESET}\n${formatted_output}\n${C_GRAY}${DIV}${T_RESET}"
    prompt_to_continue
}
# --- Main Application ---

main() {
    while true; do
        clear_screen
        printBanner "Interactive Menu Playground"

        # printMsg "${T_QST_ICON} Some ${C_RED}red${T_RESET} text with a qst goes here"

        local -a main_menu_options=(
            "Run ${C_RED}Single-Select${T_RESET} Menu Example"
            "Run ${C_GREEN}Multi-Select${T_RESET} Menu Example"
            "Run Interactive List View Example"
            "Run format_menu_lines Example"
            "Exit Playground"
        )

        local selected_index
        selected_index=$(interactive_menu "single" "Choose an example to run:" "" "${main_menu_options[@]}")

        if [[ $? -ne 0 ]]; then
            # User cancelled the main menu (e.g., pressed ESC)
            break
        fi

        case "$selected_index" in
            0) run_single_select_example ;;
            1) run_multi_select_example ;;
            2) run_list_view_example ;;
            3) run_format_menu_lines_example ;;
            4)
                local -a main_menu_options=(
                    "Run ${C_RED}Single-Select${T_RESET} Menu Example"
                    "Run ${C_GREEN}Multi-Select${T_RESET} Menu Example"
                    "Run Interactive List View Example"
                    "Run format_menu_lines Example"
                    "Exit Playground"
                )
                break ;;
        esac
    done

    clear_screen
    printOkMsg "Goodbye!"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi