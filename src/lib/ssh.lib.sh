#!/bin/bash
# A library of shared utilities for managing SSH configuration files.

# Parses the SSH config file to extract host aliases.
# Ignores wildcard hosts like '*'.
get_ssh_hosts() {
    if [[ ! -f "$SSH_CONFIG_PATH" ]]; then
        return
    fi
    # Use awk to find lines starting with "Host", print the second field,
    # and ignore any hosts that are just "*".
    awk '/^[Hh]ost / && $2 != "*" {print $2}' "$SSH_CONFIG_PATH"
}

# Gets a specific config value for a given host by using `ssh -G`.
# This is the most robust method as it uses ssh itself to evaluate the config.
# It correctly handles the "first value wins" rule for duplicate keys, as well
# as Match blocks and include directives.
# Usage: get_ssh_config_value <host_alias> <config_key>
get_ssh_config_value() {
    local host_alias="$1"
    local key="$2"
    local key_lower
    key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')

    # `ssh -G` prints the fully resolved configuration for a host.
    ssh -G "$host_alias" 2>/dev/null | awk -v key="$key_lower" '
        $1 == key {
            # The value is the rest of the line. This handles values with spaces.
            val = ""
            for (i = 2; i <= NF; i++) {
                val = (val ? val " " : "") $i
            }
            print val
            exit
        }
    '
}

# (Private) Gets a config value ONLY if it's explicitly set in the host block.
# This avoids picking up default values that `ssh -G` provides.
# Returns an empty string if the key is not explicitly set in the block.
# Usage: _get_explicit_ssh_config_value <host_alias> <config_key>
_get_explicit_ssh_config_value() {
    local host_alias="$1"
    local key_lower
    key_lower=$(echo "$2" | tr '[:upper:]' '[:lower:]')

    local host_block
    host_block=$(_get_host_block_from_config "$host_alias" "$SSH_CONFIG_PATH")

    if [[ -n "$host_block" ]]; then
        # Parse the block for the specific key, ignoring case for the key itself.
        echo "$host_block" | awk -v key="$key_lower" '
            tolower($1) == key {
                val = ""; for (i = 2; i <= NF; i++) { val = (val ? val " " : "") $i }; print val; exit
            }
        '
    fi
}

# (Private) Gets all relevant config values for a given host in one go.
# Returns a string of `eval`-safe variable assignments.
# Usage:
#   local details; details=$(_get_all_ssh_config_values_as_string <host_alias>)
#   eval "$details"
_get_all_ssh_config_values_as_string() {
    local host_alias="$1"
    # Call ssh -G once per host and parse all required values in a single awk command.
    # This is much more efficient than calling ssh -G multiple times.
    ssh -G "$host_alias" 2>/dev/null | awk '
        # Map ssh -G output keys to the shell variable names we want to use.
        BEGIN {
            keys["hostname"] = "current_hostname"
            keys["user"] = "current_user"
            # identityfile is now handled separately to avoid ssh -G defaults
            keys["port"] = "current_port"
        }
        # If the first field is one of our target keys, process it.
        $1 in keys {
            var_name = keys[$1]
            # Reconstruct the value, which might contain spaces.
            val = ""
            for (i = 2; i <= NF; i++) { val = (val ? val " " : "") $i }
            # Print in KEY="VALUE" format for safe evaluation in the shell.
            printf "%s=\"%s\"\n", var_name, val
        }
    '
}

# (Private) Generic function to process an SSH config file, filtering host blocks.
# It can either keep only the matching block or remove it and keep everything else.
# Usage: _process_ssh_config_blocks <target_host> <config_file> <mode>
#   mode: 'keep' - prints only the block matching the target_host.
#   mode: 'remove' - prints the entire file except for the matching block.
_process_ssh_config_blocks() {
    local target_host="$1"
    local config_file="$2"
    local mode="$3" # 'keep' or 'remove'

    if [[ "$mode" != "keep" && "$mode" != "remove" ]]; then
        printErrMsg "Invalid mode '${mode}' for _process_ssh_config_blocks" >&2
        return 1
    fi

    awk -v target_host="$target_host" -v mode="$mode" '
        # Flushes the buffered block based on whether it matches the target and the desired mode.
        # It manages a single newline separator between printed blocks.
        function flush_block() {
            if (block != "") {
                if ((mode == "keep" && is_target_block) || (mode == "remove" && !is_target_block)) {
                    # If we have printed a block before, add a newline separator.
                    if (output_started) {
                        printf "\n"
                    }
                    printf "%s", block
                    output_started = 1
                }
            }
        }

        # Match a new Host block definition.
        /^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/ {
            flush_block() # Flush the previous block.

            # Reset state for the new block.
            block = $0
            is_target_block = 0

            # Check if this new block is the one we are looking for by iterating
            # through the fields on the line, starting from the second field.
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^#/) break # Stop at the first comment
                if ($i == target_host) {
                    is_target_block = 1
                    break
                }
            }
            next
        }

        # For any other line (part of a block, a comment, or a blank line):
        {
            if (block != "") {
                block = block "\n" $0
            } else {
                # This is content before the first Host definition.
                # It is never a target block, so print it only in "remove" mode.
                if (mode == "remove") {
                    printf "%s\n", $0
                    output_started = 1
                }
            }
        }

        # At the end of the file, flush the last remaining block.
        END {
            flush_block()
        }
    ' "$config_file"
}

