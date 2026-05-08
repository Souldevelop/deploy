# Claude Code CLI 一键部署工具 **v2.2.6**

在 Linux (Debian / Ubuntu) 和 Windows 上一键安装 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview) 的自动化脚本。

支持 **x86_64 (amd64)** 和 **ARM64 (aarch64)** 双架构。

## 系统要求

| 系统 | 最低版本 | 支持架构 |
|------|----------|----------|
| Debian | 11 (bullseye) / 12 (bookworm) / 13 (trixie) | amd64、arm64 |
| Ubuntu | 18.04 (bionic) ~ 26.x | amd64、arm64 |
| Windows | 10 / 11、Windows Server 2016+ | amd64、arm64 |

> **ARM64 支持**: Linux 端在树莓派、Orange Pi、AWS Graviton 等 ARM64 设备上测试通过；Windows 端支持 Surface Pro X/9/11 等 ARM64 Windows 设备。

## 功能特性

- **一键部署** — 自动检测系统版本和架构，选择合适的安装方式
- **双架构支持** — Linux ARM64 自动识别并使用 `ports.ubuntu.com` 源；Windows ARM64 自动下载 `arm64` 版 Node.js MSI
- **多源智能切换** — Linux 下 NodeSource apt 安装优先，ARM 架构/J段回退到二进制 tarball；安装源双向回退（npmmirror ↔ nodejs.org）
- **中国网络优化** — 自动检测中国网络环境，使用国内 APT / npm / Node.js 镜像
- **无人值守部署** — 通过配置文件实现全程自动化安装，无需交互
- **CC-Switch 集成** — Windows 版额外集成 AI API 切换工具 CC-Switch 自动安装
- **干净卸载** — Linux 提供完整的卸载脚本（`remove_claude.sh`）

## 快速开始

### 方式一：远程一键安装（推荐）

```bash
# 使用 curl
curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh | bash -s -- \
  --config <(curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy.conf)

# 使用 wget（系统无 curl 时）
wget -qO- https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh | bash -s -- \
  --config <(wget -qO- https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy.conf)
```

此命令会自动处理：
- **Debian 13（root，无 sudo）** → 直接执行
- **Ubuntu（非 root，有 sudo）** → 自动提权（输入密码）
- **Debian 13（非 root，无 sudo）** → 自动使用 `su` 提权（输入 root 密码）

### 方式二：先下载再安装

```bash
# 使用 curl
curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy.conf -o /tmp/deploy.conf
curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh -o /tmp/deploy_claude.sh
sudo bash /tmp/deploy_claude.sh --config /tmp/deploy.conf

# 使用 wget
wget -qO /tmp/deploy.conf https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy.conf
wget -qO /tmp/deploy_claude.sh https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh
sudo bash /tmp/deploy_claude.sh --config /tmp/deploy.conf
```

### 方式三：本地交互式菜单（Linux）

```bash
git clone git@github.com:Souldevelop/deploy.git
cd deploy
sudo bash deploy_claude.sh
```

### 方式四：Windows 部署

Windows 下使用 PowerShell 脚本，支持自动提权和管理员安装。

```powershell
# 克隆仓库后运行
git clone git@github.com:Souldevelop/deploy.git
cd deploy
.\deploy_claude.bat

# 或直接运行 PowerShell 脚本
powershell -NoProfile -ExecutionPolicy Bypass -File deploy.ps1

# 指定配置文件运行
powershell -NoProfile -ExecutionPolicy Bypass -File deploy.ps1 -ConfigFile deploy.conf
```

**Windows 系统特别说明：**

- 脚本会自动请求管理员权限（安装 Node.js 需要）
- 提供 `deploy_claude.bat` 批处理启动器，可直接双击运行
- Node.js 通过 MSI 安装包静默安装，可从 nodejs.org 或 npmmirror 下载
- **ARM64 Windows** 自动下载 `arm64` 版 Node.js MSI
- 支持 `deploy.conf` 配置文件（格式与 Linux 版相同）
- 额外集成 CC-Switch（AI API 切换工具）自动安装
- **不支持通过远程管道一键安装**（PowerShell 远程执行策略限制），请先下载到本地再运行

## 无人值守配置文件

通过 `--config` 参数指定配置文件，可实现全程无人值守自动化部署。

