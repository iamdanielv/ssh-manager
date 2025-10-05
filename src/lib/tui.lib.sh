#!/bin/bash
# A library of shared utilities for building Terminal User Interfaces (TUIs).

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
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }

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

# An interactive yes/no prompt that handles single-character input.
# It supports default answers and cancellation.
# Usage: prompt_yes_no "Your question?" [default_answer: y/n]
# Returns 0 for 'yes', 1 for 'no', and 2 for cancellation (ESC/q).
prompt_yes_no() {
    local question="$1"
    local default_answer="${2:-}"
    local has_error=false
    local answer
    local prompt_suffix

    if [[ "$default_answer" == "y" ]]; then prompt_suffix="(Y/n)"; elif [[ "$default_answer" == "n" ]]; then prompt_suffix="(y/N)"; else prompt_suffix="(y/n)"; fi
    local question_lines; question_lines=$(echo -e "$question" | wc -l)

    _clear_all_prompt_content() {
        clear_current_line >/dev/tty
        if (( question_lines > 1 )); then clear_lines_up $(( question_lines - 1 )); fi
        if $has_error; then clear_lines_up 1; fi
    }

    printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty

    while true; do
        answer=$(read_single_char </dev/tty)
        if [[ "$answer" == "$KEY_ENTER" ]]; then answer="$default_answer"; fi

        case "$answer" in
            [Yy]|[Nn])
                _clear_all_prompt_content
                if [[ "$answer" =~ [Yy] ]]; then return 0; else return 1; fi
                ;;
            "$KEY_ESC"|"q")
                _clear_all_prompt_content
                show_timed_message " ${C_L_YELLOW}-- cancelled --${T_RESET}" 1
                return 2 # Cancelled
                ;;
            *)
                _clear_all_prompt_content; printErrMsg "Invalid input. Please enter 'y' or 'n'." >/dev/tty; has_error=true
                printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty ;;
        esac
    done
}

# (Private) Clears the footer area of an interactive list view.
# The cursor is expected to be at the end of the list content (before the divider).
# It leaves the cursor at the start of the now-cleared footer area.
# Usage: _clear_list_view_footer <footer_line_count>
_clear_list_view_footer() {
    local footer_lines="$1"

    # The cursor is at the end of the list content.
    # Move down one line to be past the list's bottom divider.
    printf '\n' >/dev/tty

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
        local old_footer_content; old_footer_content=$("$footer_draw_func") # Capture old footer
        local old_footer_line_count; old_footer_line_count=$(echo -e "$old_footer_content" | wc -l)

        # Toggle the state
        is_expanded_ref=$(( 1 - is_expanded_ref ))

        # --- Perform the partial redraw without a full refresh ---
        # The cursor is at the end of the list, before the divider. Move down into the footer area.
        printf '\n'

        # Clear the old footer area (the footer text + the final bottom divider).
        clear_lines_down $(( old_footer_line_count + 1 ))

        # Now, print the new footer.
        local new_footer_content; new_footer_content=$("$footer_draw_func") # Capture new footer
        printMsg "$new_footer_content"

        # Move the cursor back to where the main loop expects it (end of list).
        local new_footer_lines; new_footer_lines=$(echo -e "$new_footer_content" | wc -l) # The +1 is for the divider we removed
        move_cursor_up $(( new_footer_lines + 1 ))
    } >/dev/tty
}

