#!/usr/bin/env bash
#
# remove_claude.sh — Reverse deploy_claude.sh, clean removal
#
# Removes everything installed by deploy_claude.sh:
#   Claude Code CLI, Node.js, NodeSource repo, config files
#
# Usage:
#   sudo ./remove_claude.sh              # Interactive (asks for each step)
#   sudo ./remove_claude.sh --auto       # Non-interactive, remove all
#   sudo ./remove_claude.sh --dry-run    # Show what would be removed
#
# Licensed under MIT.

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour & style constants
# ---------------------------------------------------------------------------

readonly R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m'
readonly P=$'\033[35m' C=$'\033[36m' D=$'\033[2m' BD=$'\033[1m'
readonly RS=$'\033[0m'

OK="${G}OK${RS}"  WA="${Y}!!${RS}"  ER="${R}ER${RS}"
IN="${B}==${RS}"  AR="${P}->${RS}"

# ---------------------------------------------------------------------------
# Mutable state
# ---------------------------------------------------------------------------

DRY_RUN=false
AUTO=false
HAS_NODESOURCE=false
NODE_SOURCE=""

log_info()  { echo -e " ${IN}  ${BD}$*${RS}"; }
log_warn()  { echo -e " ${WA}  ${BD}$*${RS}"; }
log_error() { echo -e " ${ER}  ${BD}$*${RS}"; }
log_ok()    { echo -e " ${OK}  $*"; }
log_step()  { echo -e "\n ${AR}  ${BD}$*${RS}"; }
log_dim()   { echo -e "${D}$*${RS}"; }

confirm_yes() {
    [ "$AUTO" = true ] && return 0
    local prompt="$1" default="${2:-N}"
    local ans
    while true; do
        read -r -p "$(echo -e " ${IN}  ${prompt} [${default}] ")" ans
        ans="${ans:-$default}"
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "   Please enter y or n" ;;
        esac
    done
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo &>/dev/null; then
            log_info "Elevating via sudo ..."
            exec sudo bash "$0" "$@"
        fi
        log_error "This script needs root privileges."
        log_error "Run: sudo bash $0"
        exit 1
    fi
}

# Return the real user's home directory (not /root/)
user_home() {
    local u=""
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        u="$SUDO_USER"
    elif [ -n "${LOGNAME:-}" ] && [ "$LOGNAME" != "root" ]; then
        u="$LOGNAME"
    else
        u="$(logname 2>/dev/null || echo "")"
    fi
    if [ -n "$u" ] && [ "$u" != "root" ]; then
        local dir
        dir="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            echo "$dir"
            return
        fi
        echo "/home/${u}"
    else
        echo "$HOME"
    fi
}

run() {
    if [ "$DRY_RUN" = true ]; then
        log_dim "    (dry-run) $*"
        return 0
    fi
    "$@"
}

# ---------------------------------------------------------------------------
# Detection: what did deploy_claude.sh install?
# ---------------------------------------------------------------------------

detect_state() {
    log_step "Detecting installed components ..."

    # NodeSource repo files
    if [ -f /etc/apt/sources.list.d/nodesource.list ] || \
       [ -f /etc/apt/sources.list.d/nodesource.sources ]; then
        HAS_NODESOURCE=true
        log_dim "  NodeSource repo: found"
    else
        log_dim "  NodeSource repo: not found"
    fi

    # Node.js origin
    if command -v node &>/dev/null; then
        local node_path node_ver
        node_path="$(command -v node)"
        node_ver="$(node --version 2>/dev/null || true)"
        if [ "$HAS_NODESOURCE" = true ]; then
            NODE_SOURCE="apt"
            log_dim "  Node.js: from NodeSource/apt (${node_path}, ${node_ver})"
        elif [ "$node_path" = "/usr/local/bin/node" ]; then
            NODE_SOURCE="binary"
            log_dim "  Node.js: from binary tarball (${node_path}, ${node_ver})"
        else
            NODE_SOURCE="unknown"
            log_dim "  Node.js: from unknown source (${node_path}, ${node_ver})"
        fi
    else
        log_dim "  Node.js: not found"
    fi

    # Claude Code CLI
    if command -v claude &>/dev/null; then
        local claude_ver
        claude_ver="$(claude --version 2>/dev/null || echo "installed")"
        log_dim "  Claude Code CLI: ${claude_ver}"
    else
        log_dim "  Claude Code CLI: not found"
    fi

    # Claude config directory
    local claude_dir
    claude_dir="$(user_home)/.claude"
    if [ -d "$claude_dir" ]; then
        log_dim "  Claude config: ${claude_dir}"
    else
        log_dim "  Claude config: not found"
    fi

    # APT backup files from bootstrap
    if [ -d /etc/apt/backups ]; then
        log_dim "  APT backups: /etc/apt/backups"
    fi
}

