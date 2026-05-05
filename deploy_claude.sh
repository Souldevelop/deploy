#!/usr/bin/env bash
#
# deploy_claude.sh — One-click Claude Code CLI deployment for Debian/Ubuntu
#
# Remote usage (host on any web server):
#   curl -fsSL https://your.host/deploy_claude.sh | sudo bash
#   curl -fsSL https://your.host/deploy_claude.sh | sudo bash -s -- --china
#   curl -fsSL https://your.host/deploy_claude.sh | sudo bash -s -- --quick --china
#
# Local usage:
#   ./deploy_claude.sh                  # Interactive menu
#   ./deploy_claude.sh --quick          # Auto mode, best-effort defaults
#   ./deploy_claude.sh --quick --china  # China-optimised auto mode
#   ./deploy_claude.sh --install        # Copy to /usr/local/bin for PATH use
#
# Supports:
#   Debian  11 (bullseye) / 12 (bookworm) / 13 (trixie)
#   Ubuntu  18.04 (bionic) ~ 26.x
#
# Licensed under MIT.

set -euo pipefail

# Self-repair: strip Windows CRLF from the script file if present.
# This only applies to local file execution (curl|bash is unaffected).
if [ -w "$0" ] && grep -q $'\r' "$0" 2>/dev/null; then
    sed -i 's/\r$//' "$0"
    exec bash "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Colour & style constants
# ---------------------------------------------------------------------------

readonly R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m'
readonly P=$'\033[35m' C=$'\033[36m' D=$'\033[2m' BD=$'\033[1m'
readonly RS=$'\033[0m'

OK="${G}OK${RS}"  WA="${Y}!!${RS}"  ER="${R}ER${RS}"
IN="${B}==${RS}"  AR="${P}->${RS}"

# ---------------------------------------------------------------------------
# Mutable state (updated during execution)
# ---------------------------------------------------------------------------

DISTRO_ID=""
VERSION_ID=""
CODENAME=""
ARCH=""
APT_MIRROR=""
NPM_MIRROR=""
USE_CHINA=false

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# 脚本自身的下载地址（用于管道模式自动提权）。
# 可通过环境变量 BOOTSTRAP_SELF_URL 覆盖。
readonly SELF_SOURCE="${BOOTSTRAP_SELF_URL:-https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh}"

# ---------------------------------------------------------------------------
# APT mirror presets
# ---------------------------------------------------------------------------

MIRROR_LIST_CHINA=(
    "mirrors.aliyun.com|Alibaba Cloud"
    "mirrors.tencent.com|Tencent Cloud"
    "mirrors.huaweicloud.com|Huawei Cloud"
    "mirrors.tuna.tsinghua.edu.cn|Tsinghua University"
    "mirrors.ustc.edu.cn|USTC"
    "mirrors.163.com|NetEase"
    "mirrors.zju.edu.cn|Zhejiang University"
    "mirrors.nju.edu.cn|Nanjing University"
    "mirror.sjtu.edu.cn|Shanghai Jiao Tong University"
    "mirrors.pku.edu.cn|Peking University"
)

MIRROR_LIST_GLOBAL=(
    "deb.debian.org|Debian Official Mirror"
    "archive.ubuntu.com|Ubuntu Official Mirror"
    "mirrors.kernel.org|Kernel.org"
    "mirrors.mit.edu|MIT"
)

# ---------------------------------------------------------------------------
# npm mirror presets
# ---------------------------------------------------------------------------

NPM_MIRROR_LIST=(
    "https://registry.npmjs.org/|npm (official)"
    "https://registry.npmmirror.com/|npmmirror (China)"
)

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

log_info()  { echo -e " ${IN}  ${BD}$*${RS}"; }
log_warn()  { echo -e " ${WA}  ${BD}$*${RS}"; }
log_error() { echo -e " ${ER}  ${BD}$*${RS}"; }
log_ok()    { echo -e " ${OK}  $*"; }
log_step()  { echo -e "\n ${AR}  ${BD}$*${RS}"; }
log_dim()   { echo -e "${D}$*${RS}"; }

confirm_yes() {
    local prompt="$1" default="${2:-Y}" ans
    while true; do
        if [ -t 0 ]; then
            read -r -p "$(echo -e " ${IN}  ${prompt} [${default}] ")" ans
        else
            read -r -p "$(echo -e " ${IN}  ${prompt} [${default}] ")" ans </dev/tty
        fi
        ans="${ans:-$default}"
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "   Please enter y or n" ;;
        esac
    done
}

pick_number() {
    local max="$1" n
    if [ -t 0 ]; then
        read -r -p "$(echo -e " ${IN}  Enter choice [0-${max}]: ")" n
    else
        read -r -p "$(echo -e " ${IN}  Enter choice [0-${max}]: ")" n </dev/tty
    fi
    echo "${n:-0}"
}

