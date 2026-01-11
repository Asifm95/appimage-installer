# AppImage Installer

A simple script to install, upgrade, and manage AppImages on Linux and WSL.

## Why?

AppImages normally mount via FUSE on every launch, adding overhead. This script extracts them once for ~10x faster startup.

## Installation
```bash
curl -o ~/.local/bin/appimage-installer https://raw.githubusercontent.com/Asifm95/appimage-installer/refs/heads/master/appimage-installer.sh
chmod +x ~/.local/bin/appimage-installer
```

## Quick Start

```bash
# Install from GitHub releases (recommended)
appimage-installer --from github:user/repo myapp

# Install from local file
appimage-installer ~/Downloads/MyApp-1.0.0-x86_64.AppImage

# Check for updates
appimage-installer --check

# Update all apps
appimage-installer --update-all
```

## Usage

### Installing AppImages

```bash
# Install from GitHub releases (auto-configures updates)
appimage-installer --from github:obsidianmd/obsidian-releases obsidian

# Install from direct URL
appimage-installer --from direct:https://example.com/app.AppImage myapp

# Install from local file
appimage-installer ~/Downloads/MyApp-1.0.0-x86_64.AppImage

# Install with custom name
appimage-installer ~/Downloads/MyApp-1.0.0-x86_64.AppImage myapp

# Install and set update source for future updates
appimage-installer ~/Downloads/MyApp.AppImage myapp -s github:user/repo
```

### Managing Updates

```bash
# Check all apps for updates
appimage-installer --check

# Check specific app
appimage-installer --check myapp

# Update a specific app
appimage-installer --update myapp

# Update all apps with available updates
appimage-installer --update-all

# Update all without confirmation prompt
appimage-installer --update-all --force

# Set update source for an existing app
appimage-installer --set-source myapp github:user/repo
```

### Upgrading from Local Files

```bash
# Upgrade existing installation
appimage-installer -u ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp

# Upgrade with backup
appimage-installer -u -b ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp
```

### Other Operations

```bash
# List installed apps
appimage-installer --list

# Remove an app
appimage-installer --remove myapp
```

## Options

### Install Options

| Flag | Description |
|------|-------------|
| `-u, --upgrade` | Upgrade without prompting |
| `-b, --backup` | Create backup before upgrading |
| `-f, --force` | Force install, no prompts |
| `-d, --delete` | Delete AppImage after install |
| `-s, --source <url>` | Set update source URL |
| `-F, --from <source>` | Install directly from source |

### Update Options

| Flag | Description |
|------|-------------|
| `-c, --check [app]` | Check for updates (all or specific app) |
| `--update <app>` | Update a specific app |
| `--update-all` | Update all apps with available updates |
| `--set-source <app> <url>` | Set update source for existing app |

### Management Options

| Flag | Description |
|------|-------------|
| `-l, --list` | List installed AppImages |
| `-r, --remove <app>` | Remove an installed AppImage |

### Update Source Formats

| Format | Description |
|--------|-------------|
| `github:owner/repo` | Check GitHub releases for updates |
| `direct:url` | Direct download URL |

## How it works

1. Extracts AppImage to `~/.local/share/<app-name>/`
2. Creates symlink in `~/.local/bin/<app-name>`
3. Tracks version in `.appimage-version` for upgrade comparisons
4. Stores update source in `.appimage-update-url` for automatic updates

## Workflow Example

```bash
# 1. Install app from GitHub (one-time setup)
appimage-installer --from github:obsidianmd/obsidian-releases obsidian

# 2. Periodically check for updates
appimage-installer --check

# 3. Update when new version available
appimage-installer --update obsidian
# or update all at once
appimage-installer --update-all
```

## License

MIT
