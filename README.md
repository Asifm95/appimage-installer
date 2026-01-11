# AppImage Installer

A simple script to install, upgrade, and manage AppImages on Linux and WSL.

## Why?

AppImages normally mount via FUSE on every launch, adding overhead. This script extracts them once for ~10x faster startup.

## Installation
```bash
curl -o ~/.local/bin/appimage-installer https://raw.githubusercontent.com/Asifm95/appimage-installer/refs/heads/master/appimage-installer.sh
chmod +x ~/.local/bin/appimage-installer
```

## Usage
```bash
# Install an AppImage
appimage-installer ~/Downloads/MyApp-1.0.0-x86_64.AppImage

# Install with custom name
appimage-installer ~/Downloads/MyApp-1.0.0-x86_64.AppImage myapp

# Upgrade existing installation
appimage-installer -u ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp

# Upgrade with backup
appimage-installer -u -b ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp

# List installed apps
appimage-installer --list

# Remove an app
appimage-installer --remove myapp
```

## Options

| Flag | Description |
|------|-------------|
| `-u, --upgrade` | Upgrade without prompting |
| `-b, --backup` | Create backup before upgrading |
| `-f, --force` | Force install, no prompts |
| `-d, --delete` | Delete AppImage after install |
| `-l, --list` | List installed AppImages |
| `-r, --remove` | Remove an installed AppImage |

## How it works

1. Extracts AppImage to `~/.local/share/<app-name>/`
2. Creates symlink in `~/.local/bin/<app-name>`
3. Tracks version for upgrade comparisons

## License

MIT