# (Private) Reads an SSH config file and returns the block for a specific host.
# Usage:
#   local block
#   block=$(_get_host_block_from_config "my-host" "/path/to/config")
_get_host_block_from_config() {
    local host_to_find="$1"
    local config_file="$2"
    _process_ssh_config_blocks "$host_to_find" "$config_file" "keep"
}

# (Private) Reads the SSH config and returns a new version with a specified host block removed.
# Usage:
#   local new_config
#   new_config=$(_remove_host_block_from_config "my-host")
#   echo "$new_config" > "$SSH_CONFIG_PATH"
_remove_host_block_from_config() {
    local host_to_remove="$1"
    _process_ssh_config_blocks "$host_to_remove" "$SSH_CONFIG_PATH" "remove"
}

# (Private) Gets the tags for a given host from its config block.
# Tags are expected to be on a line like: # Tags: tag1,tag2,tag3
# Usage: _get_tags_for_host <host_alias>
_get_tags_for_host() {
    local host_alias="$1"
    local host_block
    host_block=$(_process_ssh_config_blocks "$host_alias" "$SSH_CONFIG_PATH" "keep")

    if [[ -n "$host_block" ]]; then
        # Grep for the tags line, cut out the prefix, and trim whitespace.
        # This pipeline handles multiple "# Tags:" lines by joining them with commas.
        echo "$host_block" | grep -o -E '^\s*#\s*Tags:\s*.*' \
            | sed -E 's/^\s*#\s*Tags:\s*//' \
            | sed 's/^\s*//;s/\s*$//' \
            | paste -sd, -
    fi
}

# (Private) A shared function to refresh the data for host list views.
_common_host_view_refresh() {
    local -n out_menu_options="$1"
    local -n out_data_payloads="$2"
    # This function now populates both arrays based on the filter.
    get_detailed_ssh_hosts_menu_options out_menu_options out_data_payloads "false" "${_HOST_VIEW_CURRENT_FILTER:-}"
}

# (Private) A shared function to draw a standardized header for host list views.
_common_host_view_draw_header() {
    local header; header=$(printf "${C_L_BLUE}┗${T_RESET}  %-20s ${C_WHITE}%s${T_RESET}" "HOST ALIAS" "user@hostname[:port]")
    printMsg "${C_WHITE}${header}${T_RESET}"
}

# (Private) A special-case helper to launch the default editor for the main config file.
# This is called directly from a key handler, bypassing run_menu_action to avoid
# the intermediate "Press any key" prompt. It takes over the screen and relies
# on the calling view to perform a full refresh upon return.
_launch_editor_for_config() {
    local editor="${EDITOR:-nvim}"
    if ! command -v "${editor}" &>/dev/null; then
        printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."
        prompt_to_continue
    else
        # The calling function is responsible for managing the cursor and screen state
        # before and after calling this function.
        "${editor}" "${SSH_CONFIG_PATH}"
    fi
}

# (Private) Ensures the SSH directory and config file exist with correct permissions.
# This is a common setup step for both main scripts.
_ensure_ssh_dir_and_config() {
    # These variables are defined in the main scripts that source this library.
    # If they aren't set, use the standard defaults.
    local ssh_dir="${SSH_DIR:-${HOME}/.ssh}"
    local ssh_config="${SSH_CONFIG_PATH:-${ssh_dir}/config}"
    mkdir -p "$ssh_dir"; chmod 700 "$ssh_dir"; touch "$ssh_config"; chmod 600 "$ssh_config"
}

