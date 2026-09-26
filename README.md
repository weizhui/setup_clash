# setup_clash

Linux 一键安装、更新和管理 Clash/Mihomo 的脚本。默认下载并安装 maintained 的 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 内核，支持写入 Clash YAML 订阅配置，并通过用户级 systemd 服务后台运行。

## 功能

- 自动识别 Linux CPU 架构并下载对应的 Mihomo release
- 支持 Clash / Clash Meta / YAML 专用订阅地址
- 自动补齐常用配置项，如 `mixed-port`、`mode`、`external-controller`
- 支持用户级 systemd 服务启动、停止、重启和查看状态
- 支持后续只更新订阅配置
- 对 Base64 节点列表、普通节点列表等非 Clash YAML 内容给出明确提示

## 环境要求

- Linux
- Bash
- `curl`
- `grep`
- `sed`
- `gzip`
- `systemctl` 可选；没有 systemd 时脚本会前台运行

支持的架构包括：

- `x86_64` / `amd64`
- `aarch64` / `arm64`
- `armv7l`
- `armv6l`
- `i386` / `i686`

## 快速开始

```bash
bash setup_clash.sh install "https://example.com/api/v1/client/subscribe?token=xxx"
```

兼容旧用法：

```bash
bash setup_clash.sh "https://example.com/api/v1/client/subscribe?token=xxx"
```

安装完成后，默认会使用以下端口：

- HTTP/SOCKS 混合代理：`127.0.0.1:7890`
- External Controller：`127.0.0.1:9090`

## 常用命令

```bash
# 安装内核、写入配置、配置服务并启动
bash setup_clash.sh install "订阅地址"

# 只更新 config.yaml，并在存在 systemd 用户服务时自动重启
bash setup_clash.sh update-config "订阅地址"

# 启动
bash setup_clash.sh start

# 停止
bash setup_clash.sh stop

# 重启
bash setup_clash.sh restart

# 查看状态
bash setup_clash.sh status

# 测试配置
bash setup_clash.sh test

# 查看帮助
bash setup_clash.sh help
```

如果执行 `update-config` 时不传订阅地址，脚本会尝试复用上次保存的订阅地址。

## 默认文件位置

默认安装目录为：

```text
$HOME/clash
```

主要文件：

```text
$HOME/clash/clash          # Mihomo/Clash 内核
$HOME/clash/config.yaml    # Clash 配置文件
$HOME/clash/subscribe.url  # 上次使用的订阅地址
```

systemd 用户服务文件：

```text
$HOME/.config/systemd/user/clash.service
```

## 环境变量

可以通过环境变量调整默认行为：

```bash
# 自定义安装目录
CLASH_DIR="$HOME/clash" bash setup_clash.sh install "订阅地址"

# 自定义 Mihomo release 仓库
CLASH_REPO="MetaCubeX/mihomo" bash setup_clash.sh install "订阅地址"

# 设置 external-controller secret
CLASH_SECRET="your-dashboard-secret" bash setup_clash.sh install "订阅地址"
```

## 订阅地址说明

请使用面板提供的 Clash / Clash Meta / YAML 专用订阅地址。脚本不会把普通节点订阅自动转换成 Clash YAML。

如果订阅返回的是 Base64 节点列表，或直接返回如下类型的节点列表：

```text
vmess://...
vless://...
ss://...
trojan://...
```

脚本会停止并提示更换订阅地址。

## 代理使用

启动成功后，可以临时为当前 shell 设置代理：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
```

取消代理：

```bash
unset http_proxy https_proxy all_proxy
```

## 故障排查

查看服务状态：

```bash
bash setup_clash.sh status
```

测试配置文件：

```bash
bash setup_clash.sh test
```

如果提示配置不像 Clash YAML，请回到订阅面板复制 Clash / Clash Meta / YAML 专用链接后重试。

如果系统没有 systemd 用户服务，脚本会以前台方式启动 Clash，按 `Ctrl+C` 停止。

## 注意事项

- 当前脚本仅支持 Linux。
- 订阅地址通常包含 token，请不要公开泄露。
- 默认 `allow-lan` 为 `false`，不会开放给局域网设备使用。