# An interactive prompt for user input that supports cancellation.
# It provides a rich line-editing experience including cursor movement
# (left/right/home/end), insertion, and deletion (backspace/delete). This version
# handles long input by scrolling the text horizontally within a single line.
# Usage: prompt_for_input "Prompt text" "variable_name" ["default_value"] ["allow_empty"]
# Returns 0 on success (Enter), 1 on cancellation (ESC).
prompt_for_input() {
    local prompt_text="$1"
    local -n var_ref="$2" # Use nameref to assign to caller's variable
    local default_val="${3:-}"
    local allow_empty="${4:-false}"
 
    local input_str="$default_val" cursor_pos=${#input_str} view_start=0 key
 
    # --- One-time setup ---
    # Calculate the length of the icon prefix to use for indenting subsequent lines.
    local icon_prefix_len; icon_prefix_len=$(strip_ansi_codes "${T_QST_ICON} " | wc -c)
    local padding; printf -v padding '%*s' "$icon_prefix_len" ""
    # Prepend padding to each line of the prompt text after the first one.
    local indented_prompt_text; indented_prompt_text=$(echo -e "$prompt_text" | sed "2,\$s/^/${padding}/")

    # Print the prompt text. Using `printf %b` handles newlines without adding an extra one at the end.
    printf '%b' "${T_QST_ICON} ${indented_prompt_text}" >/dev/tty
    # The actual input line starts with a simple prefix, printed right after the prompt text.
    local input_prefix=": "
    printMsgNoNewline "$input_prefix" >/dev/tty
 
    # Calculate how many lines the prompt text occupies for later cleanup.
    local prompt_lines; prompt_lines=$(echo -e "${indented_prompt_text}" | wc -l)
    # The length of the last line of the prompt determines where the input starts.
    local input_line_prefix_len
    if (( prompt_lines > 1 )); then
        local last_line_prompt; last_line_prompt=$(echo -e "${indented_prompt_text}" | tail -n 1)
        input_line_prefix_len=$(strip_ansi_codes " ${last_line_prompt}${input_prefix}" | wc -c)
    else
        input_line_prefix_len=$(strip_ansi_codes "${T_QST_ICON} ${prompt_text}${input_prefix}" | wc -c)
    fi
 
    # (Private) Helper to redraw the input line.
    _prompt_for_input_redraw() {
        # Go to beginning of line, then move right past the static prompt.
        printf '\r\033[%sC' "$input_line_prefix_len" >/dev/tty
 
        local term_width; term_width=$(tput cols)
        local available_width=$(( term_width - input_line_prefix_len ))
        if (( available_width < 1 )); then available_width=1; fi
 
        # --- Scrolling logic ---
        if (( cursor_pos < view_start )); then view_start=$cursor_pos; fi
        if (( cursor_pos >= view_start + available_width )); then view_start=$(( cursor_pos - available_width + 1 )); fi
 
        local display_str="${input_str:$view_start:$available_width}" local total_len=${#input_str}
 
        # --- Ellipsis logic for overflow ---
        local ellipsis="…"
        if (( total_len > available_width )); then
            if (( view_start > 0 )); then
                # We've scrolled right, show ellipsis on the left.
                display_str="${ellipsis}${display_str:1}"
            fi
            if (( view_start + available_width < total_len )); then
                # There's more text to the right, show ellipsis on the right.
                display_str="${display_str:0:${#display_str}-1}${ellipsis}"
            fi
        fi
 
        # Print the dynamic part: colored input, reset color, and clear rest of line.
        # This overwrites the previous input and clears any leftover characters.
        printMsgNoNewline "${C_L_CYAN}${display_str}${T_RESET}${T_CLEAR_LINE}" >/dev/tty
 
        # --- Cursor positioning ---
        local display_cursor_pos=$(( cursor_pos - view_start )); if (( view_start > 0 )); then ((display_cursor_pos++)); fi
        local chars_after_cursor=$(( ${#display_str} - display_cursor_pos ))
        if (( chars_after_cursor > 0 )); then
            printf '\033[%sD' "$chars_after_cursor" >/dev/tty
        fi
    }
 
    while true; do
        _prompt_for_input_redraw
 
        key=$(read_single_char </dev/tty)
 
        case "$key" in
            "$KEY_ENTER")
                if [[ -n "$input_str" || "$allow_empty" == "true" ]]; then
                    var_ref="$input_str"
                    # On success, clear the input line and the prompt text above it.
                    # We clear `prompt_lines` in total. The current line is one of them.
                    clear_current_line >/dev/tty; clear_lines_up $(( prompt_lines - 1 )) >/dev/tty

                    # --- Print a clean, single-line, truncated summary ---
                    local total_width=70
                    local icon_len; icon_len=$(strip_ansi_codes "${T_QST_ICON} " | wc -c)
                    local separator_len=2 # for ": "
                    local available_width=$(( total_width - icon_len - separator_len ))
                    local prompt_width=$(( available_width / 2 )); local value_width=$(( available_width - prompt_width ))
                    local single_line_prompt; single_line_prompt=$(echo -e "$prompt_text" | tr '\n' ' ')
                    local truncated_prompt; truncated_prompt=$(_truncate_string "$single_line_prompt" "$prompt_width")
                    local truncated_value; truncated_value=$(_truncate_string "${C_L_GREEN}${var_ref}${T_RESET}" "$value_width")
                    printMsg "${T_QST_ICON} ${truncated_prompt}: ${truncated_value}" >/dev/tty

                    return 0
                fi
                ;;
            "$KEY_ESC")
                # On cancel, clear the input area and show a timed message.
                # We clear `prompt_lines` in total. The current line is one of them.
                clear_current_line >/dev/tty; clear_lines_up $(( prompt_lines - 1 )) >/dev/tty
                show_timed_message "${T_INFO_ICON} Input cancelled." 1
                return 1
                ;;
            "$KEY_BACKSPACE")
                if (( cursor_pos > 0 )); then
                    input_str="${input_str:0:cursor_pos-1}${input_str:cursor_pos}"
                    ((cursor_pos--))
                fi
                ;;
            "$KEY_DELETE")
                if (( cursor_pos < ${#input_str} )); then
                    input_str="${input_str:0:cursor_pos}${input_str:cursor_pos+1}"
                fi
                ;;
            "$KEY_LEFT") if (( cursor_pos > 0 )); then ((cursor_pos--)); fi ;;
            "$KEY_RIGHT") if (( cursor_pos < ${#input_str} )); then ((cursor_pos++)); fi ;;
            "$KEY_HOME") cursor_pos=0 ;;
            "$KEY_END") cursor_pos=${#input_str} ;;
            *)
                if (( ${#key} == 1 )) && [[ "$key" =~ [[:print:]] ]]; then
                    input_str="${input_str:0:cursor_pos}${key}${input_str:cursor_pos}"
                    ((cursor_pos++))
                fi
                ;;
        esac
    done
}
#endregion User Input

#region Editor Loop
# (Private) A generic, reusable interactive loop for entity editors (hosts, port forwards).
# This function encapsulates the shared UI loop for adding, editing, and cloning.
#
# It relies on context-specific functions being defined in the caller's scope, which
# have access to the necessary state variables (e.g., new_alias, original_alias).
#
# Usage: _interactive_editor_loop <mode> <banner> <draw_func> <field_handler_func> <change_checker_func> <reset_func>
# Returns 0 if the user chooses to save, 1 if they cancel/quit.
_interactive_editor_loop() {
    local mode="$1" banner_text="$2" draw_func="$3" field_handler_func="$4" change_checker_func="$5" reset_func="$6"

    while true; do
        clear_screen; printBanner "$banner_text"; "$draw_func"
        local key; key=$(read_single_char)
        case "$key" in
            'c'|'C'|'d'|'D')
                clear_current_line
                local question="Discard all pending changes?"; if [[ "$mode" == "add" || "$mode" == "clone" ]]; then question="Discard all changes and reset fields?"; fi
                if prompt_yes_no "$question" "y"; then "$reset_func"; show_timed_message "${T_INFO_ICON} Changes discarded."; fi ;;
            's'|'S') return 0 ;; # Signal to Save
            'q'|'Q'|"$KEY_ESC")
                if "$change_checker_func"; then
                    if ! prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then
                        show_timed_message "${T_INFO_ICON} Operation cancelled."; return 1
                    fi
                else
                    clear_current_line
                    show_timed_message "${T_INFO_ICON} Edit Host cancelled. No changes were made."
                    return 1
                fi ;;
            *)
                # Delegate to the context-specific field handler.
                # It returns 0 on success (key was handled), 1 on failure (key was not for it).
                if ! "$field_handler_func" "$key"; then :; fi ;; # Key was not handled, loop to redraw.
        esac
    done
}
#endregion

#region Error Handling & Traps
script_exit_handler() { printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; }
trap 'script_exit_handler' EXIT
script_interrupt_handler() {
    trap - INT; clear_screen; printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"; exit 130
}
trap 'script_interrupt_handler' INT
#endregion Error Handling & Traps

#region Interactive Menus

# (Private) Applies a reverse-video highlight to a string, correctly handling
# any existing ANSI color codes within it.
# Usage: highlighted_string=$(_apply_highlight "my ${C_RED}colored${T_RESET} string")
_apply_highlight() {
    local content="$1"
    # To correctly handle items that have their own color resets (${T_RESET})
    # or foreground resets (${T_FG_RESET}), we perform targeted substitutions.
    # This ensures the background remains highlighted across the entire line.
    local highlight_restore="${T_RESET}${T_REVERSE}${C_L_BLUE}"
    local highlighted_content="${content//${T_RESET}/${highlight_restore}}"
    # Also handle foreground-only resets.
    highlighted_content="${highlighted_content//${T_FG_RESET}/${C_L_BLUE}}"

    printf "%s%s%s%s" \
        "${T_REVERSE}${C_L_BLUE}" \
        "$highlighted_content" \
        "${T_CLEAR_LINE}" \
        "${T_RESET}"
}

# (Private) Gets the appropriate prefix for a menu item.
# Handles pointers and multi-select checkboxes.
# Usage: prefix=$(_get_menu_item_prefix <is_current> <is_selected> <is_multi_select>)
_get_menu_item_prefix() {
    local is_current="$1" is_selected="$2" is_multi_select="$3"

    local pointer=" "
    if [[ "$is_current" == "true" ]]; then
        pointer="${T_BOLD}${C_L_MAGENTA}❯${T_FG_RESET}"
    fi

    local checkbox=" " # One space for alignment in single-select mode
    if [[ "$is_multi_select" == "true" ]]; then
        checkbox="_" # Default unchecked state
        if [[ "$is_selected" == "true" ]]; then
            checkbox="${T_BOLD}${C_GREEN}✓${T_FG_RESET}"
        fi
    fi

    echo "${pointer}${checkbox}"
}

# (Private) Draws a single item for an interactive menu or list.
# This function encapsulates the complex logic for single-line, multi-line,
# and highlighted rendering, promoting DRY principles.
#
# Usage: _draw_menu_item <is_current> <is_selected> <is_multi_select> <option_text>
_draw_menu_item() {
    local is_current="$1" is_selected="$2" is_multi_select="$3" option_text="$4"

    local prefix; prefix=$(_get_menu_item_prefix "$is_current" "$is_selected" "$is_multi_select")

    # --- 2. Format and Draw Lines ---
    local -a lines=()
    mapfile -t lines <<< "$option_text"
    local num_lines=${#lines[@]}

    for j in "${!lines[@]}"; do
        local line_prefix="│"
        if (( num_lines == 1 )); then line_prefix="╶";
        elif (( j == 0 )); then line_prefix="┌";
        elif (( j == num_lines - 1 )); then line_prefix="└";
        fi

        local formatted_line; formatted_line=$(_format_fixed_width_string "${lines[j]}" 67)

        # Use a different prefix for subsequent lines of a multi-line item
        local current_prefix="  " # Two spaces for alignment
        if (( j == 0 )); then current_prefix="$prefix"; fi

        if [[ "$is_current" == "true" ]]; then
            local highlighted_line; highlighted_line=$(_apply_highlight "${line_prefix}${formatted_line}")
            printf "%s%s\n" \
                "$current_prefix" \
                "$highlighted_line"
        else
            # For non-current items, print as is.
            printf "%s%s%s%s%s\n" \
                "$current_prefix" \
                "$line_prefix" \
                "$formatted_line" \
                "${T_CLEAR_LINE}" \
                "${T_RESET}"
        fi
    done
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

    local movement_keys="↓/↑/j/k"; local select_action="${C_L_GREEN}SPACE/ENTER${C_WHITE} to confirm"
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
                local is_current="false"
                if (( i == current_option )); then is_current="true"; fi
                # A list view is like a single-select menu, so is_selected and is_multi_select are false.
                _draw_menu_item "$is_current" "false" "false" "${menu_options[i]}"
            done
        else
            printf "  %s\n" "${C_GRAY}(No items found.)${T_CLEAR_LINE}${T_RESET}"
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
# (Private) A wrapper for running a menu action.
# It clears the screen, runs the function, and then prompts to continue.
run_menu_action() {
    local action_func="$1"; shift; clear_screen; printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    "$action_func" "$@"; local exit_code=$?
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    # If the exit code is 2, it's a signal that the action handled its own
    # "cancellation" feedback and we should skip the prompt.
    if [[ $exit_code -ne 2 ]]; then prompt_to_continue; fi
}

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
