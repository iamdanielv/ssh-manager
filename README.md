# 🔑 SSH Manager

A user-friendly, interactive TUI for managing your `~/.ssh/config` file.

About • Demo • Features • Installation • Quick-Actions

## 🧠 About

SSH Manager provides a simple and robust terminal interface for all your common SSH configuration tasks. It's designed to be a powerful alternative to manually editing your `~/.ssh/config` file, reducing errors and saving time.

It is a single, self-contained `bash` script with no external dependencies beyond standard command-line tools, making it highly portable and easy to use anywhere.

## ✨ Features

The script is organized into three main interactive views and an advanced tools menu.

### 🖥️ Server Management

- **Connect**: Interactively select a host and connect with `ssh`.
- **Add**: Add new hosts with a step-by-step wizard or by cloning an existing host.
- **Edit**: Modify host parameters using a simple wizard or open the host's entire config block in your `$EDITOR` for advanced changes.
- **Manage**: `delete`, `rename`, and `clone` hosts with ease.
- **Test**: Test the connection to a single host or run parallel tests for all configured hosts.

### 🔑 Key Management

- **Generate**: Create new `ed25519` or `rsa` key pairs.
- **Manage**: `delete` and `rename` key pairs (private and public).
- **Copy to Server**: Use `ssh-copy-id` to install your public key on a remote server.
- **Recover**: Re-generate a public key (`.pub`) from its private key file.
- **View**: Display the contents of a public key.

### 🔌 Port Forwarding

- **Saved Forwards**: Save, manage, and activate port forward configurations. All saved forwards are stored in `~/.ssh/port_forwards.conf`.
- **Live Status**: View which of your saved forwards are currently `[ACTIVE]` or `[INACTIVE]`.
- **Manage**: `add`, `edit`, `delete`, and `clone` saved forward configurations.
- **Activate/Deactivate**: Easily start and stop forwards with a single keypress.

### 🛠️ Advanced Tools

- **Direct Editing**: Open your entire `~/.ssh/config` file in your `$EDITOR`.
- **Re-order**: Interactively change the order of host blocks in your config file.
- **Backup**: Create a timestamped backup of your config file.
- **Import/Export**: Export selected host configurations to a file or import them from a file into your main config.

## 🚀 Quick Actions

Bypass the interactive menus for quick, direct actions:

- `-c, --connect`: Go directly to host selection for connecting.
- `-a, --add`: Go directly to the 'Add a new server' menu.
- `-p, --port-forward`: Go directly to the 'Port Forwarding' menu.
- `-l, --list-hosts`: List all configured hosts and exit.
- `-f, --list-forwards`: List active port forwards and exit.
- `-t, --test [host|all]`: Test connection to a specific host, all hosts, or show the selection menu.
- `-h, --help`: Show the help message.

## 📦 Installation

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

## ⚙️ Dependencies

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