# 别名：在管道模式下也一样读取终端

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        local from_stdin=false
        [ ! -t 0 ] && from_stdin=true

        # ------- 本地文件模式：直接提权重新执行 -------
        if [ "$from_stdin" = false ] && [ -f "$0" ]; then
            if command -v sudo &>/dev/null; then
                log_info "Elevating via sudo ..."
                exec sudo bash "$0" "$@"
            fi
            if command -v su &>/dev/null; then
                log_info "Elevating via su (sudo not found) ..."
                # 写包装脚本，避免 su -c 对命令字符串的解析问题
                local wrapper="/tmp/.su-wrapper.sh"
                {
                    echo '#!/bin/sh'
                    printf "exec bash '%s'" "$0"
                    for _arg in "$@"; do printf " '%s'" "$_arg"; done
                    echo
                } > "$wrapper"
                chmod +x "$wrapper"
                exec su -c "$wrapper" < /dev/tty
            fi
            log_error "Cannot elevate — install sudo or run as root"
            exit 1
        fi

        # ------- 管道模式：下载到临时文件后提权重新执行 -------
        if [ "$from_stdin" = true ]; then
            log_info "Downloading script for privilege elevation ..."
            local tmp="/tmp/deploy_claude.sh"
            if ! download_file "$SELF_SOURCE" "$tmp"; then
                log_error "Failed to download script for elevation"
                exit 1
            fi
            chmod +x "$tmp"

            # 如果 --config 来自进程替换 (/dev/fd/*)，提权前先拷贝到临时文件
            local args=("$@")
            for ((i = 0; i < ${#args[@]}; i++)); do
                if [ "${args[$i]}" = "--config" ] && [[ "${args[$i+1]:-}" == /dev/fd/* ]]; then
                    local tmp_conf="/tmp/deploy.conf"
                    cat "${args[$i+1]}" > "$tmp_conf" 2>/dev/null || true
                    if [ -s "$tmp_conf" ]; then
                        args[$i+1]="$tmp_conf"
                    fi
                    break
                fi
            done

            if command -v sudo &>/dev/null; then
                log_info "Elevating via sudo ..."
                exec sudo bash "$tmp" "${args[@]}"
            fi
            if command -v su &>/dev/null; then
                log_info "Elevating via su (sudo not found) ..."
                # 写包装脚本，避免 su -c 对命令字符串的解析问题
                local wrapper="/tmp/.su-wrapper.sh"
                {
                    echo '#!/bin/sh'
                    printf "exec bash '%s'" "$tmp"
                    for _arg in "${args[@]}"; do printf " '%s'" "$_arg"; done
                    echo
                } > "$wrapper"
                chmod +x "$wrapper"
                exec su -c "$wrapper" < /dev/tty
            fi
            log_error "Cannot elevate — install sudo or run as root"
            exit 1
        fi

        log_error "This script needs root privileges."
        if [ "$from_stdin" = true ]; then
            log_error "Use: curl -fsSL <URL> | sudo bash"
        else
            log_error "Run: sudo bash $0"
        fi
        exit 1
    fi
}

cleanup_exit() {
    local ec=$?
    if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
        rm -rf "$TMPDIR"
    fi
    if [ $ec -ne 0 ] && [ $ec -ne 130 ]; then
        echo
        log_error "Abnormal exit (code: ${ec}) — re-run to continue unfinished steps"
    fi
    exit $ec
}

run_retry() {
    local cmd=("$@") attempt=0 max_attempt=3 delay=3
    until "${cmd[@]}"; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge "$max_attempt" ]; then
            log_error "Command failed after ${max_attempt} attempts: ${cmd[*]}"
            return 1
        fi
        log_warn "Retry ${attempt}/${max_attempt} in ${delay}s ..."
        sleep "$delay"
    done
}

# 下载文件辅助函数：优先 curl，失败时退到 wget
download_file() {
    local url="$1" output="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output" 2>/dev/null && return 0
        log_dim "  curl failed, trying wget ..."
    fi
    if command -v wget &>/dev/null; then
        wget -qO "$output" "$url" 2>/dev/null && return 0
    fi
    log_error "Failed to download ${url}"
    return 1
}

# 交互式读输入：始终从终端读取（兼容管道模式 stdin 被占用的情况）
read_input() {
    local prompt="$1" var_name="${2:-REPLY}" val
    if [ -t 0 ]; then
        read -r -p "$prompt" val
    else
        read -r -p "$prompt" val </dev/tty
    fi
    printf -v "$var_name" "%s" "$val"
}

# ---------------------------------------------------------------------------
# Config file reader (for unattended deployment)
# ---------------------------------------------------------------------------

# Usage: create a file with key=value lines:
#
#   # APT mirror hostname (e.g., mirrors.aliyun.com, deb.debian.org)
#   APT_MIRROR=mirrors.aliyun.com
#
#   # npm registry URL
#   NPM_MIRROR=https://registry.npmmirror.com/
#
#   # Claude Code credentials (optional — prompts if omitted)
#   ANTHROPIC_API_KEY=sk-ant-...
#   ANTHROPIC_BASE_URL=https://api.anthropic.com
#   ANTHROPIC_MODEL=claude-sonnet-4-6-20250224
#
# Then run: sudo bash deploy_claude.sh --config myconfig.conf

read_config_file() {
    local file="$1"
    if [ ! -r "$file" ]; then
        log_error "Config file not readable: ${file}"
        exit 1
    fi
    log_info "Loading configuration from ${file} ..."
    source "$file"
    log_ok "Configuration loaded"
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

# Return the real user's home directory (Claude Code config must go to
# the non-root user, not /root/).  Tries, in order:
#   $SUDO_USER  — sudo(8) always sets this for the original caller
#   $LOGNAME    — login name from /var/log/wtmp (set by login(1))
#   logname(1)  — same source, works in containers
#   $HOME       — last resort (root in a truly root-only session)
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
        # /home/$USER is a safe guess even for custom setups — the
        # fallback after this is /root, which is always wrong for our use.
        echo "/home/${u}"
    else
        echo "$HOME"
    fi
}

detect_os() {
    log_step "Detecting operating system ..."

    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS (/etc/os-release missing)"
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_ID="${ID,,}"
    VERSION_ID="${VERSION_ID:-}"
    ARCH="$(uname -m)"

    case "$DISTRO_ID" in
        debian)
            CODENAME="$(grep -oP 'VERSION_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)"
            if [ -z "$CODENAME" ]; then
                local ver
                ver="$(head -1 /etc/debian_version 2>/dev/null | cut -d. -f1 || true)"
                case "$ver" in
                    11) CODENAME="bullseye" ;;
                    12) CODENAME="bookworm" ;;
                    13) CODENAME="trixie"  ;;
                    *)  CODENAME="" ;;
                esac
            fi
            ;;
        ubuntu)
            CODENAME="$(grep -oP 'VERSION_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)"
            ;;
        *)
            log_error "Unsupported distribution: ${DISTRO_ID} (only debian/ubuntu)"
            exit 1
            ;;
    esac

    if [ -z "$CODENAME" ]; then
        log_error "Could not detect version codename"
        exit 1
    fi

    log_ok "${NAME} ${VERSION_ID} (${CODENAME}) / ${ARCH}"
}

# ---------------------------------------------------------------------------
# Version guard
# ---------------------------------------------------------------------------

check_version() {
    local major
    major="$(echo "$VERSION_ID" | cut -d. -f1)"
    case "$DISTRO_ID" in
        debian)
            if [ "$major" -lt 11 ] 2>/dev/null; then
                log_warn "Debian ${VERSION_ID} is untested (minimum: 11)"
                confirm_yes "Continue?" "Y" || exit 0
            fi
            ;;
        ubuntu)
            if [ "$major" -lt 18 ] 2>/dev/null; then
                log_warn "Ubuntu ${VERSION_ID} is untested (minimum: 18.04)"
                confirm_yes "Continue?" "Y" || exit 0
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers for apt source construction
# ---------------------------------------------------------------------------

apt_components() {
    case "$DISTRO_ID" in
        debian)
            if [ "$(echo "$VERSION_ID" | cut -d. -f1)" -ge 12 ] 2>/dev/null; then
                echo "main contrib non-free non-free-firmware"
            else
                echo "main contrib non-free"
            fi
            ;;
        ubuntu) echo "main restricted universe multiverse" ;;
        *)      echo "main" ;;
    esac
}

security_suite() {
    case "$DISTRO_ID" in
        debian)
            if [ "$(echo "$VERSION_ID" | cut -d. -f1)" -lt 12 ] 2>/dev/null; then
                echo "${CODENAME}/updates"
            else
                echo "${CODENAME}-security"
            fi
            ;;
        ubuntu) echo "${CODENAME}-security" ;;
    esac
}

# ---------------------------------------------------------------------------
# APT mirror selection (interactive)
# ---------------------------------------------------------------------------

select_apt_mirror_interactive() {
    [ -n "$APT_MIRROR" ] && return 0  # already set via config

    local region items=() labels=() i

    if [ "$USE_CHINA" = true ]; then
        region="china"
    else
        echo
        echo "  Select region:"
        echo "    1) China mainland (accelerated mirrors)"
        echo "    2) Global (international mirrors)"
        echo "    0) Exit"
        local sel
        sel="$(pick_number 2)"
        case "$sel" in
            1) region="china" ;;
            2) region="global" ;;
            0) exit 0 ;;
            *) region="china" ;;
        esac
    fi

    if [ "$region" = "china" ]; then
        for item in "${MIRROR_LIST_CHINA[@]}"; do
            items+=("${item%%|*}")
            labels+=("${item##*|}")
        done
    else
        for item in "${MIRROR_LIST_GLOBAL[@]}"; do
            items+=("${item%%|*}")
            labels+=("${item##*|}")
        done
    fi

    echo
    echo "  Available APT mirrors:"
    for i in "${!labels[@]}"; do
        printf "    %2d) %-30s  (%s)\n" $((i + 1)) "${labels[$i]}" "${items[$i]}"
    done
    echo "    0) Exit"
    echo

    local pick
    pick="$(pick_number "${#items[@]}")"
    [ "$pick" -eq 0 ] && exit 0

    if [ "$pick" -ge 1 ] && [ "$pick" -le "${#items[@]}" ]; then
        APT_MIRROR="${items[$((pick - 1))]}"
        log_ok "APT mirror: ${labels[$((pick - 1))]} (${APT_MIRROR})"
    else
        log_error "Invalid option"
        select_apt_mirror_interactive
    fi
}

# ---------------------------------------------------------------------------
# Write apt sources (one-line format — /etc/apt/sources.list)
# ---------------------------------------------------------------------------

apply_apt_sources_list() {
    local mirror="$1" components="$2" sec_suite="$3" force_proto="${4:-}"
    local proto="http"

    if [ -n "$force_proto" ]; then
        proto="$force_proto"
    elif dpkg -s ca-certificates &>/dev/null 2>&1; then
        proto="https"
    fi

    # Backup to a location APT won't scan
    mkdir -p /etc/apt/backups
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "/etc/apt/backups/sources.list.$(date +%s)"
    fi
    # Remove deb822 files since we'll centralise everything
    rm -f /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/ubuntu.sources

    {
        echo "## Generated by deploy_claude.sh on $(date --rfc-3339=date)"
        echo "## Mirror: ${mirror}"
        echo "deb ${proto}://${mirror}/${DISTRO_ID} ${CODENAME} ${components}"
        echo "deb ${proto}://${mirror}/${DISTRO_ID} ${CODENAME}-updates ${components}"
        echo "deb ${proto}://${mirror}/${DISTRO_ID} ${CODENAME}-backports ${components}"
        echo "deb ${proto}://${mirror}/${DISTRO_ID} ${sec_suite} ${components}"
    } > /etc/apt/sources.list

    log_ok "APT sources written (one-line) <- ${mirror}"
}

# ---------------------------------------------------------------------------
# Write apt sources (deb822 format — /etc/apt/sources.list.d/*.sources)
# ---------------------------------------------------------------------------

apply_apt_sources_deb822() {
    local mirror="$1" components="$2" sec_suite="$3" force_proto="${4:-}"
    local proto="http" keyring=""
    local source_file=""
    local sec_source_file=""

    if [ -n "$force_proto" ]; then
        proto="$force_proto"
    elif dpkg -s ca-certificates &>/dev/null 2>&1; then
        proto="https"
    fi

    case "$DISTRO_ID" in
        debian)
            source_file="/etc/apt/sources.list.d/debian.sources"
            sec_source_file="/etc/apt/sources.list.d/debian-security.sources"
            keyring="/usr/share/keyrings/debian-archive-keyring.gpg"
            ;;
        ubuntu)
            source_file="/etc/apt/sources.list.d/ubuntu.sources"
            sec_source_file="/etc/apt/sources.list.d/ubuntu-security.sources"
            keyring="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
            ;;
    esac

    mkdir -p /etc/apt/backups /etc/apt/sources.list.d

    # Backup existing files
    for f in "$source_file" "$sec_source_file"; do
        [ -f "$f" ] && cp "$f" "/etc/apt/backups/$(basename "$f").$(date +%s)"
    done

    # Disable CD-ROM entry in sources.list (common on Debian installs)
    if [ -f /etc/apt/sources.list ]; then
        sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
    fi

    # Main suites (codename, updates, backports)
    cat > "$source_file" <<EOS
## Generated by deploy_claude.sh on $(date --rfc-3339=date)
## Mirror: ${mirror}
Types: deb
URIs: ${proto}://${mirror}/${DISTRO_ID}
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: ${components}
Signed-By: ${keyring}
EOS

    # Security suite (separate file so it can be independently removed)
    cat > "$sec_source_file" <<EOS
## Generated by deploy_claude.sh on $(date --rfc-3339=date)
## Mirror: ${mirror}
Types: deb
URIs: ${proto}://${mirror}/${DISTRO_ID}
Suites: ${sec_suite}
Components: ${components}
Signed-By: ${keyring}
EOS

    log_ok "APT sources written (deb822) <- ${mirror}"
}

# ---------------------------------------------------------------------------
# Apply the selected APT mirror
# ---------------------------------------------------------------------------

apply_apt_mirror() {
    local mirror="$1"
    local components sec_suite
    components="$(apt_components)"

    # Clean up leftover backup files that confuse APT
    rm -f /etc/apt/sources.list.d/*.bak.* /etc/apt/sources.list.bak.* 2>/dev/null || true
    sec_suite="$(security_suite)"

    local major
    major="$(echo "$VERSION_ID" | cut -d. -f1)"

    local use_deb822=false
    case "$DISTRO_ID" in
        debian)
            [ "$major" -ge 12 ] 2>/dev/null && use_deb822=true
            ;;
        ubuntu)
            [ "$major" -ge 24 ] 2>/dev/null && use_deb822=true
            ;;
    esac

    if [ "$use_deb822" = true ]; then
        apply_apt_sources_deb822 "$mirror" "$components" "$sec_suite"
    else
        apply_apt_sources_list "$mirror" "$components" "$sec_suite"
    fi

    log_info "Updating package index ..."
    if apt-get update -qq 2>/dev/null; then
        log_ok "Package index updated"
        return 0
    fi

    # Retry 1: security suite might not exist at mirror (common for new releases)
    if [ "$use_deb822" = true ]; then
        log_warn "Security suite not found — retrying without it ..."
        rm -f /etc/apt/sources.list.d/debian-security.sources /etc/apt/sources.list.d/ubuntu-security.sources
        if apt-get update -qq 2>/dev/null; then
            log_ok "Package index updated (skipping security suite)"
            log_warn "Security updates not available from this mirror"
            return 0
        fi
    fi

    # Retry 2: try http in case https is blocked or mirror incomplete
    log_warn "apt update failed — retrying with http ..."
    if [ "$use_deb822" = true ]; then
        apply_apt_sources_deb822 "$mirror" "$components" "$sec_suite" "http"
        rm -f /etc/apt/sources.list.d/debian-security.sources /etc/apt/sources.list.d/ubuntu-security.sources
    else
        apply_apt_sources_list "$mirror" "$components" "$sec_suite" "http"
    fi
    if apt-get update -qq 2>/dev/null; then
        log_ok "Package index updated (http)"
        return 0
    fi

    # Retry 3: backports might not exist on this mirror
    log_warn "Backports not found — retrying without backports ..."
    if [ "$use_deb822" = true ]; then
        local sf; case "$DISTRO_ID" in
            debian) sf="/etc/apt/sources.list.d/debian.sources" ;;
            ubuntu) sf="/etc/apt/sources.list.d/ubuntu.sources" ;;
        esac
        [ -f "$sf" ] && sed -i '/Suites:/{s/ [^ ]*-backports[^ ]*//;s/  */ /g;s/ $//}' "$sf"
    else
        sed -i '/-backports/d' /etc/apt/sources.list
    fi
    if apt-get update -qq 2>/dev/null; then
        log_ok "Package index updated (without backports)"
        return 0
    fi

    # Retry 4: security suite might not exist on this mirror
    log_warn "Security suite not found — retrying without it ..."
    if [ "$use_deb822" = false ]; then
        sed -i "\|${sec_suite}|d" /etc/apt/sources.list
    fi
    apt-get update -qq 2>/dev/null || {
        log_error "apt update failed; check network connectivity"
        return 1
    }
    log_warn "Security updates not available from this mirror"
    return 0
}

# ---------------------------------------------------------------------------
# npm mirror selection (interactive)
# ---------------------------------------------------------------------------

select_npm_mirror_interactive() {
    [ -n "$NPM_MIRROR" ] && return 0  # already set via config

    local i
    echo
    echo "  Available npm mirrors:"
    for i in "${!NPM_MIRROR_LIST[@]}"; do
        local name="${NPM_MIRROR_LIST[$i]##*|}"
        local url="${NPM_MIRROR_LIST[$i]%%|*}"
        printf "    %2d) %s\n" $((i + 1)) "${name}"
        log_dim "       ${url}"
    done
    echo "    0) Exit"
    echo

    local pick
    pick="$(pick_number "${#NPM_MIRROR_LIST[@]}")"
    [ "$pick" -eq 0 ] && exit 0

    if [ "$pick" -ge 1 ] && [ "$pick" -le "${#NPM_MIRROR_LIST[@]}" ]; then
        NPM_MIRROR="${NPM_MIRROR_LIST[$((pick - 1))]%%|*}"
        local name="${NPM_MIRROR_LIST[$((pick - 1))]##*|}"
        log_ok "npm mirror: ${name}"
    else
        log_error "Invalid option"
        select_npm_mirror_interactive
    fi
}

# ---------------------------------------------------------------------------
# Install system dependencies via apt
# ---------------------------------------------------------------------------

install_system_deps() {
    log_step "Installing system dependencies ..."

    # Clean up leftover apt backup files from previous runs
    rm -f /etc/apt/sources.list.d/*.bak.* /etc/apt/sources.list.bak.* 2>/dev/null || true

    # Refresh package index on fresh installs
    if [ ! -f /var/lib/apt/lists/lock ] && [ ! -d /var/lib/apt/lists/partial ]; then
        log_info "Updating package index (first run) ..."
        apt-get update -qq 2>/dev/null || log_warn "apt update failed — will retry later"
    fi

    local pkgs=(curl wget ca-certificates git)

    local install_list=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
            install_list+=("$pkg")
        fi
    done

    if [ ${#install_list[@]} -eq 0 ]; then
        log_ok "All system dependencies already present"
        return 0
    fi

    log_info "Installing: ${install_list[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${install_list[@]}" 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${install_list[@]}"

    log_ok "System dependencies installed"
}

# ---------------------------------------------------------------------------
# Select appropriate Node.js major version per distro
# ---------------------------------------------------------------------------

select_nodejs_major() {
    case "$DISTRO_ID" in
        debian)
            case "$(echo "$VERSION_ID" | cut -d. -f1)" in
                11) echo "20"  ;;   # NodeSource drops 22.x for bullseye
                *)  echo "22"  ;;
            esac
            ;;
        ubuntu)
            case "$(echo "$VERSION_ID" | cut -d. -f1)" in
                18|20) echo "20"  ;;  # NodeSource drops 22.x for bionic/focal
                *)     echo "22"  ;;
            esac
            ;;
        *) echo "22" ;;
    esac
}

# ---------------------------------------------------------------------------
# Install Node.js (NodeSource -> binary tarball fallback)
# ---------------------------------------------------------------------------

install_nodejs() {
    log_step "Installing Node.js ..."

    local node_major
    node_major="$(select_nodejs_major)"
    log_info "Target version: Node.js ${node_major}.x"

    # Check existing Node
    local current_ver="" current_major=0
    if command -v node &>/dev/null; then
        current_ver="$(node --version 2>/dev/null || true)"
        current_major="$(echo "$current_ver" | sed 's/v//' | cut -d. -f1)"
        if [ "$current_major" -ge 18 ] 2>/dev/null; then
            log_ok "Node.js ${current_ver} already installed, skipping"
            return 0
        fi
        log_warn "Node.js ${current_ver} is too old (need 18+), upgrading"
    fi

    # ---- Method 1: NodeSource (convenient, integrates with apt) ----
    if command -v curl &>/dev/null; then
        local ns_url="https://deb.nodesource.com/setup_${node_major}.x"
        log_info "Trying NodeSource ${node_major}.x ..."
        if curl -fL --connect-timeout 10 --max-time 60 --progress-bar \
            "$ns_url" | bash -; then

            log_info "Updating apt cache ..."
            apt-get update -qq 2>/dev/null || true

            log_info "Installing Node.js ${node_major}.x via apt ..."
            # apt may install the distro default version (too old)
            # on systems where NodeSource doesn't provide ${node_major}.x.
            # The version check below catches that and falls back to binary tarball.

            if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs 2>/dev/null || \
               DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs; then
                # Verify installed version meets requirements
                local installed
                installed="$(node --version 2>/dev/null || echo "unknown")"
                local installed_major
                installed_major="$(echo "$installed" | sed 's/v//' | cut -d. -f1)"
                if [ "$installed_major" -ge 18 ] 2>/dev/null; then
                    log_ok "Node.js ${installed} installed (NodeSource)"
                    # Activate bundled npm if needed
                    if ! command -v npm &>/dev/null; then
                        log_info "Activating bundled npm via corepack ..."
                        corepack enable npm 2>/dev/null || true
                        if ! command -v npm &>/dev/null && [ -f /usr/lib/node_modules/npm/bin/npm-cli.js ]; then
                            ln -sf /usr/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
                        fi
                        if ! command -v npm &>/dev/null; then
                            log_warn "npm not bundled, installing via apt ..."
                            apt-get install -y -qq npm 2>/dev/null || apt-get install -y npm || true
                        fi
                    fi
                    if command -v npm &>/dev/null; then
                        log_dim "  npm $(npm --version)"
                    fi
                    return 0
                fi
                log_warn "Node.js ${installed} too old — trying binary fallback"
            else
                log_warn "apt install failed — trying binary fallback"
            fi
        else
            log_warn "NodeSource setup failed — trying binary fallback"
        fi
    fi

    # ---- Method 2: Binary tarball (works everywhere) ----
    install_nodejs_binary "$node_major" || {
        log_error "Node.js installation failed"
        return 1
    }

    if ! command -v npm &>/dev/null; then
        log_info "Activating bundled npm ..."
        corepack enable npm 2>/dev/null || true
        if ! command -v npm &>/dev/null && [ -f /usr/local/lib/node_modules/npm/bin/npm-cli.js ]; then
            ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
        fi
    fi
    if command -v npm &>/dev/null; then
        log_dim "  npm $(npm --version)"
    fi
}

# ---------------------------------------------------------------------------
# Install Node.js from official binary tarball (universal fallback)
# ---------------------------------------------------------------------------

install_nodejs_binary() {
    local major="$1"
    local arch="$ARCH"
    case "$arch" in
        x86_64)  arch="x64"   ;;
        aarch64) arch="arm64" ;;
        *)
            log_error "Architecture ${ARCH} not supported for binary install"
            return 1
            ;;
    esac

    local base_url="https://nodejs.org/dist"
    case "${NPM_MIRROR:-}" in
        *npmmirror*) base_url="https://mirrors.npmmirror.com/nodejs" ;;
    esac

    local version=""
    local ver_list
    ver_list="$(curl -fsL --connect-timeout 10 --max-time 30 "${base_url}/index.json" 2>/dev/null || true)"
    if [ -n "$ver_list" ]; then
        version="$(echo "$ver_list" | grep -oP "\"v${major}\.[0-9]+\.[0-9]+\"" | tr -d '"' | sort -V | tail -1 || true)"
    fi

    if [ -z "$version" ]; then
        log_warn "Version discovery failed, trying known ${major}.x releases ..."
        local fallback_vers=""
        case "$major" in
            22) fallback_vers="22.14.0 22.13.1 22.12.0" ;;
            20) fallback_vers="20.18.0 20.17.0" ;;
            *)  log_error "Cannot determine latest Node.js ${major}.x version"; return 1 ;;
        esac
        for try_ver in $fallback_vers; do
            local test_url="${base_url}/v${try_ver}/node-v${try_ver}-linux-${arch}.tar.gz"
            if curl -sfL --connect-timeout 5 --max-time 15 -o /dev/null "${test_url}" 2>/dev/null; then
                version="v${try_ver}"
                log_dim "  Found ${version}"
                break
            fi
        done
    fi

    # Retry with npmmirror China mirror if primary failed
    if [ -z "$version" ] && [ "$base_url" = "https://nodejs.org/dist" ]; then
        log_warn "Primary mirror unreachable, trying npmmirror China mirror ..."
        base_url="https://mirrors.npmmirror.com/nodejs"
        ver_list="$(curl -fsL --connect-timeout 10 --max-time 30 "${base_url}/index.json" 2>/dev/null || true)"
        if [ -n "$ver_list" ]; then
            version="$(echo "$ver_list" | grep -oP "\"v${major}\.[0-9]+\.[0-9]+\"" | tr -d '"' | sort -V | tail -1 || true)"
        fi
        if [ -z "$version" ] && [ -n "${fallback_vers:-}" ]; then
            for try_ver in $fallback_vers; do
                try_url="${base_url}/v${try_ver}/node-v${try_ver}-linux-${arch}.tar.gz"
                if curl -sfL --connect-timeout 5 --max-time 15 -o /dev/null "${try_url}" 2>/dev/null; then
                    version="v${try_ver}"
                    log_dim "  Found ${version} (China mirror)"
                    break
                fi
            done
        fi
    fi

    if [ -z "$version" ]; then
        log_error "Cannot determine latest Node.js ${major}.x version (network issue?)"
        return 1
    fi

    local filename="node-${version}-linux-${arch}.tar.gz"
    local download_url="${base_url}/${version}/${filename}"

    log_info "Downloading Node.js ${version} (binary tarball) ..."
    if ! curl -fL --connect-timeout 10 --max-time 180 --progress-bar \
        "$download_url" -o "/tmp/${filename}" 2>/dev/null; then
        if [ "$base_url" = "https://nodejs.org/dist" ]; then
            local alt_dl_url="https://mirrors.npmmirror.com/nodejs/${version}/${filename}"
            log_warn "Download from nodejs.org failed, trying China mirror ..."
            curl -fL --connect-timeout 10 --max-time 180 --progress-bar \
                "$alt_dl_url" -o "/tmp/${filename}" || {
                log_error "Download failed, check network connectivity"
                return 1
            }
        else
            log_error "Download failed, check network connectivity"
            return 1
        fi
    fi

    log_info "Extracting to /usr/local/ ..."
    tar -xzf "/tmp/${filename}" -C /usr/local/ --strip-components=1 --no-same-owner
    rm -f "/tmp/${filename}"

    local installed
    installed="$(node --version 2>/dev/null || echo "unknown")"
    log_ok "Node.js ${installed} installed (binary tarball)"

    if command -v npm &>/dev/null; then
        log_dim "  npm $(npm --version)"
    fi
}

# ---------------------------------------------------------------------------
# Apply npm mirror setting
# ---------------------------------------------------------------------------

configure_npm_mirror() {
    [ -z "$NPM_MIRROR" ] && return 0

    log_step "Applying npm mirror ..."

    if ! command -v npm &>/dev/null; then
        log_warn "npm not available, skipping"
        return 0
    fi

    # Use temp dir for npm cache when running as root
    local npm_cache="/tmp/.npm-cache"
    mkdir -p "$npm_cache"
    npm config set cache "$npm_cache" 2>/dev/null || true

    # Read .npmrc directly to avoid slow first-run npm init
    local rcfile="${HOME}/.npmrc"
    local current=""
    if [ -f "$rcfile" ] && grep -q "^registry=" "$rcfile" 2>/dev/null; then
        current="$(grep "^registry=" "$rcfile" | head -1 | cut -d= -f2-)"
    fi
    if [ "$current" = "$NPM_MIRROR" ]; then
        log_ok "npm registry already set to ${NPM_MIRROR}"
        return 0
    fi

    # Write directly — avoids spawning npm just for config
    if grep -q "^registry=" "$rcfile" 2>/dev/null; then
        sed -i "s|^registry=.*|registry=${NPM_MIRROR}|" "$rcfile"
    else
        echo "registry=${NPM_MIRROR}" >> "$rcfile"
    fi

    # Also set for the non-root user if running under sudo
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        local home_dir
        home_dir="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "/home/${SUDO_USER}")"
        local user_rcfile="${home_dir}/.npmrc"
        if [ -d "$home_dir" ]; then
            if grep -q "^registry=" "$user_rcfile" 2>/dev/null; then
                sed -i "s|^registry=.*|registry=${NPM_MIRROR}|" "$user_rcfile"
            else
                echo "registry=${NPM_MIRROR}" >> "$user_rcfile"
            fi
            chown "${SUDO_USER}:${SUDO_USER}" "$user_rcfile" 2>/dev/null || true
        fi
    fi

    log_ok "npm registry set to ${NPM_MIRROR}"
}

# ---------------------------------------------------------------------------
# Install Claude Code CLI
# ---------------------------------------------------------------------------

install_claude_code() {
    log_step "Installing Claude Code CLI ..."

    if ! command -v node &>/dev/null; then
        log_error "Node.js is required but not found"
        return 1
    fi

    local major
    major="$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)"
    if [ "$major" -lt 18 ] 2>/dev/null; then
        log_error "Node.js version too old ($(node --version)), need 18+"
        return 1
    fi

    if command -v claude &>/dev/null; then
        local ver
        ver="$(claude --version 2>/dev/null || echo "installed")"
        if confirm_yes "Claude Code CLI (${ver}) already present, reinstall?" "N"; then
            npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
        else
            log_ok "Claude Code CLI already installed, skipping"
            return 0
        fi
    fi

    log_info "Installing @anthropic-ai/claude-code globally ..."
    log_info "  This downloads ~15MB from npm registry, may take a minute ..."

    # Avoid writing npm cache to /root/.npm/ when running under sudo
    local npm_cache="/tmp/.npm-cache"
    mkdir -p "$npm_cache"

    run_retry npm install --cache "$npm_cache" -g @anthropic-ai/claude-code || {
        log_error "npm install failed"
        log_error "Check network connectivity and npm registry: $(npm config get registry)"
        log_error "Retry manually: npm install -g @anthropic-ai/claude-code"
        return 1
    }

    if command -v claude &>/dev/null; then
        local ver
        ver="$(claude --version 2>/dev/null || echo "")"
        log_ok "Claude Code CLI ${ver} installed"
    else
        log_warn "claude not in PATH — creating symlink"
        local prefix
        prefix="$(npm config get prefix 2>/dev/null || echo "/usr/local")"
        if [ -f "${prefix}/lib/node_modules/@anthropic-ai/claude-code/cli.js" ]; then
            ln -sf "${prefix}/lib/node_modules/@anthropic-ai/claude-code/cli.js" /usr/local/bin/claude
            chmod +x /usr/local/bin/claude
            log_ok "Symlink created"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Claude Code post-install configuration
# ---------------------------------------------------------------------------

configure_claude_code() {
    log_step "Configuring Claude Code ..."

    if ! command -v claude &>/dev/null; then
        log_warn "claude command unavailable, skipping config"
        return 0
    fi

    local real_user="${SUDO_USER:-$(logname 2>/dev/null || echo "root")}"
    local claude_dir; claude_dir="$(user_home)/.claude"
    mkdir -p "$claude_dir"

    # ---------- Prompt for credentials ----------
    local api_key="${ANTHROPIC_API_KEY:-}"
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local model_name="${ANTHROPIC_MODEL:-}"

    # Read existing settings.json if env vars not set
    if [ -f "${claude_dir}/settings.json" ]; then
        [ -z "$api_key" ]  && api_key="$(grep -oP '"ANTHROPIC_API_KEY"\s*:\s*"\K[^"]+' "${claude_dir}/settings.json" 2>/dev/null || true)"
        [ -z "$base_url" ] && base_url="$(grep -oP '"ANTHROPIC_BASE_URL"\s*:\s*"\K[^"]+' "${claude_dir}/settings.json" 2>/dev/null || true)"
        [ -z "$model_name" ] && model_name="$(grep -oP '"model"\s*:\s*"\K[^"]+' "${claude_dir}/settings.json" 2>/dev/null || true)"
    fi
    # Also check .env for existing values (backward compat)
    if [ -f "${claude_dir}/.env" ]; then
        [ -z "$api_key" ]  && api_key="$(grep "^ANTHROPIC_API_KEY=" "${claude_dir}/.env" | tail -1 | cut -d= -f2- || true)"
        [ -z "$base_url" ] && base_url="$(grep "^ANTHROPIC_BASE_URL=" "${claude_dir}/.env" | tail -1 | cut -d= -f2- || true)"
    fi

    # Key
    if [ -z "$api_key" ]; then
        echo
        echo "  API Key: (get one at https://console.anthropic.com/)"
        if confirm_yes "  Enter API Key?" "Y"; then
            read_input "  Key: " api_key
        fi
    fi

    # URL
    if [ -z "$base_url" ]; then
        echo
        echo "  API Base URL (enter to use https://api.anthropic.com):"
        echo "    Examples:"
        echo "      https://api.anthropic.com           (official)"
        echo "      https://your-proxy.com/anthropic     (custom gateway)"
        read_input "  URL: " base_url
        [ -z "$base_url" ] && base_url="https://api.anthropic.com"
    fi

    # Model
    if [ -z "$model_name" ]; then
        echo
        echo "  Select default model:"
        echo "    1) claude-sonnet-4-6-20250224  (Anthropic, recommended)"
        echo "    2) claude-opus-4-6-20250224    (Anthropic, most capable)"
        echo "    3) claude-haiku-4-5-20251001   (Anthropic, fastest)"
        echo "    4) deepseek-v4-flash           (DeepSeek, fast/cheap)"
        echo "    5) deepseek-v4-pro             (DeepSeek, powerful)"
        echo "    6) Enter custom model name"
        echo "    0) Skip (use claude default)"
        local mpick
        mpick="$(pick_number 6)"
        case "$mpick" in
            1) model_name="claude-sonnet-4-6-20250224" ;;
            2) model_name="claude-opus-4-6-20250224" ;;
            3) model_name="claude-haiku-4-5-20251001" ;;
            4) model_name="deepseek-v4-flash" ;;
            5) model_name="deepseek-v4-pro" ;;
            6) read_input "  Model name: " model_name ;;
            *) model_name="" ;;
        esac
    fi

    # ---------- Write .env (backward compat fallback) ----------
    cat > "${claude_dir}/.env" << EOF
ANTHROPIC_AUTH_TOKEN=${api_key}
ANTHROPIC_API_KEY=${api_key}
ANTHROPIC_BASE_URL=${base_url}
EOF
    chmod 600 "${claude_dir}/.env"

    # ---------- Write settings.json (primary config) ----------
    cat > "${claude_dir}/settings.json" << EOF
{
    "env": {
        "ANTHROPIC_AUTH_TOKEN": "${api_key}",
        "ANTHROPIC_BASE_URL": "${base_url}",
        "ANTHROPIC_MODEL": "${model_name:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${model_name:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "${model_name:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "${model_name:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_REASONING_MODEL": "${model_name:-claude-sonnet-4-6-20250224}"
    }
}
EOF
    log_ok "Config written → ${claude_dir}/settings.json"
    log_dim "  .env (backup) → ${claude_dir}/.env"

    # Own by the real user
    [ "$real_user" != "root" ] && chown -R "${real_user}:${real_user}" "$claude_dir" 2>/dev/null || true

    # ---------- Verify connectivity ----------
    echo
    log_info "Verifying API endpoint: ${base_url} ..."
    local http_code
    http_code="$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 8 --max-time 10 \
        -H "x-api-key: ${api_key}" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        "${base_url}/v1/messages" \
        -d '{"model":"claude-sonnet-4-6-20250224","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        2>/dev/null || echo "FAIL")"

    case "$http_code" in
        400)
            log_warn "API returned 400 (expected if key is read-only or new)"
            log_ok "Network connectivity OK"
            ;;
        401|403)
            log_ok "API reachable (${http_code}) — key will be validated on first run"
            ;;
        200|201|202)
            log_ok "API reachable and responding"
            ;;
        "FAIL")
            log_warn "Cannot reach ${base_url}"
            log_warn "  Check: firewall, DNS, proxy settings"
            log_warn "  If in China, you may need a proxy or custom ANTHROPIC_BASE_URL"
            ;;
        *)
            log_dim "  HTTP ${http_code} (unexpected, but connectivity exists)"
            ;;
    esac

    echo
    log_ok "Claude Code configuration complete"
    log_dim "  Config: ${claude_dir}/settings.json"
    log_dim "  Start:  claude"
}

# ---------------------------------------------------------------------------
# Reconfigure Claude Code (standalone — API key / Base URL / model)
# ---------------------------------------------------------------------------

reconfigure_claude() {
    local claude_dir; claude_dir="$(user_home)/.claude"
    mkdir -p "$claude_dir"

    local env_file="${claude_dir}/.env"
    local settings_file="${claude_dir}/settings.json"

    # Show path
    echo
    log_dim "  Config dir: ${claude_dir}"

    # Warn about project-level override
    if [ -f "$(pwd)/.claude/settings.json" ] 2>/dev/null; then
        log_warn "Project-level .claude/settings.json detected: $(pwd)/.claude/"
        log_warn "  This OVERRIDES ~/.claude/settings.json when claude runs from this directory."
    fi

    # --- Read current values from settings.json ---
    local curr_key="" curr_url="" curr_model=""
    if [ -f "$settings_file" ]; then
        curr_key="$(grep -oP '"ANTHROPIC_AUTH_TOKEN"\s*:\s*"\K[^"]+' "$settings_file" 2>/dev/null || true)"
        curr_url="$(grep -oP '"ANTHROPIC_BASE_URL"\s*:\s*"\K[^"]+' "$settings_file" 2>/dev/null || true)"
        curr_model="$(grep -oP '"ANTHROPIC_MODEL"\s*:\s*"\K[^"]+' "$settings_file" 2>/dev/null || true)"
    fi
    # Fallback: read from .env
    if [ -z "$curr_key" ] && [ -f "$env_file" ]; then
        curr_key="$(grep "^ANTHROPIC_AUTH_TOKEN=" "$env_file" | tail -1 | cut -d= -f2- || true)"
        [ -z "$curr_key" ] && curr_key="$(grep "^ANTHROPIC_API_KEY=" "$env_file" | tail -1 | cut -d= -f2- || true)"
        curr_url="$(grep "^ANTHROPIC_BASE_URL=" "$env_file" | tail -1 | cut -d= -f2- || true)"
    fi

    clear_screen
    echo "============================================"
    echo "  Claude Code — Reconfigure"
    echo "============================================"
    echo
    echo "  Current settings:"
    echo "    API Key:    ${curr_key:+${curr_key:0:8}...}${curr_key:-not set}"
    echo "    Base URL:   ${curr_url:-not set (→ api.anthropic.com)}"
    echo "    Model:      ${curr_model:-not set (→ claude default)}"
    echo
    echo "  1) Change API Key"
    echo "  2) Change Base URL"
    echo "  3) Change model"
    echo "  4) All of the above"
    echo "  0) Exit"
    echo

    local pick
    pick="$(pick_number 4)"

    case "$pick" in
        1|2|3|4) ;;
        0) return 0 ;;
        *) reconfigure_claude; return 0 ;;
    esac

    # --- API Key ---
    if [ "$pick" -eq 1 ] || [ "$pick" -eq 4 ]; then
        echo
        read_input "  API Key (enter to keep current): " new_key
        [ -n "$new_key" ] && curr_key="$new_key"
    fi

    # --- Base URL ---
    if [ "$pick" -eq 2 ] || [ "$pick" -eq 4 ]; then
        echo
        echo "  Base URL (enter to keep current):"
        read_input "  [${curr_url:-https://api.anthropic.com}]: " new_url
        [ -n "$new_url" ] && curr_url="$new_url"
    fi

    # --- Model ---
    if [ "$pick" -eq 3 ] || [ "$pick" -eq 4 ]; then
        echo
        echo "  Select model:"
        echo "    1) claude-sonnet-4-6-20250224  (Anthropic, recommended)"
        echo "    2) claude-opus-4-6-20250224    (Anthropic, most capable)"
        echo "    3) claude-haiku-4-5-20251001   (Anthropic, fastest)"
        echo "    4) deepseek-v4-flash           (DeepSeek, fast/cheap)"
        echo "    5) deepseek-v4-pro             (DeepSeek, powerful)"
        echo "    6) Enter custom model name"
        echo "    0) Keep current (${curr_model:-default})"
        local mpick
        mpick="$(pick_number 6)"
        case "$mpick" in
            1) curr_model="claude-sonnet-4-6-20250224" ;;
            2) curr_model="claude-opus-4-6-20250224" ;;
            3) curr_model="claude-haiku-4-5-20251001" ;;
            4) curr_model="deepseek-v4-flash" ;;
            5) curr_model="deepseek-v4-pro" ;;
            6) read_input "  Model name: " curr_model ;;
            0) ;;  # keep current
        esac
    fi

    # --- Write .env (backward compat fallback) ---
    {
        [ -n "$curr_key" ] && echo "ANTHROPIC_AUTH_TOKEN=${curr_key}"
        [ -n "$curr_key" ] && echo "ANTHROPIC_API_KEY=${curr_key}"
        [ -n "$curr_url" ] && echo "ANTHROPIC_BASE_URL=${curr_url}"
    } > "$env_file"
    chmod 600 "$env_file"

    # --- Write settings.json (primary config) ---
    cat > "$settings_file" <<EOF
{
    "env": {
        "ANTHROPIC_AUTH_TOKEN": "${curr_key}",
        "ANTHROPIC_BASE_URL": "${curr_url}",
        "ANTHROPIC_MODEL": "${curr_model:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${curr_model:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "${curr_model:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "${curr_model:-claude-sonnet-4-6-20250224}",
        "ANTHROPIC_REASONING_MODEL": "${curr_model:-claude-sonnet-4-6-20250224}"
    }
}
EOF

    # Own by the real user
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "$claude_dir" 2>/dev/null || true
    fi

    echo
    log_ok "Claude Code configuration updated"
    log_dim "  Config dir: ${claude_dir}"
    log_dim "  To verify, run: claude --version"
}

# ---------------------------------------------------------------------------
# Print deployment summary
# ---------------------------------------------------------------------------

print_summary() {
    echo
    echo "============================================"
    echo "        Deployment Complete"
    echo "============================================"
    echo
    echo "  System:  ${NAME:-} ${VERSION_ID} (${CODENAME}) / ${ARCH}"
    echo
    command -v node   &>/dev/null && echo "  Node.js: $(node --version)"   || true
    command -v npm    &>/dev/null && echo "  npm:     $(npm --version)"    || true
    command -v claude &>/dev/null && echo "  Claude:  $(claude --version 2>/dev/null || echo 'installed')" || true
    echo
    [ -n "$APT_MIRROR" ] && echo "  APT mirror:  ${APT_MIRROR}"
    [ -n "$NPM_MIRROR" ] && echo "  npm mirror:  ${NPM_MIRROR}"
    local env_dir; env_dir="$(user_home)/.claude"
    echo "  Claude config: ${env_dir}"
    if [ -f "${env_dir}/settings.json" ]; then
        echo "  Model:    $(grep -oP '"ANTHROPIC_MODEL"\s*:\s*"\K[^"]+' "${env_dir}/settings.json" 2>/dev/null || echo 'default')"
        echo "  API URL:  $(grep -oP '"ANTHROPIC_BASE_URL"\s*:\s*"\K[^"]+' "${env_dir}/settings.json" 2>/dev/null || echo 'https://api.anthropic.com')"
        grep -q "ANTHROPIC_AUTH_TOKEN" "${env_dir}/settings.json" 2>/dev/null && \
            echo "  API key:  configured"
    fi
    echo
    echo "  Next step: run  claude"
    echo
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

clear_screen() { clear || true; }

show_menu() {
    clear_screen
    cat << EOF
============================================
 Claude Code CLI — Bootstrap Installer
 Debian / Ubuntu
============================================

  System: ${NAME:-} ${VERSION_ID} (${CODENAME}) ${ARCH}

  Choose deployment mode:

    ${BD}1${RS})  Quick full deploy (recommended)
         Auto-detect, choose mirrors, install everything

    ${BD}2${RS})  Step-by-step custom deploy
         Pick which steps to run

    ${BD}3${RS})  APT mirror only
    ${BD}4${RS})  npm mirror only
    ${BD}5${RS})  Node.js only (via NodeSource)
    ${BD}6${RS})  Claude Code CLI only
    ${BD}7${RS})  Reconfigure Claude Code (API key / Base URL / model)

    ${BD}0${RS})  Exit

EOF
}

handle_menu() {
    local choice
    choice="$(pick_number 7)"
    case "$choice" in
        1) run_full_deploy  ;;
        2) run_custom_deploy ;;
        3) run_apt_only     ;;
        4) run_npm_only     ;;
        5) run_node_only    ;;
        6) run_claude_only  ;;
        7) reconfigure_claude ;;
        0) exit 0           ;;
        *) show_menu; handle_menu ;;
    esac
}

# ---------------------------------------------------------------------------
# Deployment mode implementations
# ---------------------------------------------------------------------------

run_full_deploy() {
    # Auto-detect China region
    if curl -sL --connect-timeout 2 "https://mirrors.aliyun.com" >/dev/null 2>&1; then
        USE_CHINA=true
    fi

    select_apt_mirror_interactive
    select_npm_mirror_interactive

    echo
    install_system_deps
    echo
    apply_apt_mirror "$APT_MIRROR"
    echo
    install_nodejs
    echo
    configure_npm_mirror
    echo
    install_claude_code
    echo
    configure_claude_code
    print_summary
}

run_custom_deploy() {
    declare -A step_labels=(
        [1]="APT mirror"
        [2]="npm mirror"
        [3]="System dependencies (curl/git/unzip)"
        [4]="Node.js via NodeSource"
        [5]="Claude Code CLI"
    )

    local steps=()
    for i in 1 2 3 4 5; do
        if confirm_yes "Run: ${step_labels[$i]}?" "Y"; then
            steps+=("$i")
        fi
    done

    if [ ${#steps[@]} -eq 0 ]; then
        log_info "No steps selected, exiting"
        exit 0
    fi

    echo
    log_info "Executing:"
    for s in "${steps[@]}"; do log_dim "  - ${step_labels[$s]}"; done
    sleep 1

    for s in "${steps[@]}"; do
        case "$s" in
            1)
                select_apt_mirror_interactive
                apply_apt_mirror "$APT_MIRROR"
                echo
                ;;
            2)
                select_npm_mirror_interactive
                echo
                ;;
            3)
                install_system_deps
                echo
                ;;
            4)
                install_nodejs
                echo
                ;;
            5)
                [ -n "$NPM_MIRROR" ] && configure_npm_mirror
                install_claude_code
                configure_claude_code
                echo
                ;;
        esac
    done

    print_summary
}

run_apt_only() {
    select_apt_mirror_interactive
    apply_apt_mirror "$APT_MIRROR"
    log_ok "APT mirror configured"
}

run_npm_only() {
    select_npm_mirror_interactive
    configure_npm_mirror
    log_ok "npm mirror configured"
}

run_node_only() {
    install_system_deps
    install_nodejs
    log_ok "Node.js installation complete"
}

run_claude_only() {
    if ! command -v node &>/dev/null; then
        log_error "Node.js is required — please install it first (option 5)"
        exit 1
    fi
    install_claude_code
    configure_claude_code
    log_ok "Claude Code CLI installation complete"
}

# ---------------------------------------------------------------------------
# Quick (non-interactive) mode
# ---------------------------------------------------------------------------

run_quick_mode() {
    log_info "Quick mode — auto-detecting best configuration ..."

    if curl -sL --connect-timeout 2 "https://mirrors.aliyun.com" >/dev/null 2>&1; then
        USE_CHINA=true
    fi

    if [ "$USE_CHINA" = true ]; then
        APT_MIRROR="mirrors.aliyun.com"
        NPM_MIRROR="https://registry.npmmirror.com/"
    else
        case "$DISTRO_ID" in
            debian) APT_MIRROR="deb.debian.org" ;;
            ubuntu) APT_MIRROR="archive.ubuntu.com" ;;
        esac
        NPM_MIRROR="https://registry.npmjs.org/"
    fi

    log_ok "APT mirror: ${APT_MIRROR}"
    log_ok "npm mirror: ${NPM_MIRROR}"

    install_system_deps
    apply_apt_mirror "$APT_MIRROR"
    install_nodejs
    configure_npm_mirror
    install_claude_code
    configure_claude_code
    print_summary
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
    trap cleanup_exit EXIT INT TERM

    local quick_mode=false
    local config_file=""
    local orig_args=("$@")

    while [ $# -gt 0 ]; do
        case "$1" in
            --quick|-q)    quick_mode=true; shift ;;
            --china|-c)    USE_CHINA=true;  shift ;;
            --config)      config_file="$2"; shift 2 ;;
            --install|-i)
                shift
                local target="/usr/local/bin/deploy_claude.sh"
                if [ -f "$0" ]; then
                    cp "$0" "$target"
                    chmod +x "$target"
                    echo "Installed to ${target}"
                    echo "Run: sudo ${target}"
                else
                    echo "Cannot install — script is running from pipe."
                    echo "Save manually: curl -fsSL <URL> -o ${target} && chmod +x ${target}"
                fi
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "  --quick, -q           Non-interactive quick mode"
                echo "  --china, -c           Prefer China mirrors"
                echo "  --config FILE         Unattended deployment via config file"
                echo "                        See: --help-config for format"
                echo "  --install, -i         Copy to /usr/local/bin for PATH use"
                echo "  --help, -h            Show this help"
                echo "  --help-config         Show config file format"
                echo
                echo "Remote (curl | bash):"
                echo "  curl -fsSL <URL> | sudo bash"
                echo "  curl -fsSL <URL> | sudo bash -s -- --quick --china"
                exit 0
                ;;
            --help-config)
                cat << CFGEOF
Config file format for --config FILE
=====================================

Create a plain text file with key=value lines.
Empty lines and lines starting with '#' are ignored.

Required (at minimum, one of APT_MIRROR or NPM_MIRROR must be set):

  APT_MIRROR            APT mirror hostname
                        Examples:
                          mirrors.aliyun.com
                          deb.debian.org
                          archive.ubuntu.com

  NPM_MIRROR            npm registry URL
                        Examples:
                          https://registry.npmmirror.com/
                          https://registry.npmjs.org/

Optional (Claude Code credentials — prompts interactively if omitted):

  ANTHROPIC_API_KEY     Your Anthropic API key (sk-ant-...)
  ANTHROPIC_BASE_URL    API endpoint URL (default: https://api.anthropic.com)
  ANTHROPIC_MODEL       Model name (default: claude-sonnet-4-6-20250224)

Example config file:

  # Use Aliyun APT mirror + npmmirror (China-optimised)
  APT_MIRROR=mirrors.aliyun.com
  NPM_MIRROR=https://registry.npmmirror.com/

  # Claude Code credentials
  ANTHROPIC_API_KEY=sk-ant-0123456789abcdef
  ANTHROPIC_BASE_URL=https://api.anthropic.com
  ANTHROPIC_MODEL=claude-sonnet-4-6-20250224

Run:

  sudo bash deploy_claude.sh --config myconfig.conf

CFGEOF
                exit 0
                ;;
            *) echo "Unknown: $1"; exit 1 ;;
        esac
    done

    require_root "${orig_args[@]}"
    detect_os
    check_version

    if [ -n "$config_file" ]; then
        read_config_file "$config_file"
        run_full_deploy
    elif [ "$quick_mode" = true ]; then
        run_quick_mode
    else
        show_menu
        handle_menu
    fi
}

main "$@"