### 配置文件格式

```
# APT 镜像源（必填）
APT_MIRROR=mirrors.aliyun.com

# npm 镜像源（必填）
NPM_MIRROR=https://registry.npmmirror.com/

# Claude API 密钥（必填，从 https://console.anthropic.com/ 获取）
ANTHROPIC_API_KEY=sk-ant-替换成你的真实密钥

# API 地址（选填，默认 https://api.anthropic.com）
ANTHROPIC_BASE_URL=https://api.anthropic.com

# 默认模型（选填，默认 claude-sonnet-4-6-20250224）
ANTHROPIC_MODEL=claude-sonnet-4-6-20250224
```

### 配置项说明

| 配置项 | 必填 | 说明 |
|--------|------|------|
| `APT_MIRROR` | 是 | APT 镜像源地址，只填主机名 |
| `NPM_MIRROR` | 是 | npm 注册表完整 URL |
| `ANTHROPIC_API_KEY` | 否 | Claude API 密钥，不填则安装过程提示输入 |
| `ANTHROPIC_BASE_URL` | 否 | API 端点地址，默认 `https://api.anthropic.com` |
| `ANTHROPIC_MODEL` | 否 | 默认模型名，不填则安装过程提示选择 |

## 命令行参数

```
deploy_claude.sh [OPTIONS]

  --quick, -q           非交互式快速模式（自动检测最佳配置）
  --china, -c           优先使用中国镜像
  --config FILE         通过配置文件实现无人值守部署
  --install, -i         复制脚本到 /usr/local/bin/
  --help, -h            显示帮助信息
  --help-config         显示配置文件格式说明

远程使用:
  curl -fsSL <URL> | bash -s -- --quick --china
  curl -fsSL <URL> | bash -s -- --config <(curl -fsSL <URL>)
  wget -qO- <URL> | bash -s -- --quick --china
  wget -qO- <URL> | bash -s -- --config <(wget -qO- <URL>)
```

## 安装流程

### Linux

1. **检测操作系统** — 自动识别 Debian/Ubuntu 版本和架构（amd64 / arm64）
2. **安装系统依赖** — 安装 `curl`、`ca-certificates`、`git`
3. **配置 APT 镜像源** — 切换到选择的镜像源（ARM Ubuntu 自动使用 `ubuntu-ports`）
4. **安装 Node.js** — amd64 优先 NodeSource apt，arm64 直接走二进制 tarball；安装源双向回退
5. **配置 npm 镜像源** — 设置 npm registry 地址
6. **安装 Claude Code CLI** — 通过 npm 全局安装 `@anthropic-ai/claude-code`
7. **配置 Claude Code** — 写入 API 密钥、地址、模型等信息

### Windows

1. **提权** — 自动检测管理员权限，非管理员时弹出 UAC 提权窗口
2. **加载配置** — 解析 `deploy.conf` 配置文件
3. **安装 Node.js** — 根据架构（x64 / arm64）下载对应 MSI 静默安装，带进度显示
4. **配置 npm 镜像源** — 设置 npm registry 地址
5. **安装 Claude Code CLI** — 通过 npm 全局安装 `@anthropic-ai/claude-code`，失败自动重试
6. **安装 CC-Switch** — 从 GitHub 下载最新 MSI 并静默安装 AI API 切换工具
7. **配置 Claude Code** — 写入 API 密钥、地址、模型等信息（交互式或配置文件中读取）
8. **清理临时文件** — 删除下载的 MSI 安装包

## Node.js 版本策略

| 系统版本 | Node.js 版本 | amd64 安装方式 | arm64 安装方式 |
|----------|-------------|----------------|----------------|
| Debian 11 | 20.x | NodeSource → 二进制回退 | 二进制 tarball |
| Debian 12+ | 22.x | NodeSource → 二进制回退 | 二进制 tarball |
| Ubuntu 18.04 / 20.04 | 20.x | NodeSource → 二进制回退 | 二进制 tarball |
| Ubuntu 22.04+ | 22.x | NodeSource → 二进制回退 | 二进制 tarball |
| Windows | 22.x | MSI 安装 | arm64 MSI 安装 |

**最低要求**: Node.js >= 18.x

> **ARM 说明**: Linux ARM 架构跳过 NodeSource apt 安装（国内 ARM 镜像不稳定），直接走 Node.js 官方二进制 tarball；Windows ARM64 自动下载 `arm64` 版 MSI。

