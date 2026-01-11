#!/bin/bash

# AppImage Installer Script
# Extracts AppImage to ~/.local/share/ and symlinks to ~/.local/bin/
# Supports fresh installs and upgrades

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
UPGRADE=false
BACKUP=false
FORCE=false
DELETE_APPIMAGE=false

usage() {
    echo "Usage: $(basename "$0") [options] <appimage-file> [app-name]"
    echo ""
    echo "Arguments:"
    echo "  appimage-file   Path to the .AppImage file"
    echo "  app-name        Optional: Name for the installed app (default: derived from filename)"
    echo ""
    echo "Options:"
    echo "  -u, --upgrade   Upgrade existing installation without prompting"
    echo "  -b, --backup    Create backup of existing installation before upgrading"
    echo "  -f, --force     Force install, remove existing without prompting or backup"
    echo "  -d, --delete    Delete the original AppImage file after installation"
    echo "  -l, --list      List installed AppImages"
    echo "  -r, --remove    Remove an installed AppImage"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") fresh-editor-1.2.3-x86_64.AppImage fresh"
    echo "  $(basename "$0") --upgrade Obsidian-1.5.3.AppImage obsidian"
    echo "  $(basename "$0") -u -b myapp-2.0.AppImage    # upgrade with backup"
    echo "  $(basename "$0") --list"
    echo "  $(basename "$0") --remove obsidian"
    exit 0
}

list_installed() {
    echo -e "${BLUE}Installed AppImages:${NC}"
    echo ""
    
    SHARE_BASE="$HOME/.local/share"
    BIN_DIR="$HOME/.local/bin"
    
    found=false
    for symlink in "$BIN_DIR"/*; do
        if [ -L "$symlink" ]; then
            target=$(readlink -f "$symlink" 2>/dev/null || true)
            if [[ "$target" == "$SHARE_BASE"/* ]]; then
                app_name=$(basename "$symlink")
                app_dir=$(echo "$target" | sed "s|$SHARE_BASE/||" | cut -d'/' -f1)
                
                # Check if version info exists
                version_file="$SHARE_BASE/$app_dir/.appimage-version"
                if [ -f "$version_file" ]; then
                    version=$(cat "$version_file")
                    echo -e "  ${GREEN}$app_name${NC} (v$version)"
                else
                    echo -e "  ${GREEN}$app_name${NC}"
                fi
                echo "    Location: $SHARE_BASE/$app_dir"
                found=true
            fi
        fi
    done
    
    if [ "$found" = false ]; then
        echo "  No AppImages installed via this script."
    fi
}

remove_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        echo -e "${RED}Error: Please specify an app name to remove${NC}"
        echo "Usage: $(basename "$0") --remove <app-name>"
        exit 1
    fi
    
    SHARE_DIR="$HOME/.local/share/$app_name"
    SYMLINK_PATH="$HOME/.local/bin/$app_name"
    BACKUP_DIR="$HOME/.local/share/${app_name}.backup"
    
    if [ ! -d "$SHARE_DIR" ] && [ ! -L "$SYMLINK_PATH" ]; then
        echo -e "${RED}Error: App '$app_name' is not installed${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Removing '$app_name'...${NC}"
    
    # Remove symlink
    if [ -L "$SYMLINK_PATH" ]; then
        rm -f "$SYMLINK_PATH"
        echo "  Removed symlink: $SYMLINK_PATH"
    fi
    
    # Remove app directory
    if [ -d "$SHARE_DIR" ]; then
        rm -rf "$SHARE_DIR"
        echo "  Removed directory: $SHARE_DIR"
    fi
    
    # Remove backup if exists
    if [ -d "$BACKUP_DIR" ]; then
        read -p "Also remove backup at $BACKUP_DIR? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$BACKUP_DIR"
            echo "  Removed backup: $BACKUP_DIR"
        fi
    fi
    
    echo -e "${GREEN}✓ '$app_name' has been removed${NC}"
}

# Parse options
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--upgrade)
            UPGRADE=true
            shift
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--delete)
            DELETE_APPIMAGE=true
            shift
            ;;
        -l|--list)
            list_installed
            exit 0
            ;;
        -r|--remove)
            shift
            remove_app "$1"
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        -*|--*)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

APPIMAGE_PATH="$(realpath "$1")"
APP_NAME="${2:-}"

# Validate AppImage file exists
if [ ! -f "$APPIMAGE_PATH" ]; then
    echo -e "${RED}Error: File '$APPIMAGE_PATH' not found${NC}"
    exit 1
fi

# Derive app name from filename if not provided
if [ -z "$APP_NAME" ]; then
    # Extract base name, remove version numbers and architecture, lowercase it
    APP_NAME=$(basename "$APPIMAGE_PATH" | sed -E 's/[-_][0-9]+\.[0-9]+.*//; s/\.AppImage$//i' | tr '[:upper:]' '[:lower:]')
fi

# Try to extract version from filename
VERSION=$(basename "$APPIMAGE_PATH" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "")

# Define paths
SHARE_DIR="$HOME/.local/share/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/.local/share/${APP_NAME}.backup"
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Ensure bin directory exists
mkdir -p "$BIN_DIR"

# Check if already installed
if [ -d "$SHARE_DIR" ]; then
    EXISTING_VERSION=""
    if [ -f "$SHARE_DIR/.appimage-version" ]; then
        EXISTING_VERSION=$(cat "$SHARE_DIR/.appimage-version")
    fi
    
    if [ -n "$EXISTING_VERSION" ] && [ -n "$VERSION" ]; then
        echo -e "${BLUE}Existing installation: $APP_NAME v$EXISTING_VERSION${NC}"
        echo -e "${BLUE}New version: $VERSION${NC}"
    else
        echo -e "${YELLOW}Warning: $SHARE_DIR already exists${NC}"
    fi
    
    if [ "$FORCE" = true ]; then
        echo "Force mode: removing existing installation..."
        rm -rf "$SHARE_DIR"
    elif [ "$UPGRADE" = true ]; then
        if [ "$BACKUP" = true ]; then
            echo "Creating backup at $BACKUP_DIR..."
            rm -rf "$BACKUP_DIR"
            mv "$SHARE_DIR" "$BACKUP_DIR"
        else
            echo "Upgrade mode: removing existing installation..."
            rm -rf "$SHARE_DIR"
        fi
    else
        echo ""
        echo "Options:"
        echo "  [u] Upgrade (replace existing)"
        echo "  [b] Backup and upgrade"
        echo "  [c] Cancel"
        read -p "Choose an option [u/b/c]: " -n 1 -r
        echo
        case $REPLY in
            [Uu])
                rm -rf "$SHARE_DIR"
                ;;
            [Bb])
                echo "Creating backup at $BACKUP_DIR..."
                rm -rf "$BACKUP_DIR"
                mv "$SHARE_DIR" "$BACKUP_DIR"
                ;;
            *)
                echo "Aborted."
                exit 0
                ;;
        esac
    fi
