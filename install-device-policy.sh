#!/bin/bash
# device-policy 一键部署脚本（自包含单文件）
# 用法: curl -sL <url> | bash
set -e

TEMPLATE_SETTINGS="ewogICJwZXJtaXNzaW9ucyI6IHsKICAgICJhbGxvdyI6IFsKICAgICAgIkJhc2giLAogICAgICAiUmVhZCIsCiAgICAgICJXcml0ZSIsCiAgICAgICJFZGl0IiwKICAgICAgIldlYlNlYXJjaCIsCiAgICAgICJXZWJGZXRjaCIsCiAgICAgICJHbG9iIiwKICAgICAgIkdyZXAiCiAgICBdLAogICAgImRlbnkiOiBbCiAgICAgICJCYXNoKHJtIC1yZiAvKSIsCiAgICAgICJCYXNoKHJtIC1yZiAvKikiLAogICAgICAiQmFzaCg+IC9kZXYvc2QqKSIsCiAgICAgICJCYXNoKGRkIGlmPS9kZXYvemVybykiCiAgICBdCiAgfSwKICAiaG9va3MiOiB7CiAgICAiU2Vzc2lvblN0YXJ0IjogWwogICAgICB7CiAgICAgICAgImhvb2tzIjogWwogICAgICAgICAgewogICAgICAgICAgICAidHlwZSI6ICJjb21tYW5kIiwKICAgICAgICAgICAgImNvbW1hbmQiOiAiU0tJTExfQ09OVEVOVD0kKGNhdCAkSE9NRS8uY2xhdWRlL2RldmljZS1wb2xpY3kvU0tJTEwubWQgMj4vZGV2L251bGwpOyBqcSAtbiAtYyAtLWFyZyBjdHggXCIkU0tJTExfQ09OVEVOVFwiICd7XCJob29rU3BlY2lmaWNPdXRwdXRcIjoge1wiaG9va0V2ZW50TmFtZVwiOiBcIlNlc3Npb25TdGFydFwiLCBcImFkZGl0aW9uYWxDb250ZXh0XCI6ICRjdHh9fScgMj4vZGV2L251bGwgfHwgZWNobyAne1wic3lzdGVtTWVzc2FnZVwiOlwiRGV2aWNlLXBvbGljeSBza2lsbCBub3QgZm91bmRcIn0nIiwKICAgICAgICAgICAgInRpbWVvdXQiOiA1LAogICAgICAgICAgICAic3RhdHVzTWVzc2FnZSI6ICJMb2FkaW5nIGRldmljZSBwb2xpY3kgY29udGV4dC4uLiIKICAgICAgICAgIH0KICAgICAgICBdCiAgICAgIH0KICAgIF0sCiAgICAiUHJlVG9vbFVzZSI6IFsKICAgICAgewogICAgICAgICJtYXRjaGVyIjogIkJhc2h8V3JpdGV8RWRpdCIsCiAgICAgICAgImhvb2tzIjogWwogICAgICAgICAgewogICAgICAgICAgICAidHlwZSI6ICJjb21tYW5kIiwKICAgICAgICAgICAgImNvbW1hbmQiOiAiY2F0IHwgJEhPTUUvLmNsYXVkZS9kZXZpY2UtcG9saWN5L2RldmljZS1sb2ctaG9vay5zaCAyPi9kZXYvbnVsbCB8fCB0cnVlIiwKICAgICAgICAgICAgInRpbWVvdXQiOiA1LAogICAgICAgICAgICAic3RhdHVzTWVzc2FnZSI6ICIiCiAgICAgICAgICB9CiAgICAgICAgXQogICAgICB9CiAgICBdCiAgfQp9Cg=="
LOG_HOOK="IyEvYmluL2Jhc2gKIyBEZXZpY2Ugb3BlcmF0aW9uIGxvZ2dpbmcgaG9vayBmb3IgQ2xhdWRlIENvZGUKIyBDYWxsZWQgZnJvbSBQcmVUb29sVXNlIGhvb2tzIHdpdGggSlNPTiBvbiBzdGRpbgojIExvZ3MgZGV2aWNlLW1vZGlmeWluZyBvcGVyYXRpb25zIHRvIH4vLmNsYXVkZS9kZXZpY2UtcG9saWN5L2xvZ3MvCgpJTlBVVD0kKGNhdCkKClRPT0xfTkFNRT0kKGVjaG8gIiRJTlBVVCIgfCBqcSAtciAnLnRvb2xfbmFtZSAvLyBlbXB0eScpClRPT0xfSU5QVVQ9JChlY2hvICIkSU5QVVQiIHwganEgLXIgJy50b29sX2lucHV0IC8vIGVtcHR5JykKU0VTU0lPTl9JRD0kKGVjaG8gIiRJTlBVVCIgfCBqcSAtciAnLnNlc3Npb25faWQgLy8gZW1wdHknKQoKWyAteiAiJFRPT0xfTkFNRSIgXSAmJiBleGl0IDAKClRJTUVTVEFNUD0kKGRhdGUgJyslSDolTTolUycpCkxPR19EQVRFPSQoZGF0ZSAnKyVZJW0lZCcpClNFU1NJT05fTE9HPSIkSE9NRS8uY2xhdWRlL2RldmljZS1wb2xpY3kvbG9ncy8ke0xPR19EQVRFfS5tZCIKCmlmIFsgISAtZiAiJFNFU1NJT05fTE9HIiBdOyB0aGVuCiAgICBlY2hvICIjIFNlc3Npb24gJChkYXRlICcrJVktJW0tJWQgJUg6JU0nKSAtIERldmljZSBPcGVyYXRpb25zIExvZyIgPiAiJFNFU1NJT05fTE9HIgpmaQoKY2FzZSAiJFRPT0xfTkFNRSIgaW4KICAgIEJhc2gpCiAgICAgICAgQ09NTUFORD0kKGVjaG8gIiRJTlBVVCIgfCBqcSAtciAnLnRvb2xfaW5wdXQuY29tbWFuZCAvLyBlbXB0eScpCiAgICAgICAgWyAteiAiJENPTU1BTkQiIF0gJiYgZXhpdCAwCiAgICAgICAgY2FzZSAiJENPTU1BTkQiIGluCiAgICAgICAgICAgIGxzXCAqfGxzfGNhdFwgL3Byb2MqfGNhdFwgL3N5cyp8aGVhZFwgKnx0YWlsXCAqfGVjaG9cICp8Z3JlcFwgKnxmaW5kXCAqfHdoaWNoXCAqfHdob1wgKnx1cHRpbWVcICp8ZnJlZVwgKnxkZlwgKnxwc1wgKnxzc1wgKnxpcFwgYWRkcipcIHxpcFwgcm91dGUqXCB8am91cm5hbGN0bFwgKnxzeXN0ZW1jdGxcIHN0YXR1c1wgKnxzeXN0ZW1jdGxcIGxpc3QtKlwgfGRvY2tlclwgcHNcICp8ZG9ja2VyXCAtLXZlcnNpb24qfGRhdGVcICp8dHJ1ZXxmYWxzZXxwd2RcICp8aWRcICp8dW5hbWVcICp8aG9zdG5hbWVcICp8d2NcICp8c29ydFwgKnxjdXRcICp8aGlzdG9yeVwgKnx0eXBlXCAqfHByaW50ZW52XCAqfGVudlwgKnxsc2Jsa1wgKnxsc2NwdVwgKnxsc3BjaVwgKnxsc3VzYlwgKnx6cmFtY3RsXCAqfHN3YXBvblwgKnxwaXAzXCAqfG5wbVwgKnxkb2NrZXJcIC0tdmVyc2lvbnxweXRob24zXCAtLXZlcnNpb258bm9kZVwgLS12ZXJzaW9ufGdpdFwgc3RhdHVzXCAqfGdpdFwgbG9nXCAqfGdpdFwgZGlmZlwgKnxnaXRcIC0tdmVyc2lvbnxodG9wXCAqfHZuc3RhdFwgKnx0cmFjZXJvdXRlXCAqfHBpbmdcICp8bnNsb29rdXBcICp8ZGlnXCAqfGpxXCAqKQogICAgICAgICAgICAgICAgZXhpdCAwCiAgICAgICAgICAgICAgICA7OwogICAgICAgIGVzYWMKICAgICAgICA7OwogICAgV3JpdGV8RWRpdCkKICAgICAgICBGSUxFX1BBVEg9JChlY2hvICIkSU5QVVQiIHwganEgLXIgJy50b29sX2lucHV0LmZpbGVfcGF0aCAvLyBlbXB0eScpCiAgICAgICAgY2FzZSAiJEZJTEVfUEFUSCIgaW4KICAgICAgICAgICAgKi9kZXZpY2UtcG9saWN5L2xvZ3MvKnwkSE9NRS8uY2xhdWRlL21lbW9yeS8qKQogICAgICAgICAgICAgICAgZXhpdCAwCiAgICAgICAgICAgICAgICA7OwogICAgICAgIGVzYWMKICAgICAgICA7OwogICAgKikKICAgICAgICBleGl0IDAKICAgICAgICA7Owplc2FjCgp7CiAgICBlY2hvICIiCiAgICBlY2hvICIjIyAke1RJTUVTVEFNUH0gLSAke1RPT0xfTkFNRX0iCiAgICBlY2hvICdgYGBqc29uJwogICAgZWNobyAiJElOUFVUIiB8IGpxIC1jICd7dG9vbDogLnRvb2xfbmFtZSwgaW5wdXQ6IC50b29sX2lucHV0fScgMj4vZGV2L251bGwKICAgIGVjaG8gJ2BgYCcKfSA+PiAiJFNFU1NJT05fTE9HIgo="

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

# 部署 settings.local.json
echo "$TEMPLATE_SETTINGS" | base64 -d > "$CLAUDE_DIR/settings.local.json"

# 部署日志脚本
echo "$LOG_HOOK" | base64 -d > "$CLAUDE_DIR/device-policy/device-log-hook.sh"
chmod +x "$CLAUDE_DIR/device-policy/device-log-hook.sh"

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
echo "  $CLAUDE_DIR/device-policy/device-log-hook.sh"
echo "  $CLAUDE_DIR/device-policy/logs/"
echo "  $CLAUDE_DIR/settings.local.json"
echo ""
echo "新会话自动生效:"
echo "  1. SessionStart → 自动加载设备档案"
echo "  2. 权限全部免确认"
echo "  3. 操作自动记录日志"
