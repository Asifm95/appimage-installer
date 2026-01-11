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
UPDATE_SOURCE=""
INSTALL_FROM=""

usage() {
    echo "Usage: $(basename "$0") [options] <appimage-file> [app-name]"
    echo "       $(basename "$0") --from <source> [app-name]"
    echo ""
    echo "Arguments:"
    echo "  appimage-file   Path to the .AppImage file"
    echo "  app-name        Optional: Name for the installed app (default: derived from filename)"
    echo ""
    echo "Install Options:"
    echo "  -u, --upgrade          Upgrade existing installation without prompting"
    echo "  -b, --backup           Create backup of existing installation before upgrading"
    echo "  -f, --force            Force install, remove existing without prompting or backup"
    echo "  -d, --delete           Delete the original AppImage file after installation"
    echo "  -s, --source <url>     Set update source URL for the app"
    echo "  -F, --from <source>    Install directly from source (github:owner/repo or direct:url)"
    echo ""
    echo "Management Options:"
    echo "  -l, --list             List installed AppImages"
    echo "  -r, --remove <app>     Remove an installed AppImage"
    echo ""
    echo "Update Options:"
    echo "  -c, --check [app]      Check for updates (all apps if no app specified)"
    echo "  --update <app>         Update a specific app"
    echo "  --update-all           Update all apps with available updates"
    echo "  --set-source <app> <url>  Set update source for an installed app"
    echo ""
    echo "Update Source Formats:"
    echo "  github:owner/repo      Check GitHub releases for updates"
    echo "  direct:url             Direct download URL (use {version} placeholder)"
    echo ""
    echo "General Options:"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") fresh-editor-1.2.3-x86_64.AppImage fresh"
    echo "  $(basename "$0") --upgrade Obsidian-1.5.3.AppImage obsidian"
    echo "  $(basename "$0") -u -b myapp-2.0.AppImage"
    echo "  $(basename "$0") app.AppImage -s github:user/repo"
    echo "  $(basename "$0") --from github:user/repo myapp"
    echo "  $(basename "$0") -F direct:https://example.com/app.AppImage"
    echo "  $(basename "$0") --list"
    echo "  $(basename "$0") --check"
    echo "  $(basename "$0") --check myapp"
    echo "  $(basename "$0") --update myapp"
    echo "  $(basename "$0") --update-all"
    echo "  $(basename "$0") --set-source myapp github:user/repo"
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
                app_dir="$SHARE_BASE/$app_name"

                # Only show apps installed by this script (have .appimage-source file)
                if [ ! -f "$app_dir/.appimage-source" ]; then
                    continue
                fi

                # Check if version info exists
                version_file="$app_dir/.appimage-version"
                if [ -f "$version_file" ]; then
                    version=$(cat "$version_file")
                    echo -e "  ${GREEN}$app_name${NC} (v$version)"
                else
                    echo -e "  ${GREEN}$app_name${NC}"
                fi
                echo "    Location: $app_dir"

                # Show update source if configured
                update_source_file="$app_dir/.appimage-update-url"
                if [ -f "$update_source_file" ]; then
                    update_source=$(cat "$update_source_file")
                    echo -e "    Update:   $update_source"
                fi
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

# Get list of installed apps (only those installed via this script)
get_installed_apps() {
    local SHARE_BASE="$HOME/.local/share"
    local BIN_DIR="$HOME/.local/bin"

    for symlink in "$BIN_DIR"/*; do
        if [ -L "$symlink" ]; then
            target=$(readlink -f "$symlink" 2>/dev/null || true)
            if [[ "$target" == "$SHARE_BASE"/* ]]; then
                local app_name
                app_name=$(basename "$symlink")
                local app_dir="$SHARE_BASE/$app_name"
                # Only include if it was installed by this script (has .appimage-source file)
                if [ -f "$app_dir/.appimage-source" ]; then
                    echo "$app_name"
                fi
            fi
        fi
    done
}

# Get update source for an app
get_update_source() {
    local app_name="$1"
    local source_file="$HOME/.local/share/$app_name/.appimage-update-url"

    if [ -f "$source_file" ]; then
        cat "$source_file"
    fi
}

# Save update source for an app
save_update_source() {
    local app_name="$1"
    local source_url="$2"
    local source_file="$HOME/.local/share/$app_name/.appimage-update-url"

    echo "$source_url" > "$source_file"
}

# Compare two version strings
# Returns: "newer" if v2 > v1, "older" if v2 < v1, "equal" if same
compare_versions() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        echo "equal"
        return
    fi

    # Use sort -V for version comparison
    local sorted_first
    sorted_first=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)

    if [[ "$sorted_first" == "$v1" ]]; then
        echo "newer"
    else
        echo "older"
    fi
}

# Get latest version from GitHub releases
get_github_latest() {
    local repo="$1"
    local api_url="https://api.github.com/repos/$repo/releases/latest"

    local response
    response=$(curl -s --fail "$api_url" 2>/dev/null) || return 1

    # Extract tag_name and remove leading 'v' if present
    local version
    version=$(echo "$response" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')

    if [ -n "$version" ]; then
        echo "$version"
    else
        return 1
    fi
}

# Get download URL for AppImage from GitHub releases
get_github_download_url() {
    local repo="$1"
    local api_url="https://api.github.com/repos/$repo/releases/latest"

    local response
    response=$(curl -s --fail "$api_url" 2>/dev/null) || return 1

    # Find AppImage download URL (look for .AppImage in browser_download_url)
    local download_url
    download_url=$(echo "$response" | grep -o '"browser_download_url": *"[^"]*\.AppImage"' | head -1 | cut -d'"' -f4)

    # If not found, try case-insensitive
    if [ -z "$download_url" ]; then
        download_url=$(echo "$response" | grep -oi '"browser_download_url": *"[^"]*\.appimage"' | head -1 | cut -d'"' -f4)
    fi

    if [ -n "$download_url" ]; then
        echo "$download_url"
    else
        return 1
    fi
}

# Download AppImage from source (github:owner/repo or direct:url)
# Outputs: path to downloaded file
download_from_source() {
    local source="$1"
    local source_type="${source%%:*}"
    local source_value="${source#*:}"

    # Validate source format
    case "$source_type" in
        github|direct)
            ;;
        *)
            echo -e "${RED}Error: Invalid source format. Use 'github:owner/repo' or 'direct:url'${NC}" >&2
            return 1
            ;;
    esac

    local download_url=""
    local filename=""

    case "$source_type" in
        github)
            echo -e "${BLUE}Fetching latest release from GitHub: $source_value${NC}" >&2
            download_url=$(get_github_download_url "$source_value")
            if [ -z "$download_url" ]; then
                echo -e "${RED}Error: Could not find AppImage in GitHub releases${NC}" >&2
                return 1
            fi
            filename=$(basename "$download_url")
            ;;
        direct)
            download_url="$source_value"
            filename=$(basename "$download_url" | sed 's/?.*//')  # Remove query params
            ;;
    esac

    # Create temp directory for download
    local temp_dir
    temp_dir=$(mktemp -d)
    local temp_file="$temp_dir/$filename"

    # Download with progress
    echo -e "${BLUE}Downloading: $download_url${NC}" >&2
    if ! curl -L --progress-bar -o "$temp_file" "$download_url"; then
        echo -e "${RED}Error: Download failed${NC}" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    # Verify it's a valid file (not an error page)
    if [ ! -s "$temp_file" ]; then
        echo -e "${RED}Error: Downloaded file is empty${NC}" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    echo "$temp_file"
}

# Check if update is available for an app
# Returns: "available <new_version>", "up-to-date", "no-source", or "error <message>"
check_app_update() {
    local app_name="$1"
    local share_dir="$HOME/.local/share/$app_name"

    # Get current version
    local current_version=""
    if [ -f "$share_dir/.appimage-version" ]; then
        current_version=$(cat "$share_dir/.appimage-version")
    fi

    # Get update source
    local source
    source=$(get_update_source "$app_name")

    if [ -z "$source" ]; then
        echo "no-source"
        return
    fi

    # Parse source type
    local source_type="${source%%:*}"
    local source_value="${source#*:}"

    case "$source_type" in
        github)
            local latest_version
            latest_version=$(get_github_latest "$source_value" 2>/dev/null)

            if [ -z "$latest_version" ]; then
                echo "error:Failed to fetch GitHub release"
                return
            fi

            if [ -z "$current_version" ]; then
                echo "available:$latest_version"
                return
            fi

            local comparison
            comparison=$(compare_versions "$current_version" "$latest_version")

            if [ "$comparison" = "newer" ]; then
                echo "available:$latest_version"
            else
                echo "up-to-date"
            fi
            ;;
        direct)
            # For direct URLs, we can't easily check versions
            # Just report current status
            echo "up-to-date"
            ;;
        *)
            echo "error:Unknown source type: $source_type"
            ;;
    esac
}

