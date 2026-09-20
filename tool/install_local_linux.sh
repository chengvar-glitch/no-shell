#!/usr/bin/env bash
# 本机安装 NoShell（Linux 桌面）：与 release.yml 的 deb 布局保持一致——
# 程序装到 /opt/noshell，/usr/local/bin/noshell 软链，图标进 hicolor 主题，
# 桌面入口进 /usr/share/applications。
#
# 用法：tool/install_local_linux.sh [sudo密码]
#   密码经 stdin 交给 `sudo -S -v` 校验并缓存，之后所有 sudo 调用走缓存，
#   命令行参数（会出现在 ps 输出里）不是首选，仅在需要时使用。
# 已是 root 时不需要密码。
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$PROJECT_ROOT/build/linux/x64/release/bundle"
APP_DIR=/opt/noshell
BIN_LINK=/usr/local/bin/noshell
DESKTOP_FILE=/usr/share/applications/noshell.desktop
ICON_SRC="$PROJECT_ROOT/icon/png/linux"

[[ -x "$SRC/NoShell" ]] || {
  echo "找不到构建产物：$SRC/NoShell" >&2
  echo "先执行：flutter build linux --release" >&2
  exit 1
}

if [[ ${EUID} -ne 0 ]]; then
  # 密码只经 stdin 交给 `sudo -S -v`（校验并缓存凭据）：不进命令行参数、
  # 不落任何文件；之后所有 sudo 调用都走这份缓存。
  if [[ $# -ge 1 ]]; then
    printf '%s\n' "$1" | sudo -S -v
  elif [[ -t 0 ]]; then
    sudo -v
  else
    sudo -S -v
  fi
fi
as_root() {
  if [[ ${EUID} -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

echo "== 安装到 $APP_DIR =="
as_root install -d -m 755 "$APP_DIR.new"
as_root cp -R "$SRC/." "$APP_DIR.new/"
as_root chmod 755 "$APP_DIR.new/NoShell"
# 先整份铺好再原子替换：避免替换过程中用户正好启动，读到半份程序。
as_root rm -rf "$APP_DIR.old"
[[ -d "$APP_DIR" ]] && as_root mv "$APP_DIR" "$APP_DIR.old"
as_root mv "$APP_DIR.new" "$APP_DIR"
as_root rm -rf "$APP_DIR.old"

echo "== 命令行入口 =="
as_root ln -sfn "$APP_DIR/NoShell" "$BIN_LINK"

echo "== 图标（hicolor 主题）=="
for n in 16 24 32 48 64 128 256 512; do
  as_root install -Dm644 "$ICON_SRC/noshell-$n.png" \
    "/usr/share/icons/hicolor/${n}x${n}/apps/noshell.png"
done

echo "== 桌面入口 =="
as_root tee "$DESKTOP_FILE" >/dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=NoShell
Comment=SSH 终端与 SFTP 文件管理
Exec=/opt/noshell/NoShell
Icon=noshell
Terminal=false
StartupWMClass=com.noshell
StartupNotify=true
Categories=Network;RemoteAccess;
DESKTOP
as_root chmod 644 "$DESKTOP_FILE"

echo "== 刷新桌面数据库 =="
as_root update-desktop-database /usr/share/applications 2>/dev/null || true
as_root gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

echo
echo "安装完成："
echo "  程序    $APP_DIR/NoShell"
echo "  入口    $BIN_LINK"
echo "  桌面项  $DESKTOP_FILE（应用列表里搜 NoShell）"
