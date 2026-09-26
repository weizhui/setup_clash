#!/usr/bin/env bash
set -euo pipefail

# 一键安装/更新/启动 Clash 内核。默认安装 maintained 的 mihomo(Clash.Meta)。
#
# 常用:
#   bash setup_clash.sh install "https://example.com/api/v1/client/subscribe?token=xxx"
#   bash setup_clash.sh start
#   bash setup_clash.sh status
#   bash setup_clash.sh stop
#   bash setup_clash.sh update-config "https://example.com/api/v1/client/subscribe?token=xxx"
#
# 也兼容旧用法:
#   bash setup_clash.sh "https://example.com/api/v1/client/subscribe?token=xxx"
#
# 可选环境变量:
#   CLASH_DIR="$HOME/clash"
#   CLASH_REPO="MetaCubeX/mihomo"
#   CLASH_SECRET="your-dashboard-secret"

CLASH_DIR="${CLASH_DIR:-$HOME/clash}"
CLASH_BIN="$CLASH_DIR/clash"
CONFIG_FILE="$CLASH_DIR/config.yaml"
SUBSCRIBE_FILE="$CLASH_DIR/subscribe.url"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/clash.service"
CLASH_REPO="${CLASH_REPO:-MetaCubeX/mihomo}"
CLASH_SECRET="${CLASH_SECRET:-}"

ACTION="${1:-install}"
SUBSCRIBE_URL="${2:-}"

if [[ "$ACTION" == http://* || "$ACTION" == https://* ]]; then
  SUBSCRIBE_URL="$ACTION"
  ACTION="install"
fi

TMP_FILE="$(mktemp)"
TMP_DECODED="$(mktemp)"
TMP_API="$(mktemp)"
TMP_BIN="$(mktemp)"

cleanup() {
  rm -f "$TMP_FILE" "$TMP_DECODED" "$TMP_API" "$TMP_BIN" "$TMP_BIN.gz"
}
trap cleanup EXIT

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

usage() {
  cat <<USAGE
用法:
  bash setup_clash.sh install <订阅地址>        下载内核、写配置、配置服务并启动
  bash setup_clash.sh update-config <订阅地址>  只更新 config.yaml
  bash setup_clash.sh start                    启动 Clash
  bash setup_clash.sh stop                     停止 Clash
  bash setup_clash.sh restart                  重启 Clash
  bash setup_clash.sh status                   查看状态
  bash setup_clash.sh test                     测试配置

兼容:
  bash setup_clash.sh <订阅地址>

默认目录:
  $CLASH_DIR
USAGE
}

detect_asset_keyword() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  [[ "$os" == "linux" ]] || die "当前脚本只处理 Linux，检测到: $os"

  case "$arch" in
    x86_64|amd64) echo "linux-amd64-compatible" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    armv7l) echo "linux-armv7" ;;
    armv6l) echo "linux-armv6" ;;
    i386|i686) echo "linux-386" ;;
    *) die "不支持的 CPU 架构: $arch" ;;
  esac
}

is_clash_yaml() {
  local file="$1"
  grep -Eq '^[[:space:]]*(proxies|proxy-groups|rules):[[:space:]]*$' "$file"
}

looks_like_proxy_list() {
  local file="$1"
  grep -Eq '^(vmess|vless|ss|ssr|trojan|hysteria2?|tuic)://' "$file"
}