fi

echo -e "${GREEN}Installing AppImage as '${APP_NAME}'${NC}"

# Make AppImage executable
chmod +x "$APPIMAGE_PATH"

# Extract AppImage
echo "Extracting AppImage..."
cd "$TEMP_DIR"
"$APPIMAGE_PATH" --appimage-extract > /dev/null 2>&1

# Move to final location
echo "Installing to $SHARE_DIR..."
mkdir -p "$SHARE_DIR"
mv squashfs-root/* "$SHARE_DIR/"

# Save version info
if [ -n "$VERSION" ]; then
    echo "$VERSION" > "$SHARE_DIR/.appimage-version"
fi

# Save original AppImage filename for reference
basename "$APPIMAGE_PATH" > "$SHARE_DIR/.appimage-source"

# Find the main executable
EXECUTABLE=""

# Try to find executable in usr/bin first
if [ -d "$SHARE_DIR/usr/bin" ]; then
    for f in "$SHARE_DIR/usr/bin/"*; do
        if [ -x "$f" ] && [ -f "$f" ]; then
            EXECUTABLE="$f"
            break
        fi
    done
fi

# Fall back to AppRun if no executable found
if [ -z "$EXECUTABLE" ] && [ -x "$SHARE_DIR/AppRun" ]; then
    EXECUTABLE="$SHARE_DIR/AppRun"
fi

if [ -z "$EXECUTABLE" ]; then
    echo -e "${RED}Error: Could not find executable in extracted AppImage${NC}"
    echo "Contents of $SHARE_DIR:"
    ls -la "$SHARE_DIR"
    exit 1
fi

# Create symlink
SYMLINK_PATH="$BIN_DIR/$APP_NAME"
echo "Creating symlink: $SYMLINK_PATH -> $EXECUTABLE"
ln -sf "$EXECUTABLE" "$SYMLINK_PATH"

# Delete original AppImage if requested
if [ "$DELETE_APPIMAGE" = true ]; then
    echo "Deleting original AppImage..."
    rm -f "$APPIMAGE_PATH"
fi

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "  App name:    $APP_NAME"
[ -n "$VERSION" ] && echo "  Version:     $VERSION"
echo "  Installed:   $SHARE_DIR"
echo "  Symlink:     $SYMLINK_PATH"
[ -d "$BACKUP_DIR" ] && echo -e "  Backup:      $BACKUP_DIR ${YELLOW}(remove manually when satisfied)${NC}"
echo ""

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${YELLOW}Note: ~/.local/bin is not in your PATH${NC}"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo ""
fi

echo "Run '$APP_NAME' to start the application."