# Check for updates command
check_updates() {
    local specific_app="$1"

    echo -e "${BLUE}Checking for updates...${NC}"
    echo ""

    local apps_checked=0
    local updates_available=0
    local max_name_len=0

    # First pass: get max name length for formatting
    if [ -n "$specific_app" ]; then
        max_name_len=${#specific_app}
    else
        while IFS= read -r app; do
            [ ${#app} -gt $max_name_len ] && max_name_len=${#app}
        done < <(get_installed_apps)
    fi

    # Check apps
    check_single_app() {
        local app="$1"
        local share_dir="$HOME/.local/share/$app"

        if [ ! -d "$share_dir" ]; then
            echo -e "  ${RED}$app${NC}: not installed"
            return
        fi

        local current_version=""
        if [ -f "$share_dir/.appimage-version" ]; then
            current_version=$(cat "$share_dir/.appimage-version")
        fi

        local result
        result=$(check_app_update "$app")

        local status="${result%%:*}"
        local info="${result#*:}"

        # Format app name with padding
        local padded_name
        printf -v padded_name "%-${max_name_len}s" "$app"

        case "$status" in
            available)
                if [ -n "$current_version" ]; then
                    echo -e "  ${GREEN}$padded_name${NC}  $current_version → $info  ${YELLOW}[UPDATE AVAILABLE]${NC}"
                else
                    echo -e "  ${GREEN}$padded_name${NC}  → $info  ${YELLOW}[UPDATE AVAILABLE]${NC}"
                fi
                ((updates_available++)) || true
                ;;
            up-to-date)
                if [ -n "$current_version" ]; then
                    echo -e "  ${GREEN}$padded_name${NC}  $current_version  ${BLUE}[up to date]${NC}"
                else
                    echo -e "  ${GREEN}$padded_name${NC}  ${BLUE}[up to date]${NC}"
                fi
                ;;
            no-source)
                if [ -n "$current_version" ]; then
                    echo -e "  ${GREEN}$padded_name${NC}  $current_version  [no update source]"
                else
                    echo -e "  ${GREEN}$padded_name${NC}  [no update source]"
                fi
                ;;
            error)
                echo -e "  ${GREEN}$padded_name${NC}  ${RED}[error: $info]${NC}"
                ;;
        esac

        ((apps_checked++)) || true
    }

    if [ -n "$specific_app" ]; then
        check_single_app "$specific_app"
    else
        while IFS= read -r app; do
            check_single_app "$app"
        done < <(get_installed_apps)
    fi

    echo ""

    if [ $apps_checked -eq 0 ]; then
        echo "No installed AppImages found."
    elif [ $updates_available -gt 0 ]; then
        echo -e "${GREEN}$updates_available update(s) available.${NC} Run '$(basename "$0") --update-all' to update."
    else
        echo "All apps are up to date."
    fi
}

