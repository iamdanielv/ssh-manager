# SSH Manager 🔑

An interactive TUI for managing and connecting to SSH hosts defined in `~/.ssh/config`.

## Features

- Connect, test, add, edit, rename, clone, reorder, and remove hosts.
- Generate new SSH keys and copy them to servers (`ssh-copy-id`).
- Backup, import, and export host configurations.
- Interactively re-order hosts in your config file.
- Edit host blocks directly in your `$EDITOR`.

## Quick Actions

Bypass the interactive menus for quick, direct actions:

- `-c, --connect`: Go directly to host selection for connecting.
- `-a, --add`: Go directly to the 'Add a new server' menu.
- `-t, --test [host|all]`: Test connection to a specific host, all hosts, or show the selection menu.
- `-h, --help`: Show the help message.

## Usage

1. Download the `ssh-manager.sh` script.
2. Make the main script executable:

    ```bash
    chmod +x ssh-manager.sh
    ```

3. Run the script:

    ```bash
    ./ssh-manager.sh
    ```

    For convenience, you can place it in a directory in your `PATH` (e.g., `~/.local/bin`).

## Contributing

Contributions of bug fixes, improvements, and documentation are welcome!

## License

MIT License