patch_config_defaults() {
  local file="$1"
  : >"$TMP_DECODED"

  grep -Eq '^[[:space:]]*mixed-port:' "$file" || echo "mixed-port: 7890" >>"$TMP_DECODED"
  grep -Eq '^[[:space:]]*allow-lan:' "$file" || echo "allow-lan: false" >>"$TMP_DECODED"
  grep -Eq '^[[:space:]]*bind-address:' "$file" || echo "bind-address: '*'" >>"$TMP_DECODED"
  grep -Eq '^[[:space:]]*mode:' "$file" || echo "mode: rule" >>"$TMP_DECODED"
  grep -Eq '^[[:space:]]*log-level:' "$file" || echo "log-level: info" >>"$TMP_DECODED"
  grep -Eq '^[[:space:]]*external-controller:' "$file" || echo "external-controller: 127.0.0.1:9090" >>"$TMP_DECODED"
  if [[ -n "$CLASH_SECRET" ]] && ! grep -Eq '^[[:space:]]*secret:' "$file"; then
    echo "secret: '$CLASH_SECRET'" >>"$TMP_DECODED"
  fi

  if [[ -s "$TMP_DECODED" ]]; then
    cat "$file" >>"$TMP_DECODED"
    cp "$TMP_DECODED" "$file"
  fi
}

download_subscribe() {
  local url="$1"
  curl -fsSL \
    -A "Clash" \
    -H "Accept: text/plain, application/yaml, application/octet-stream, */*" \
    "$url" \
    -o "$TMP_FILE"
}

write_config() {
  local url="$1"

  if [[ -z "$url" ]]; then
    if [[ -f "$SUBSCRIBE_FILE" ]]; then
      url="$(sed -n '1p' "$SUBSCRIBE_FILE")"
    else
      die "缺少订阅地址。示例: bash setup_clash.sh install 'https://example.com/subscribe?token=xxx'"
    fi
  fi

  mkdir -p "$CLASH_DIR"
  info "下载订阅配置"
  download_subscribe "$url"

  if is_clash_yaml "$TMP_FILE"; then
    cp "$TMP_FILE" "$CONFIG_FILE"
    patch_config_defaults "$CONFIG_FILE"
    printf '%s\n' "$url" >"$SUBSCRIBE_FILE"
    info "已写入配置: $CONFIG_FILE"
    return
  fi

  if base64 -d "$TMP_FILE" >"$TMP_DECODED" 2>/dev/null && looks_like_proxy_list "$TMP_DECODED"; then
    cat >&2 <<ERROR_TEXT
ERROR: 当前订阅返回的是 Base64 节点列表，不是 Clash YAML。

解码后的开头类似:
$(head -n 3 "$TMP_DECODED")

请在面板里复制 Clash / Clash Meta / YAML 专用订阅地址后重试。
不能使用:
  curl '订阅地址' | base64 -d > config.yaml
ERROR_TEXT
    exit 2
  fi

  if looks_like_proxy_list "$TMP_FILE"; then
    cat >&2 <<ERROR_TEXT
ERROR: 当前订阅直接返回了节点列表，不是 Clash YAML。
请换成 Clash / Clash Meta / YAML 专用订阅地址。
ERROR_TEXT
    exit 2
  fi

  echo "ERROR: 下载内容不像 Clash 配置，前几行如下:" >&2
  head -n 10 "$TMP_FILE" >&2
  exit 2
}

download_clash() {
  need_cmd curl
  need_cmd grep
  need_cmd sed
  need_cmd gzip
  need_cmd chmod

  local keyword api_url download_url
  keyword="$(detect_asset_keyword)"
  api_url="https://api.github.com/repos/$CLASH_REPO/releases/latest"

  mkdir -p "$CLASH_DIR"
  info "获取最新内核: $CLASH_REPO ($keyword)"
  curl -fsSL "$api_url" -o "$TMP_API"

  download_url="$({
    grep -E '"browser_download_url":' "$TMP_API" \
      | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
      | grep "$keyword" \
      | grep -E '\.gz$' \
      | grep -Ev 'alpha|sha256|checksums|\.deb|\.rpm' \
      | head -n 1
  } || true)"

  [[ -n "$download_url" ]] || die "没有找到适合当前机器的 release 资产: $keyword"

  info "下载: $download_url"
  curl -fL "$download_url" -o "$TMP_BIN.gz"
  gzip -dc "$TMP_BIN.gz" >"$CLASH_BIN"
  chmod +x "$CLASH_BIN"
  info "已安装内核: $CLASH_BIN"
  "$CLASH_BIN" -v || true
}