# Update a single app
update_app() {
    local app_name="$1"
    local share_dir="$HOME/.local/share/$app_name"

    if [ ! -d "$share_dir" ]; then
        echo -e "${RED}Error: App '$app_name' is not installed${NC}"
        return 1
    fi

    local source
    source=$(get_update_source "$app_name")

    if [ -z "$source" ]; then
        echo -e "${RED}Error: No update source configured for '$app_name'${NC}"
        echo "Set one with: $(basename "$0") --set-source $app_name github:owner/repo"
        return 1
    fi

    local source_type="${source%%:*}"
    local source_value="${source#*:}"

    # Check if update is available
    local result
    result=$(check_app_update "$app_name")
    local status="${result%%:*}"
    local new_version="${result#*:}"

    if [ "$status" = "up-to-date" ]; then
        echo -e "${BLUE}$app_name is already up to date${NC}"
        return 0
    elif [ "$status" = "error" ]; then
        echo -e "${RED}Error checking for updates: $new_version${NC}"
        return 1
    elif [ "$status" = "no-source" ]; then
        echo -e "${RED}Error: No update source configured${NC}"
        return 1
    fi

    echo -e "${GREEN}Updating $app_name...${NC}"

    local current_version=""
    if [ -f "$share_dir/.appimage-version" ]; then
        current_version=$(cat "$share_dir/.appimage-version")
    fi

    if [ -n "$current_version" ]; then
        echo "  $current_version → $new_version"
    fi

    # Get download URL based on source type
    local download_url=""

    case "$source_type" in
        github)
            download_url=$(get_github_download_url "$source_value")
            if [ -z "$download_url" ]; then
                echo -e "${RED}Error: Could not find AppImage download URL${NC}"
                return 1
            fi
            ;;
        direct)
            download_url="$source_value"
            ;;
        *)
            echo -e "${RED}Error: Unknown source type: $source_type${NC}"
            return 1
            ;;
    esac

    # Create temp directory for download
    local temp_dir
    temp_dir=$(mktemp -d)
    local temp_file="$temp_dir/update.AppImage"

    # Download with progress
    echo "  Downloading..."
    if ! curl -L --progress-bar -o "$temp_file" "$download_url"; then
        echo -e "${RED}Error: Download failed${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # Install the update using this script with upgrade flag
    echo "  Installing..."

    # Save the update source before upgrade (it will be preserved in the new install)
    local saved_source="$source"

    # Run the install with upgrade flag
    if "$0" --upgrade --delete "$temp_file" "$app_name"; then
        # Restore the update source
        save_update_source "$app_name" "$saved_source"
        echo -e "${GREEN}✓ Successfully updated $app_name to version $new_version${NC}"
    else
        echo -e "${RED}Error: Update installation failed${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"
    return 0
}

