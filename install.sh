#!/bin/bash
#
# Mimic 安装脚本 - 自动下载和安装 Mimic
#

set -e

# 显示帮助信息
show_help() {
  cat << 'EOF'
Mimic 安装脚本 - 自动下载和安装 Mimic

用法:
  bash install.sh
  bash install.sh -h|--help

说明:
  此脚本将自动执行以下操作:
  1. 检测系统信息 (系统代号和架构)
  2. 安装必要的依赖 (dkms, curl, wget)
  3. 从 GitHub Releases 下载最新版本的 Mimic
  4. 安装 Mimic 用户态程序
  5. 安装 Mimic 内核模块 (DKMS)
  6. 清理临时文件

支持的系统:
  - Debian 12 (Bookworm)
  - Debian 13 (Trixie)
  - Ubuntu 24.04 (Noble)
  - 其他基于 Debian/Ubuntu 的发行版

支持的架构:
  - amd64 (x86_64)
  - arm64 (aarch64)

要求:
  - 需要 root 权限
  - 需要互联网连接以下载软件包
  - 系统需要支持 DKMS (Dynamic Kernel Module Support)

选项:
  -h, --help  显示此帮助信息并退出

安装后:
  1. 验证安装:
     mimic --version

  2. 配置和启动 Mimic:
     bash configure.sh server eth0 5678

  3. 查看更多配置选项:
     bash configure.sh --help

卸载:
  apt remove --purge mimic mimic-dkms
  apt autoremove

故障排除:
  - 如果下载失败，请检查网络连接
  - 如果 DKMS 编译失败，请确保已安装内核头文件:
    apt install linux-headers-$(uname -r)
  - 查看日志: journalctl -xe

更多信息:
  项目地址: https://github.com/hack3ric/mimic
  问题反馈: https://github.com/hack3ric/mimic/issues

EOF
}

# 检查是否需要显示帮助
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  show_help
  exit 0
fi

echo "=== [1/6] 检测系统信息 ==="

# 自动识别系统 codename（bookworm / trixie / noble）
CODENAME=$(lsb_release -sc 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2)

if [[ -z "$CODENAME" ]]; then
  echo "❌ 无法识别系统代号，请手动设置 CODENAME（bookworm, trixie, noble）"
  exit 1
fi

# 自动识别架构
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

# 标准化架构名称
case "$ARCH" in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64)
    ARCH="arm64"
    ;;
esac

echo "➡️ 检测到系统代号：$CODENAME"
echo "➡️ 检测到架构：$ARCH"

# 获取最新的 release 版本
echo "🔍 获取最新的 Mimic release 版本..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/hack3ric/mimic/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')

if [[ -z "$LATEST_VERSION" ]]; then
  echo "❌ 无法获取最新版本，请检查网络连接"
  exit 1
fi

# 提取版本号（去掉 v 前缀）
VERSION="${LATEST_VERSION#v}"
echo "✅ 最新版本：v${VERSION}"

echo "=== [2/6] 安装依赖 ==="
apt update -y || true
apt install -y dkms curl wget || true

echo "=== [3/6] 下载 Mimic 包 ==="
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

BASE_URL="https://github.com/hack3ric/mimic/releases/download/v${VERSION}"

DOWNLOADED_FILES=()

# 下载函数
download_package() {
  local PACKAGE_TYPE=$1  # "mimic" 或 "mimic-dkms"
  local FOUND=false
  
  # 尝试不同的文件名格式
  local NAME_FORMATS=(
    "${CODENAME}_${PACKAGE_TYPE}_${VERSION}-1_${ARCH}.deb"
    "${CODENAME}_${PACKAGE_TYPE}_${VERSION}_${ARCH}.deb"
  )
  
  for NAME in "${NAME_FORMATS[@]}"; do
    echo "尝试下载：$NAME"
    if wget -q "${BASE_URL}/${NAME}" -O "${NAME}" 2>/dev/null; then
      DOWNLOADED_FILES+=("${NAME}")
      echo "✅ 下载成功：$NAME"
      # 下载校验和
      if wget -q "${BASE_URL}/${NAME}.sha256" -O "${NAME}.sha256" 2>/dev/null; then
        echo "✅ 下载校验和：${NAME}.sha256"
      fi
      FOUND=true
      break
    fi
  done
  
  if [ "$FOUND" = false ]; then
    echo "❌ 无法下载 ${PACKAGE_TYPE} 包"
    return 1
  fi
  return 0
}

# 下载 mimic 主包
download_package "mimic" || {
  echo "❌ 无法下载 mimic 主包"
  echo "请检查 release 页面：https://github.com/hack3ric/mimic/releases/tag/v${VERSION}"
  exit 1
}

# 下载 mimic-dkms 包
download_package "mimic-dkms" || {
  echo "❌ 无法下载 mimic-dkms 包"
  echo "请检查 release 页面：https://github.com/hack3ric/mimic/releases/tag/v${VERSION}"
  exit 1
}

echo "=== [4/6] 校验文件完整性 ==="
for FILE in "${DOWNLOADED_FILES[@]}"; do
  if [[ -f "${FILE}.sha256" ]]; then
    if sha256sum -c "${FILE}.sha256" 2>/dev/null; then
      echo "✅ 校验通过：$FILE"
    else
      echo "❌ 校验失败: $FILE"
      exit 1
    fi
  else
    echo "⚠️  跳过校验：$FILE（无校验和文件）"
  fi
done

echo "=== [5/6] 安装 Mimic ==="
sudo apt install -y ./*_mimic_*.deb ./*_mimic-dkms_*.deb || {
  echo "❌ 安装失败，请检查依赖是否满足"
  exit 1
}

# 清理临时目录
cd /
rm -rf "$WORKDIR"

echo "=== [6/6] 加载 Mimic 内核模块 ==="
modprobe mimic || insmod /lib/modules/$(uname -r)/updates/dkms/mimic.ko 2>/dev/null || {
  echo "⚠️  内核模块加载失败，DKMS 将在下次重启时自动构建"
}

echo 'mimic' > /etc/modules-load.d/mimic.conf 2>/dev/null || true

echo
echo "✅ Mimic 安装完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "版本: v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "下一步：运行配置脚本生成配置文件并启动服务"
echo "  bash configure.sh [mode] [interface] [ports] [remote_ip]"
echo
echo "参数说明："
echo "  mode: server 或 client（默认: server）"
echo "  interface: 网络接口名称（默认: eth0）"
echo "  ports: 端口，支持逗号分隔或范围，如 '5678' 或 '5678,5679' 或 '5678-5680'（默认: 5678）"
echo "  remote_ip: 远端 IP（client 模式必需，默认: 1.2.3.4）"
echo
echo "示例："
echo "  bash configure.sh server eth0 5678"
echo "  bash configure.sh client eth0 5678 192.168.1.100"
