#!/bin/bash
# device-policy 一键部署脚本（自包含单文件）
# 用法: curl -sL <url> | bash
# 依赖: bash, awk, sed, grep — 任何 Linux 系统都内置
set -e

echo "=== device-policy 部署开始 ==="

# 检测设备信息
HOSTNAME=$(hostname)
OS_INFO=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Unknown")
KERNEL=$(uname -r)
ARCH=$(uname -m)
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | head -1 | awk -F': ' '{print $2}' || echo "Unknown")
CPU_CORES=$(nproc 2>/dev/null || echo "?")
CPU_MAX=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk -F': ' '{print $2}' || echo "?")
MEM_TOTAL=$(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo "?")
DISK_TOTAL=$(df -h / 2>/dev/null | tail -1 | awk '{print $2}' || echo "?")
DISK_USED=$(df -h / 2>/dev/null | tail -1 | awk '{print $3}' || echo "?")
IP_ADDR=$(ip -4 addr show 2>/dev/null | grep inet | head -3 | awk '{print $2}' | tr '\n' ' ' || echo "?")
DEVICE_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr '\0' ' ' || echo "$ARCH device")
[ -z "$DEVICE_MODEL" ] && DEVICE_MODEL="$ARCH device"

echo "  设备: $DEVICE_MODEL"
echo "  OS: $OS_INFO"
echo "  CPU: $CPU_MODEL x $CPU_CORES"
echo "  RAM: $MEM_TOTAL"

# 询问职责 (非交互模式跳过)
if [ -t 0 ]; then
    echo "" && echo "--- 管理职责配置 ---"
    echo "输入用途/职责（留空默认）:" && read -r ADMIN_DUTIES
    [ -z "$ADMIN_DUTIES" ] && ADMIN_DUTIES="- 系统监控（CPU、内存、磁盘、温度）\n- 软件维护（更新、Docker、包管理）\n- 网络管理\n- 故障排查\n- 安全管理"
else
    ADMIN_DUTIES="- 系统监控（CPU、内存、磁盘、温度）\n- 软件维护（更新、Docker、包管理）\n- 网络管理\n- 故障排查\n- 安全管理"
fi

# 创建目录
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/device-policy/logs"
mkdir -p "$CLAUDE_DIR/projects/-root/memory"

# 生成 SKILL.md
cat > "$CLAUDE_DIR/device-policy/SKILL.md" << SKILLEOF
---
name: device-policy
description: |
  Device administration skill for $DEVICE_MODEL ($HOSTNAME).
  TRIGGER WHEN the user mentions: "设备", "device", "管理", "维护", "maintenance", "监控",
  "性能", "performance", "network", "系统状态", "update", "升级", "备份", "配置", "config",
  or any system administration task on this device.
---

# Device Administration — $DEVICE_MODEL

You are the **primary system administrator** for this device.

## Device Identity

| Attribute | Value |
|-----------|-------|
| **Model** | $DEVICE_MODEL |
| **Hostname** | $HOSTNAME |
| **OS** | $OS_INFO |
| **Kernel** | $KERNEL ($ARCH) |

## Hardware

- **CPU**: $CPU_MODEL, $CPU_CORES cores @ $CPU_MAX MHz
- **RAM**: $MEM_TOTAL
- **Disk**: $DISK_USED used / $DISK_TOTAL total
- **Network**: $IP_ADDR

## Responsibilities

$(echo -e "$ADMIN_DUTIES")

## Rules

1. **Session-start**: Device context auto-loaded via SessionStart hook.
2. **Permissions**: All tool operations auto-approved (settings.local.json).
3. **Logging**: Modifications logged to ~/.claude/device-policy/logs/.
4. **Safety**: Dangerous operations (rm -rf /, dd) blocked.

## Quick Reference