# ---------------------------------------------------------------------------
# Remove Claude Code CLI
# ---------------------------------------------------------------------------

remove_claude_code() {
    log_step "Removing Claude Code CLI ..."

    if ! command -v claude &>/dev/null && ! npm list -g @anthropic-ai/claude-code &>/dev/null 2>&1; then
        log_ok "Claude Code CLI not found, skipping"
        return 0
    fi

    if confirm_yes "Remove Claude Code CLI?" "Y"; then
        if command -v npm &>/dev/null; then
            log_info "Uninstalling @anthropic-ai/claude-code ..."
            run npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
        if [ -L /usr/local/bin/claude ]; then
            log_info "Removing claude symlink ..."
            run rm -f /usr/local/bin/claude
        fi
        log_ok "Claude Code CLI removed"
    fi
}

# ---------------------------------------------------------------------------
# Remove Claude config (~/.claude/)
# ---------------------------------------------------------------------------

remove_claude_config() {
    local claude_dir
    claude_dir="$(user_home)/.claude"

    log_step "Removing Claude Code config ..."

    if [ ! -d "$claude_dir" ]; then
        log_ok "Claude config not found, skipping"
        return 0
    fi

    if confirm_yes "Remove Claude config (${claude_dir})?" "Y"; then
        run rm -rf "$claude_dir"
        log_ok "Claude config removed"
    fi
}

# ---------------------------------------------------------------------------
# Remove Node.js
# ---------------------------------------------------------------------------

remove_nodejs() {
    log_step "Removing Node.js ..."

    if ! command -v node &>/dev/null; then
        log_ok "Node.js not found, skipping"
        return 0
    fi

    if ! confirm_yes "Remove Node.js and npm?" "Y"; then
        return 0
    fi

    case "$NODE_SOURCE" in
        apt)
            log_info "Removing Node.js and npm packages ..."
            run apt-get remove -y -qq nodejs npm 2>/dev/null || \
            run apt-get remove -y nodejs npm 2>/dev/null || true
            run apt-get autoremove -y -qq 2>/dev/null || true
            log_ok "Node.js removed (apt)"
            ;;
        binary)
            log_info "Removing Node.js binary files ..."
            run rm -f /usr/local/bin/node
            run rm -f /usr/local/bin/npm
            run rm -f /usr/local/bin/npx
            run rm -f /usr/local/bin/corepack
            run rm -rf /usr/local/lib/node_modules
            run rm -rf /usr/local/include/node
            run rm -f /usr/local/share/man/man1/node.1
            run rm -f /usr/local/share/systemtap/tapset/node.stp 2>/dev/null || true
            log_ok "Node.js removed (binary tarball)"
            ;;
        unknown)
            log_warn "Node.js source unknown — keeping it"
            log_warn "  Remove manually: sudo apt-get remove nodejs"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Remove NodeSource repository
# ---------------------------------------------------------------------------

remove_nodesource() {
    log_step "Removing NodeSource repository ..."

    if [ "$HAS_NODESOURCE" != true ]; then
        log_ok "NodeSource repo not found, skipping"
        return 0
    fi

    if ! confirm_yes "Remove NodeSource apt repository?" "Y"; then
        return 0
    fi

    # Remove repo files
    for f in /etc/apt/sources.list.d/nodesource.list \
             /etc/apt/sources.list.d/nodesource.sources; do
        if [ -f "$f" ]; then
            run rm -f "$f"
            log_dim "  Removed ${f}"
        fi
    done

    # Remove GPG key
    local keyrings=(/usr/share/keyrings/nodesource.gpg)
    # Also check for the legacy trusted.gpg.d location
    if [ -f /etc/apt/trusted.gpg.d/nodesource.gpg ]; then
        keyrings+=(/etc/apt/trusted.gpg.d/nodesource.gpg)
    fi
    for k in "${keyrings[@]}"; do
        if [ -f "$k" ]; then
            run rm -f "$k"
            log_dim "  Removed GPG key: ${k}"
        fi
    done

    run apt-get update -qq 2>/dev/null || true
    log_ok "NodeSource repository removed"
}

# ---------------------------------------------------------------------------
# Restore original APT sources
# ---------------------------------------------------------------------------