# Update all apps
update_all_apps() {
    echo -e "${BLUE}Checking for updates...${NC}"
    echo ""

    local apps_to_update=()
    local app_versions=()

    # Find all apps with available updates
    while IFS= read -r app; do
        local result
        result=$(check_app_update "$app")
        local status="${result%%:*}"
        local new_version="${result#*:}"

        if [ "$status" = "available" ]; then
            apps_to_update+=("$app")
            app_versions+=("$new_version")
        fi
    done < <(get_installed_apps)

    if [ ${#apps_to_update[@]} -eq 0 ]; then
        echo "All apps are up to date."
        return 0
    fi

    echo "Updates available for:"
    for i in "${!apps_to_update[@]}"; do
        local app="${apps_to_update[$i]}"
        local new_version="${app_versions[$i]}"
        local current_version=""

        if [ -f "$HOME/.local/share/$app/.appimage-version" ]; then
            current_version=$(cat "$HOME/.local/share/$app/.appimage-version")
        fi

        if [ -n "$current_version" ]; then
            echo -e "  ${GREEN}$app${NC}: $current_version → $new_version"
        else
            echo -e "  ${GREEN}$app${NC}: → $new_version"
        fi
    done
    echo ""

    # Confirm unless force mode
    if [ "$FORCE" != true ]; then
        read -p "Update ${#apps_to_update[@]} app(s)? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 0
        fi
    fi

    echo ""

    # Update each app
    local success_count=0
    local fail_count=0

    for app in "${apps_to_update[@]}"; do
        echo "─────────────────────────────────────"
        if update_app "$app"; then
            ((success_count++)) || true
        else
            ((fail_count++)) || true
        fi
        echo ""
    done

    echo "─────────────────────────────────────"
    echo ""
    if [ $fail_count -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully updated $success_count app(s)${NC}"
    else
        echo -e "${YELLOW}Updated $success_count app(s), $fail_count failed${NC}"
    fi
}

# Set update source for an app
set_update_source() {
    local app_name="$1"
    local source_url="$2"
    local share_dir="$HOME/.local/share/$app_name"

    if [ -z "$app_name" ]; then
        echo -e "${RED}Error: Please specify an app name${NC}"
        echo "Usage: $(basename "$0") --set-source <app-name> <source-url>"
        return 1
    fi

    if [ -z "$source_url" ]; then
        echo -e "${RED}Error: Please specify an update source URL${NC}"
        echo "Usage: $(basename "$0") --set-source <app-name> <source-url>"
        echo ""
        echo "Source formats:"
        echo "  github:owner/repo    - GitHub releases"
        echo "  direct:https://...   - Direct download URL"
        return 1
    fi

    if [ ! -d "$share_dir" ]; then
        echo -e "${RED}Error: App '$app_name' is not installed${NC}"
        return 1
    fi

    # Validate source format
    local source_type="${source_url%%:*}"
    case "$source_type" in
        github|direct)
            ;;
        *)
            echo -e "${RED}Error: Invalid source format. Use 'github:owner/repo' or 'direct:url'${NC}"
            return 1
            ;;
    esac

    save_update_source "$app_name" "$source_url"
    echo -e "${GREEN}✓ Update source set for '$app_name': $source_url${NC}"

    # Optionally check if it works
    echo ""
    echo "Verifying source..."
    local result
    result=$(check_app_update "$app_name")
    local status="${result%%:*}"
    local info="${result#*:}"

    case "$status" in
        available)
            echo -e "${GREEN}✓ Source valid. Update available: $info${NC}"
            ;;
        up-to-date)
            echo -e "${GREEN}✓ Source valid. App is up to date.${NC}"
            ;;
        error)
            echo -e "${YELLOW}Warning: Could not verify source: $info${NC}"
            ;;
    esac
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
        -c|--check)
            shift
            check_updates "$1"
            exit 0
            ;;
        --update)
            shift
            if [ -z "$1" ]; then
                echo -e "${RED}Error: Please specify an app name${NC}"
                echo "Usage: $(basename "$0") --update <app-name>"
                exit 1
            fi
            update_app "$1"
            exit $?
            ;;
        --update-all)
            shift
            update_all_apps
            exit $?
            ;;
        --set-source)
            shift
            set_update_source "$1" "$2"
            exit $?
            ;;
        -s|--source)
            shift
            UPDATE_SOURCE="$1"
            shift
            ;;
        -F|--from)
            shift
            INSTALL_FROM="$1"
            shift
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