## ARM 架构特别说明

### Linux ARM64（树莓派 / Orange Pi / AWS Graviton 等）

- **APT 源**: Ubuntu ARM 设备自动使用 `ports.ubuntu.com/ubuntu-ports` 路径（非 x86 的 `/ubuntu/`）
- **Node.js**: 直接下载官方 `linux-arm64` 二进制包，跳过 NodeSource apt 安装
- **镜像回退**: 版本发现和下载阶段双向回退（npmmirror ↔ nodejs.org）
- **经典版树莓派 (armv7l/armhf)**: 同样适用上述策略

### Windows ARM64（Surface Pro X/9/11 等）

- **Node.js**: 自动检测 `PROCESSOR_ARCHITECTURE` 为 `ARM64`，下载 `arm64` 版 MSI
- **兼容模式**: 对 WoW64 (x86 模拟) 环境同样支持，通过 `PROCESSOR_IDENTIFIER` 辅助检测

## 卸载

```bash
# 使用 curl
curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/remove_claude.sh | sudo bash

# 使用 wget
wget -qO- https://raw.githubusercontent.com/Souldevelop/deploy/master/remove_claude.sh | sudo bash

# 本地执行
sudo bash remove_claude.sh

# 自动模式（不交互）
sudo bash remove_claude.sh --auto

# 预览模式
sudo bash remove_claude.sh --dry-run
```

## 中国网络优化

在中国大陆使用，脚本会自动处理：

- **APT 镜像** — 检测 Aliyun 镜像可达性，优先使用国内源
- **npm 镜像** — 默认使用 `npmmirror.com`
- **Node.js 下载** — 双向回退，国内镜像不可达时自动切官方源

```bash
# 使用 curl
curl -fsSL https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh | bash -s -- --china

# 使用 wget
wget -qO- https://raw.githubusercontent.com/Souldevelop/deploy/master/deploy_claude.sh | bash -s -- --china
```

## 设备管理部署（Device Policy）

在已安装 Claude Code 的设备上，通过 `install-device-policy.sh` 一键注入**设备管理技能**，让 AI 会话自动识别设备角色、获得免确认操作权限，并记录操作日志。

### 功能特性

- **设备认知** — 自动检测设备型号、OS、CPU、内存等硬件信息，注入 AI 会话上下文
- **权限免确认** — Read/Write/Edit/Bash/Glob/Grep/WebSearch/WebFetch 工具自动允许，减少交互确认
- **危险命令拦截** — `rm -rf /`、`dd if=/dev/zero` 等高危操作自动拒绝
- **操作日志** — Write/Edit 及写操作 Bash 命令自动记录到 `~/.claude/device-policy/logs/`
- **零外部依赖** — 仅需 bash/awk/sed/grep，所有 Linux 系统内置

### 快速安装

```bash
curl -sL https://raw.githubusercontent.com/Souldevelop/deploy/master/install-device-policy.sh | bash
```

### 生效验证

新开 Claude Code 会话后，直接提问：

> 请描述这台设备的型号、操作系统、CPU、内存

若 AI 能直接报出具体设备信息，说明部署成功。

### 部署文件结构

```
~/.claude/
├── settings.local.json              # 权限与 hooks 配置
├── device-policy/
│   ├── SKILL.md                     # 设备管理技能定义
│   ├── device-context-hook.sh       # SessionStart hook — 注入技能上下文
│   ├── device-log-hook.sh           # PreToolUse hook — 操作日志记录
│   └── logs/                        # 操作日志目录
└── projects/-root/memory/
    ├── MEMORY.md
    └── device_admin.md              # 设备管理记忆文件
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy_claude.sh` | Linux 主部署脚本（bash） |
| `deploy_claude.bat` | Windows 批处理启动器 |
| `deploy.ps1` | Windows PowerShell 部署脚本 |
| `deploy.conf` | 配置文件示例（Linux / Windows 通用） |
| `remove_claude.sh` | Linux 卸载脚本 |
| `install-device-policy.sh` | 设备管理技能与配置部署脚本 |
| `vendor/` | 依赖的第三方安装包（如 CC-Switch MSI） |
| `README.md` | 本文档 |

## 许可证

MIT
