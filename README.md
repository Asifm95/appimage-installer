# AppImage Installer

A simple script to install, upgrade, and manage AppImages on Linux and WSL.

## Why?

AppImages normally mount via FUSE on every launch, adding overhead. This script extracts them once for ~10x faster startup.

## Installation
```bash
curl -o ~/.local/bin/install-appimage https://raw.githubusercontent.com/YOUR_USERNAME/appimage-installer/main/install-appimage
chmod +x ~/.local/bin/install-appimage
```

## Usage
```bash
# Install an AppImage
install-appimage ~/Downloads/MyApp-1.0.0-x86_64.AppImage

# Install with custom name
install-appimage ~/Downloads/MyApp-1.0.0-x86_64.AppImage myapp

# Upgrade existing installation
install-appimage -u ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp

# Upgrade with backup
install-appimage -u -b ~/Downloads/MyApp-2.0.0-x86_64.AppImage myapp

# List installed apps
install-appimage --list

# Remove an app
install-appimage --remove myapp
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