# Handle install from URL
if [ -n "$INSTALL_FROM" ]; then
    # Download the AppImage from the source
    APPIMAGE_PATH=$(download_from_source "$INSTALL_FROM")
    if [ $? -ne 0 ] || [ -z "$APPIMAGE_PATH" ]; then
        exit 1
    fi

    # Auto-set update source for future updates
    if [ -z "$UPDATE_SOURCE" ]; then
        UPDATE_SOURCE="$INSTALL_FROM"
    fi

    # Clean up downloaded file after installation
    DELETE_APPIMAGE=true

    # App name from positional arg or derive from source
    APP_NAME="${1:-}"
    if [ -z "$APP_NAME" ]; then
        # Try to derive from GitHub repo name or filename
        source_type="${INSTALL_FROM%%:*}"
        source_value="${INSTALL_FROM#*:}"
        if [ "$source_type" = "github" ]; then
            # Use repo name (e.g., "obsidian-releases" from "obsidianmd/obsidian-releases")
            APP_NAME=$(echo "$source_value" | cut -d'/' -f2 | tr '[:upper:]' '[:lower:]')
        fi
    fi
else
    # Check arguments for local file install
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

# Save update source if provided
if [ -n "$UPDATE_SOURCE" ]; then
    save_update_source "$APP_NAME" "$UPDATE_SOURCE"
fi

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
[ -n "$UPDATE_SOURCE" ] && echo "  Update src:  $UPDATE_SOURCE"
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