\`\`\`bash
htop              # Process viewer
free -h           # Memory
df -h /           # Disk
ip addr show      # Network
ss -tlnp          # Ports
\`\`\`
SKILLEOF

# 部署 device-context-hook.sh — SessionStart 钩子
# 将 SKILL.md 内容以 JSON 格式注入 Claude Code 会话上下文
# 不依赖 jq，使用 awk/sed 纯文本处理
cat > "$CLAUDE_DIR/device-policy/device-context-hook.sh" << 'CTXEOF'
#!/bin/bash
# device-context-hook.sh — SessionStart hook for device-policy
# Reads SKILL.md and outputs hook response JSON
SKILL_PATH="$HOME/.claude/device-policy/SKILL.md"
if [ ! -f "$SKILL_PATH" ]; then
    echo '{"systemMessage":"Device policy skill not found"}'
    exit 0
fi

# Use awk to escape JSON special chars and construct the hook response
# Escapes: backslash (\) and double-quote (")
awk '
BEGIN {
    printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\""
}
{
    gsub(/[\\"]/, "\\\\&")
    printf "%s\\n", $0
}
END {
    print "\"}}"
}
' "$SKILL_PATH"
CTXEOF
chmod +x "$CLAUDE_DIR/device-policy/device-context-hook.sh"

# 部署 device-log-hook.sh — PreToolUse 钩子
# 在 Bash/Write/Edit 操作前调用，记录操作日志
# 不依赖 jq，使用 sed/grep 提取 JSON 字段
cat > "$CLAUDE_DIR/device-policy/device-log-hook.sh" << 'LOGHOOKEOF'
#!/bin/bash
# device-log-hook.sh — PreToolUse hook for device-policy
# Logs device-modifying operations to ~/.claude/device-policy/logs/
# Called by Claude Code with tool call JSON on stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Extract tool_name from JSON using sed
TOOL_NAME=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$TOOL_NAME" ] && exit 0

TIMESTAMP=$(date '+%H:%M:%S')
LOG_DATE=$(date '+%Y%m%d')
SESSION_LOG="$HOME/.claude/device-policy/logs/${LOG_DATE}.md"

[ ! -f "$SESSION_LOG" ] && echo "# Session $(date '+%Y-%m-%d %H:%M') - Device Operations Log" > "$SESSION_LOG"

case "$TOOL_NAME" in
    Bash)
        COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        [ -z "$COMMAND" ] && exit 0
        # Read-only 命令免记录
        case "$COMMAND" in
            ls\ *|ls|cat\ /proc*|cat\ /sys*|head\ *|tail\ *|echo\ *|grep\ *|find\ *|which\ *|who\ *|uptime\ *|free\ *|df\ *|ps\ *|ss\ *|ip\ addr*\ |ip\ route*\ |journalctl\ *|systemctl\ status\ *|systemctl\ list-*\ |docker\ ps\ *|docker\ --version*|date\ *|true|false|pwd\ *|id\ *|uname\ *|hostname\ *|wc\ *|sort\ *|cut\ *|history\ *|type\ *|printenv\ *|env\ *|lsblk\ *|lscpu\ *|lspci\ *|lsusb\ *|zramctl\ *|swapon\ *|pip3\ *|npm\ *|docker\ --version|python3\ --version|node\ --version|git\ status\ *|git\ log\ *|git\ diff\ *|git\ --version|htop\ *|vnstat\ *|traceroute\ *|ping\ *|nslookup\ *|dig\ *|jq\ *)
                exit 0
                ;;
        esac
        ;;
    Write|Edit)
        FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        # 日志目录和记忆文件的操作免记录（避免递归）
        case "$FILE_PATH" in
            */device-policy/logs/*|$HOME/.claude/memory/*)
                exit 0
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac

# 记录操作
{
    echo ""
    echo "## ${TIMESTAMP} - ${TOOL_NAME}"
    echo '```'
    echo "$INPUT"
    echo '```'
} >> "$SESSION_LOG"
LOGHOOKEOF
chmod +x "$CLAUDE_DIR/device-policy/device-log-hook.sh"

# 部署 settings.local.json
cat > "$CLAUDE_DIR/settings.local.json" << 'JSONEOF'
{
  "permissions": {
    "allow": [
      "Bash",
      "Read",
      "Write",
      "Edit",
      "WebSearch",
      "WebFetch",
      "Glob",
      "Grep"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(> /dev/sd*)",
      "Bash(dd if=/dev/zero)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/device-policy/device-context-hook.sh",
            "timeout": 5,
            "statusMessage": "Loading device policy context..."
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/device-policy/device-log-hook.sh 2>/dev/null || true",
            "timeout": 5,
            "statusMessage": ""
          }
        ]
      }
    ]
  }
}
JSONEOF

# 部署记忆文件
cat > "$CLAUDE_DIR/projects/-root/memory/MEMORY.md" << 'MEMEOF'
- [Device Admin](device_admin.md) — Device specs, admin responsibilities, and management rules
MEMEOF

cat > "$CLAUDE_DIR/projects/-root/memory/device_admin.md" << DADEOF
---
name: Device Administration
description: Device admin info — loaded via SessionStart hook and settings.local.json
type: reference
---

**Device**: $DEVICE_MODEL ($HOSTNAME)
**OS**: $OS_INFO
**Admin rules**: SessionStart hook injects skill context; PreToolUse hook logs operations; permissions auto-approved.
DADEOF

echo ""
echo "=== 部署完成 ==="
echo "  $CLAUDE_DIR/device-policy/SKILL.md"
echo "  $CLAUDE_DIR/device-policy/device-context-hook.sh"
echo "  $CLAUDE_DIR/device-policy/device-log-hook.sh"
echo "  $CLAUDE_DIR/device-policy/logs/"
echo "  $CLAUDE_DIR/settings.local.json"
echo ""
echo "新会话自动生效:"
echo "  1. SessionStart → 自动加载设备档案 (纯 awk, 无 jq 依赖)"
echo "  2. 权限全部免确认"
echo "  3. 操作自动记录日志 (纯 sed, 无 jq 依赖)"