test_config() {
  [[ -x "$CLASH_BIN" ]] || die "未找到可执行内核: $CLASH_BIN"
  [[ -f "$CONFIG_FILE" ]] || die "未找到配置文件: $CONFIG_FILE"
  info "测试配置"
  "$CLASH_BIN" -t -d "$CLASH_DIR"
}

write_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    info "未检测到 systemd，跳过服务配置"
    return
  fi

  mkdir -p "$SERVICE_DIR"
  cat >"$SERVICE_FILE" <<SERVICE
[Unit]
Description=Clash Proxy Service
After=network-online.target

[Service]
Type=simple
ExecStart=$CLASH_BIN -d $CLASH_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
SERVICE

  systemctl --user daemon-reload || true
  info "已写入用户服务: $SERVICE_FILE"
}

start_clash() {
  [[ -x "$CLASH_BIN" ]] || die "未找到可执行内核: $CLASH_BIN"
  [[ -f "$CONFIG_FILE" ]] || die "未找到配置文件: $CONFIG_FILE"

  if command -v systemctl >/dev/null 2>&1 && [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user enable clash.service || true
    systemctl --user restart clash.service
    info "Clash 已通过 systemd 用户服务启动"
    systemctl --user --no-pager --lines=20 status clash.service || true
  else
    info "前台启动 Clash，按 Ctrl+C 停止"
    exec "$CLASH_BIN" -d "$CLASH_DIR"
  fi
}

stop_clash() {
  if command -v systemctl >/dev/null 2>&1 && [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user stop clash.service
    info "Clash 已停止"
  else
    die "未配置 systemd 用户服务；如果是前台运行，请在运行窗口按 Ctrl+C"
  fi
}

print_process_status() {
  if ! command -v ps >/dev/null 2>&1; then
    return
  fi

  local processes
  processes="$(ps -eo pid=,ppid=,comm=,args= | awk '$3 == "clash" || $3 == "mihomo" || $0 ~ /\/(clash|mihomo)( |$)/ {print}')"

  if [[ -n "$processes" ]]; then
    echo
    echo "运行中的 Clash/Mihomo 进程:"
    echo "$processes"
  else
    echo
    echo "未发现运行中的 Clash/Mihomo 进程。"
  fi
}

print_port_status() {
  if ! command -v ss >/dev/null 2>&1; then
    return
  fi

  local ports
  ports="$(ss -ltnp | awk 'NR == 1 || /:(7890|9090)[[:space:]]/')"

  if [[ "$(echo "$ports" | wc -l)" -gt 1 ]]; then
    echo
    echo "默认 Clash 端口监听:"
    echo "$ports"
  fi
}

status_clash() {
  if command -v systemctl >/dev/null 2>&1 && [[ -f "$SERVICE_FILE" ]]; then
    systemctl --user --no-pager --lines=60 status clash.service || true
  else
    [[ -x "$CLASH_BIN" ]] && "$CLASH_BIN" -v || true
    echo "未配置 systemd 用户服务。配置目录: $CLASH_DIR"
    print_process_status
    print_port_status
  fi
}

need_cmd uname
need_cmd mkdir
need_cmd head
need_cmd cp

case "$ACTION" in
  install)
    download_clash
    write_config "$SUBSCRIBE_URL"
    test_config
    write_systemd_service
    start_clash
    ;;
  update-config)
    write_config "$SUBSCRIBE_URL"
    test_config
    if command -v systemctl >/dev/null 2>&1 && [[ -f "$SERVICE_FILE" ]]; then
      systemctl --user restart clash.service || true
    fi
    ;;
  start)
    start_clash
    ;;
  stop)
    stop_clash
    ;;
  restart)
    test_config
    if command -v systemctl >/dev/null 2>&1 && [[ -f "$SERVICE_FILE" ]]; then
      systemctl --user restart clash.service
      status_clash
    else
      start_clash
    fi
    ;;
  status)
    status_clash
    ;;
  test)
    test_config
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    die "未知动作: $ACTION"
    ;;
esac