restore_apt_sources() {
    log_step "Restoring APT sources ..."

    if [ ! -d /etc/apt/backups ]; then
        log_ok "No APT backups found, skipping"
        return 0
    fi

    if ! confirm_yes "Restore original APT sources from backup?" "N"; then
        return 0
    fi

    local restored=false
    for backup in /etc/apt/backups/sources.list.*; do
        [ -f "$backup" ] || continue
        run cp "$backup" /etc/apt/sources.list
        log_ok "Restored: ${backup} → /etc/apt/sources.list"
        restored=true
        break
    done
    for backup in /etc/apt/backups/debian.sources.* /etc/apt/backups/ubuntu.sources.*; do
        [ -f "$backup" ] || continue
        local fname; fname="$(basename "$backup")"
        local target="/etc/apt/sources.list.d/${fname%.*}"
        run cp "$backup" "$target"
        log_ok "Restored: ${backup} → ${target}"
        restored=true
    done

    if [ "$restored" = true ]; then
        run apt-get update -qq 2>/dev/null || log_warn "apt update failed — check sources manually"
        log_ok "APT sources restored"
    else
        log_ok "No usable backups found"
    fi

    if confirm_yes "Remove APT backup directory?" "N"; then
        run rm -rf /etc/apt/backups
        log_ok "Backup directory removed"
    fi
}

# ---------------------------------------------------------------------------
# Remove system packages (optional)
# ---------------------------------------------------------------------------

remove_system_packages() {
    log_step "System packages ..."

    local installed=()
    for pkg in curl ca-certificates git; do
        if dpkg -s "$pkg" &>/dev/null 2>&1; then
            installed+=("$pkg")
        fi
    done

    if [ ${#installed[@]} -eq 0 ]; then
        log_ok "No bootstrap-installed system packages found"
        return 0
    fi

    log_warn "The following packages were installed by deploy_claude.sh:"
    log_warn "  ${installed[*]}"
    log_warn "They may be needed by other software on this system."
    log_warn "Use 'apt-mark showauto' to check, or keep them."

    if confirm_yes "Remove these packages?" "N"; then
        run apt-get remove -y -qq "${installed[@]}" 2>/dev/null || \
        run apt-get remove -y "${installed[@]}" 2>/dev/null || true
        run apt-get autoremove -y -qq 2>/dev/null || true
        log_ok "System packages removed"
    else
        log_ok "Keeping system packages"
    fi
}

# ---------------------------------------------------------------------------
# Restore .npmrc (remove registry override)
# ---------------------------------------------------------------------------

restore_npmrc() {
    log_step "Restoring .npmrc ..."

    local target
    target="$(user_home)/.npmrc"

    if [ ! -f "$target" ]; then
        log_ok ".npmrc not found, skipping"
        return 0
    fi

    if ! grep -q "^registry=" "$target" 2>/dev/null; then
        log_ok "No registry override found in .npmrc"
        return 0
    fi

    if confirm_yes "Remove npm registry override from ${target}?" "Y"; then
        if [ "$DRY_RUN" != true ]; then
            sed -i '/^registry=/d' "$target"
        fi
        log_ok "npm registry override removed from ${target}"

        # Clean up empty .npmrc
        if [ ! -s "$target" ]; then
            run rm -f "$target"
            log_dim "  Removed empty .npmrc"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

print_summary() {
    echo
    echo "============================================"
    echo "        Uninstall Complete"
    echo "============================================"
    echo
    echo "  Remaining:"
    command -v node   &>/dev/null && echo "  Node.js: $(node --version) (kept)"   || echo "  Node.js: removed"
    command -v claude &>/dev/null && echo "  Claude Code CLI: $(claude --version 2>/dev/null || echo 'installed') (kept)" || echo "  Claude Code CLI: removed"
    local cfg; cfg="$(user_home)/.claude"
    [ -d "$cfg" ] && echo "  Claude config: ${cfg} (kept)" || echo "  Claude config: removed"
    echo
    [ "$DRY_RUN" = true ] && log_dim "  This was a dry-run — no changes were made."
    echo
    log_dim "  To reinstall: sudo bash deploy_claude.sh"
    echo
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --auto|-a)    AUTO=true; shift ;;
            --dry-run|-n) DRY_RUN=true; shift ;;
            --help|-h)
                echo "Usage: sudo $0 [OPTIONS]"
                echo
                echo "  --auto, -a      Non-interactive, remove everything"
                echo "  --dry-run, -n   Show what would be removed without doing it"
                echo "  --help, -h      Show this help"
                exit 0
                ;;
            *) echo "Unknown: $1"; exit 1 ;;
        esac
    done

    require_root "$@"

    echo
    echo "============================================"
    echo "  Claude Code CLI — Uninstall"
    echo "============================================"
    [ "$DRY_RUN" = true ] && log_warn "DRY-RUN MODE — no changes will be made"
    echo
    log_warn "This will remove Claude Code CLI and optionally Node.js."
    log_warn "System packages (curl, git, ca-certificates) are kept by default."
    echo

    if [ "$AUTO" != true ]; then
        confirm_yes "Proceed with uninstall?" "N" || exit 0
    fi

    detect_state
    echo
    remove_claude_code
    echo
    remove_claude_config
    echo
    remove_nodejs
    echo
    remove_nodesource
    echo
    restore_apt_sources
    echo
    remove_system_packages
    echo
    restore_npmrc
    echo
    print_summary
}

main "$@"
