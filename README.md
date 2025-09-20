# 🔑 SSH Manager

A user-friendly, interactive TUI for managing your `~/.ssh/config` file.

About • Demo • Features • Installation • Quick-Actions

## 🧠 About

SSH Manager provides a simple and robust terminal interface for all your common SSH configuration tasks. It's designed to be a powerful alternative to manually editing your `~/.ssh/config` file, reducing errors and saving time.

It is a single, self-contained `bash` script with no external dependencies beyond standard command-line tools, making it highly portable and easy to use anywhere.

## Screens

### Main view

```shell
+ SSH Manager
──────────────────────────────────────────────────────────────────────
   HOST ALIAS           user@hostname[:port] (key)
──────────────────────────────────────────────────────────────────────
 ❯ dev                  daniel@dev.local
   dev-clonessssssssss… daniel@dev.local:223 (~/.ssh/id_rsa)
   kvm                  daniel@kvm.main:24
   kube                 kuber@kube.test (~/ssh/kube_id_rsa)
──────────────────────────────────────────────────────────────────────
  Navigation:   ↓/↑/j/k Move | Q/ESC (Q)uit | ? for more options
──────────────────────────────────────────────────────────────────────
```

### Expanded Footer

```shell
──────────────────────────────────────────────────────────────────────
  Navigation:   ↓/↑/j/k Move | Q/ESC (Q)uit | ? for fewer options
  Host Actions: (A)dd | (D)elete | (C)lone
  Host Edit:    (E)dit host details
  Manage:       SSH (K)eys | (P)ort Forwards
                (O)pen ssh config in editor
  Connection:   ENTER Connect | (t)est selected | (T)est all
──────────────────────────────────────────────────────────────────────
```

### Add a New Host - Step 1

```shell
+ Add New SSH Host
──────────────────────────────────────────────────────────────────────
[?] How would you like to add the new host?
──────────────────────────────────────────────────────────────────────
 ❯  Create a new host from scratch 
    Clone settings from an existing host 
──────────────────────────────────────────────────────────────────────
  ↓/↑ Move | SPACE/ENTER to confirm | Q/ESC to cancel
```

### Add a New Host - Step 2

```shell
+ Add New SSH Host
──────────────────────────────────────────────────────────────────────
Configure the new host:
  1)   Host (Alias)   : (not set)
  2)   HostName       : (not set)
  3)   User           : daniel
  4)   Port           : 22
  5)   IdentityFile   : (not set)

  c) (C)ancel/(D)eset fields
  s) (S)ave and Quit
  q) (Q)uit without saving (or press ESC)

[?] Your choice: 
```

### Key Management

```shell
+ Key Management
──────────────────────────────────────────────────────────────────────
   KEY FILENAME              TYPE       BITS   COMMENT                
──────────────────────────────────────────────────────────────────────
 ❯ some_Name                 ED25519    256    @iamdanielv             
   server1                   ED25519    256    @iamdanielv   
   id_ed25519ssssssssssssss… ED25519    256    daniel@something…
   id_rsa                    RSA        3072   daniel@pop-os          
──────────────────────────────────────────────────────────────────────
  Navigation:   ↓/↑/j/k Move | Q/ESC Back
  Key Actions:  (A)dd Key | (D)elete | (R)ename
                (V)iew public | (C)opy to Server | Re-gen (P)ublic
──────────────────────────────────────────────────────────────────────
```

### Port Forwards

```shell
+ Saved Port Forwards
──────────────────────────────────────────────────────────────────────
   HOST                 FORWARD                                      
   [ ] PID      TYPE    DESCRIPTION                                  
──────────────────────────────────────────────────────────────────────
 ❯ dev.local            8081:localhost:80                            
   [-] off      Remote  web server on dev         
   kube.test            8082:localhost:80                            
   [-] off      Local   web server on kube
──────────────────────────────────────────────────────────────────────
  Navigation:   ↓/↑/j/k Move | Q/ESC Back
  Actions:      (A)dd | (D)elete | (E)dit | (C)lone | ENTER Start/Stop
──────────────────────────────────────────────────────────────────────
```

## ✨ Features

- **Responsive TUI**: Terminal interface with:
  - Clean, aligned, table-like layouts for all lists.
  - Collapsible footers to maximize content visibility.
  - In-place actions (start/stop, delete) for a smooth, flicker-free workflow.
  - input validation to prevent configuration errors.

The project is split into two scripts with distinct features:

### `ssh-manager.sh` (Main Script)

The main script provides a TUI for all your common, day-to-day SSH tasks.

- **Server Management**:
  - Interactively select a host and connect.
  - Add new hosts from scratch or by cloning an existing one.
  - Edit host parameters (alias, hostname, user, port, key file) using a step-by-step wizard.
  - `delete` and `clone` hosts.
  - Test the connection to a single host or all hosts in parallel.
- **Key Management**:
  - Generate new `ed25519` or `rsa` key pairs.
  - `delete` and `rename` key pairs.
  - Copy public keys to a remote server using `ssh-copy-id`.
  - Re-generate a public key from a private key.
  - View public key contents.
- **Port Forwarding**:
  - Save, manage, and activate port forward configurations (`~/.ssh/port_forwards.conf`).
  - View live status of active forwards.
  - `add`, `edit`, `delete`, and `clone` saved configurations.
- **Direct Config Editing**:
  - A top-level menu option provides a shortcut to open your entire `~/.ssh/config` file in your default `$EDITOR`.

### `advanced-ssh-manager.sh` (Advanced Tools)

This script provides a focused TUI for more complex or potentially destructive operations.

- **Advanced Editing**: Open a specific host's entire configuration block in your `$EDITOR`.
- **Backup**: Create a timestamped backup of your config file.
- **Import/Export**: Export selected host configurations to a new file or import them from a file into your main config.

## 🚀 Quick Actions

**Note:** The following actions apply to the main `ssh-manager.sh` script.

Bypass the interactive menus for quick, direct actions:

- `-c, --connect`: Go directly to host selection for connecting.
- `-a, --add`: Go directly to the 'Add a new server' menu.
- `-p, --port-forward`: Go directly to the 'Port Forwarding' menu.
- `-l, --list-hosts`: List all configured hosts and exit.
- `-f, --list-forwards`: List active port forwards and exit.
- `-t, --test [host|all]`: Test connection to a specific host, all hosts, or show the selection menu.
- `-h, --help`: Show the help message.

## 📦 Installation

This project now consists of two scripts:

- `ssh-manager.sh`: The main script for day-to-day server, key, and port-forwarding management.
- `advanced-ssh-manager.sh`: A separate script for advanced tasks like backups, import/export, and direct file editing.

1. Download the script(s) you need.
2. Make it executable:

    ```bash
    chmod +x ssh-manager.sh
    chmod +x advanced-ssh-manager.sh
    ```

3. Run it:

    ```bash
    ./ssh-manager.sh
    # or for advanced tools:
    ./advanced-ssh-manager.sh
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