# Generates a list of formatted strings for the interactive menu,
# showing details for each SSH host.
# Populates an array whose name is passed as the first argument.
# Usage:
#   local -a my_menu_options
#   get_detailed_ssh_hosts_menu_options my_menu_options
get_detailed_ssh_hosts_menu_options() {
    local -n out_array="$1" # Nameref for the output menu options
    local -n out_data_payloads_ref="$2" # Nameref for the raw host aliases
    local single_line="${3:-false}"
    local filter_tag="${4:-}"
    local -a hosts
    mapfile -t hosts < <(get_ssh_hosts)

    out_array=() # Clear the output array
    out_data_payloads_ref=() # Clear the data payload array

    if [[ ${#hosts[@]} -eq 0 ]]; then
        # If there are no hosts at all, ensure output arrays are empty and return.
        out_array=()
        out_data_payloads_ref=()
        return 0
    fi

    # If filtering, pre-filter the hosts array
    if [[ -n "$filter_tag" ]]; then
        local -a filtered_hosts=()
        for host_alias in "${hosts[@]}"; do
            local host_tags; host_tags=$(_get_tags_for_host "$host_alias")
            # For case-insensitive matching, convert the filter, tags, and alias to lowercase.
            # This allows for partial matching against either the host's tags or its alias.
            local lower_host_tags="${host_tags,,}"
            local lower_filter_tag="${filter_tag,,}"
            local lower_host_alias="${host_alias,,}"

            if [[ "$lower_host_tags" == *"$lower_filter_tag"* || "$lower_host_alias" == *"$lower_filter_tag"* ]]; then
                filtered_hosts+=("$host_alias")
            fi
        done
        hosts=("${filtered_hosts[@]}")

        if [[ ${#hosts[@]} -eq 0 ]]; then
            # If filtering resulted in no hosts, provide a specific message.
            out_array+=("  ${C_L_YELLOW}(No items found that match filter: ${filter_tag})${T_RESET}")
            return 0
        fi
    fi

    for host_alias in "${hosts[@]}"; do
        local display_alias; display_alias=$(_format_fixed_width_string "$host_alias" 20)
        # Declare local variables and use eval to populate them from the awk output.
        # This is safe because the input is controlled (from ssh -G) and the awk script
        # only processes specific, known keys.
        local current_hostname current_user current_identityfile current_port
        local details; details=$(_get_all_ssh_config_values_as_string "$host_alias")
        eval "$details" # Sets the variables

        # Now, explicitly get the identity file to avoid using ssh -G defaults.
        # Also get tags.
        current_identityfile=$(_get_explicit_ssh_config_value "$host_alias" "IdentityFile")

        # Format port info, only show if not the default port 22
        local port_info=""
        if [[ -n "$current_port" && "$current_port" != "22" ]]; then
            port_info=":${C_L_YELLOW}${current_port}${C_L_CYAN}"
        fi

        local raw_line1_details="${C_L_CYAN}${current_user:-?}@${current_hostname:-?}${port_info}${T_RESET}"

        if [[ "$single_line" == "true" ]]; then
            local line1_details; line1_details=$(_format_fixed_width_string "$raw_line1_details" 46)
            out_array+=("$(printf "%s %s" "$display_alias" "$line1_details")${T_RESET}")
        else
            local line1; line1=$(printf "%s %s" "$display_alias" "$(_format_fixed_width_string "$raw_line1_details" 46)")
            local key_info=""; if [[ -n "$current_identityfile" ]]; then key_info="${C_WHITE}(${current_identityfile/#$HOME/\~})"; fi
            local host_tags; host_tags=$(_get_tags_for_host "$host_alias"); local tags_info=""; if [[ -n "$host_tags" ]]; then tags_info="${C_GRAY}[${host_tags//,/, }]${T_RESET}"; fi
            local line2_details; line2_details=$(echo "${tags_info} ${key_info}" | sed 's/^\s*//;s/\s*$//'); line2_details=$(_format_fixed_width_string "$line2_details" 67)
            local formatted_string="$line1"; if [[ -n "$line2_details" ]]; then formatted_string+=$'\n'"${line2_details}"; fi
            out_array+=("${formatted_string}${T_RESET}")
        fi
        out_data_payloads_ref+=("$host_alias")
    done
}

# Presents an interactive menu for the user to select an SSH host.
# Returns the selected host alias via stdout. Returns exit code 1 if no host is selected.
select_ssh_host() {
    local prompt="$1"; local single_line="${2:-false}"
    local -a menu_options data_payloads
    get_detailed_ssh_hosts_menu_options menu_options data_payloads "$single_line" "" # No filter
    if [[ ${#menu_options[@]} -eq 0 ]]; then printInfoMsg "No hosts found in your SSH config file."; return 1; fi
    local selected_index
    local header; header=$(printf "%-20s ${C_WHITE}%s${T_RESET}" "HOST ALIAS" "user@hostname[:port]")
    selected_index=$(interactive_menu "single" "$prompt" "$header" "${menu_options[@]}")
    if [[ $? -ne 0 ]]; then printInfoMsg "Operation cancelled."; return 1; fi
    echo "${data_payloads[$selected_index]}"; return 0
}