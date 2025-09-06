# 🔑 SSH Manager

A user-friendly, interactive TUI for managing your `~/.ssh/config` file.

## 🧠 About

SSH Manager provides a simple and robust terminal interface for all your common SSH configuration tasks. It's designed to be a powerful alternative to manually editing your `~/.ssh/config` file, reducing errors and saving time.

It is a single, self-contained `bash` script with no external dependencies beyond standard command-line tools, making it highly portable and easy to use anywhere.

## 🧩 Features

- **Full Host Management**: Interactively connect, add, edit, rename, clone, and remove hosts.
- **Connection Testing**: Test connectivity to a single host or all hosts in parallel.
- **Key Management**: Generate new SSH key pairs (ed25519 or RSA) and copy public keys to a server with `ssh-copy-id`.
- **Safe File Operations**:
  - Re-order hosts in your config file.
  - Edit host blocks directly in your default `$EDITOR`.
  - Automatically backs up your config file before destructive operations.
- **Import/Export**: Easily export selected host configurations to a file or import them into your main config.
- **Smart & Safe**:
  - Reliably parses your config using `ssh -G`.
  - Offers to clean up orphaned key files when hosts are removed or edited.
  - Uses `awk` for safe, non-destructive file modifications.

## Quick Actions

Bypass the interactive menus for quick, direct actions:

- `-c, --connect`: Go directly to host selection for connecting.
- `-a, --add`: Go directly to the 'Add a new server' menu.
- `-t, --test [host|all]`: Test connection to a specific host, all hosts, or show the selection menu.
- `-h, --help`: Show the help message.

## Installation

1. Download the `ssh-manager.sh` script.
2. Make it executable:

    ```bash
    chmod +x ssh-manager.sh
    ```

3. Run it:

    ```bash
    ./ssh-manager.sh
    ```

    For convenience, place it in a directory that is in your `PATH` (e.g., `~/.local/bin` or `/usr/local/bin`) to run it from anywhere.

    ```bash
    # Example:
    sudo mv ssh-manager.sh /usr/local/bin/ssh-manager
    ssh-manager # Now you can run it like this
    ```

## Dependencies

The script relies on a set of common command-line tools that are pre-installed on most Linux and macOS systems:

`ssh`, `ssh-keygen`, `ssh-copy-id`, `awk`, `cat`, `grep`, `rm`, `mktemp`, `cp`, `date`

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## 📜 License

[MIT License](LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)
