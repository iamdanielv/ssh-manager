#!/bin/bash
# An interactive TUI for managing and connecting to SSH hosts.

# Source the TUI utility library.
# The script will fail if it is not in the lib/ directory.
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/tui.lib.sh"; then
    echo "Error: Could not source lib/tui.lib.sh. Make sure it is in the lib/ directory." >&2
    exit 1
fi

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
    local -a options=("All" "Apple" "Banana"$'\n'"A tasty yellow fruit" "Cherry" "Date some ${C_RED}really long (with color!)${T_FG_RESET} text that should be ${C_YELLOW}truncated because${T_FG_RESET} it is super long")
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

    # Source data for the example
    local -a names=(
        "alpha-service"
        "beta-database"
        "gamma-worker"
        "delta-proxy"
        "epsilon-long-name-service-that-will-most-definitely-need-truncation-to-fit"
        "zeta-multiline-service-A"
        "eta-multiline-service-B"
    )
    local -a statuses=(
        "${C_L_GREEN}Running${T_RESET}" "${C_L_GREEN}Running${T_RESET}" "${C_YELLOW}Degraded${T_RESET}" "${C_L_RED}Failed${T_RESET}"
        "${C_L_GREEN}Running${T_RESET}" "${C_L_BLUE}Initializing${T_RESET}" "${C_GRAY}Stopped${T_RESET}"
    )

    # On each refresh, show a random number of items (between 2 and the max)
    # to demonstrate how the redraw handles lists of different heights.
    local num_items=${#names[@]}
    local num_to_show=$(( RANDOM % (num_items - 1) + 2 )) # Random number between 2 and num_items

    # Get a shuffled list of indices to pick random items from the source arrays.
    local -a shuffled_indices
    mapfile -t shuffled_indices < <(shuf -i 0-$((num_items - 1)) -n "$num_to_show")

    for i in "${shuffled_indices[@]}"; do
        local id="id-$(printf "%03d" $((i+1)))"
        local name="${names[i]}"
        local status="${statuses[i]}"

        out_data_payloads+=("$id|$name|$status")

        # Make some items multi-line for testing purposes
        if (( i == 2 )); then # Make the "Degraded" item multi-line for testing
            out_menu_options+=("ID: $id"$'\n'" Name: ${C_L_CYAN}${name}${T_RESET}"$'\n'" Status: ${status}")
        elif (( i == 6 )); then # Make an item multi-line with long lines
            out_menu_options+=("ID: $id - This is a very long first line that will need to be truncated for sure."$'\n'" Name: ${C_L_CYAN}${name}${T_RESET} - This is another very long line that will also be truncated."$'\n'" Status: ${status} - And a final long line for good measure to test truncation.")
        else
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
            # Perform a partial refresh.
            {
                # The cursor is at the end of the list, before the bottom divider.
                local old_list_lines=$list_lines
                local footer_content; footer_content=$(_list_view_example_footer)
                local footer_line_count; footer_line_count=$(echo -e "$footer_content" | wc -l)

                _clear_list_view_footer "$footer_line_count" >/dev/tty

                # Randomly show a single or multi-line message to test redraw robustness.
                local single_line_msg="${T_INFO_ICON} Refreshing data..."
                local multi_line_msg="${T_INFO_ICON} Refreshing data...\n${C_GRAY}This may take a moment.${T_RESET}\n${C_L_BLUE}Please wait...${T_RESET}"
                clear_lines_up 1 # Clear the previous input line
                if (( RANDOM % 2 == 0 )); then
                    show_timed_message "$single_line_msg" 1
                else
                    show_timed_message "$multi_line_msg" 1.5
                fi

                # From the start of the footer area, move up and clear the old list and its bottom divider.
                # This leaves the cursor at the start of the now-cleared list area.
                clear_lines_up $(( old_list_lines + 1 )) # +1 for the divider line

                # Refresh data and redraw the list and footer in the now-cleared space.
                _refresh_data
                _draw_list
                printMsg "${C_GRAY}${DIV}${T_RESET}"
                printMsg "$footer_content"

                # Reposition the cursor where the main loop expects it.
                move_cursor_up $(( footer_line_count + 1 ))
            } >/dev/tty
            out_result="partial_redraw" # Signal that we've handled the drawing.
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