#!/bin/bash
#
# Mimic 诊断脚本 - 检查 Mimic 服务状态和配置
#

set -e

# 显示帮助信息
show_help() {
  cat << 'EOF'
Mimic 诊断脚本 - 检查 Mimic 服务状态和配置

用法:
  bash diagnose.sh [IFACE]
  bash diagnose.sh -h|--help

参数:
  IFACE       网络接口名称 (默认: eth0)

选项:
  -h, --help  显示此帮助信息并退出

说明:
  此脚本将执行以下诊断检查:
  1. 检查 Mimic 是否已安装
  2. 检查内核模块是否已加载
  3. 检查 mimic 用户是否存在
  4. 检查配置文件是否存在
  5. 检查网络接口是否存在
  6. 测试直接运行 Mimic
  7. 检查 systemd 服务状态

示例:
  # 诊断默认接口 (eth0)
  bash diagnose.sh

  # 诊断指定接口
  bash diagnose.sh ens33

  # 诊断 wlan0 接口
  bash diagnose.sh wlan0

输出说明:
  ✅ 表示检查通过
  ❌ 表示检查失败
  ⚠️  表示警告或需要注意的事项

常见问题:
  1. 内核模块未加载
     解决: modprobe mimic

  2. mimic 用户不存在
     解决: useradd -r -s /usr/sbin/nologin mimic

  3. 配置文件不存在
     解决: bash configure.sh server eth0 5678

  4. 网络接口不存在
     解决: 使用 'ip link show' 查看可用接口

  5. 服务启动失败
     解决: 查看日志 journalctl -xeu mimic@eth0.service

查看日志:
  # 查看服务日志
  journalctl -u mimic@eth0.service -f

  # 查看最近 100 条日志
  journalctl -xeu mimic@eth0.service -n 100

  # 查看内核日志
  dmesg | grep -i mimic

更多信息:
  项目地址: https://github.com/database64128/mimic
  问题反馈: https://github.com/database64128/mimic/issues

EOF
}

# 检查是否需要显示帮助
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  show_help
  exit 0
fi

IFACE=${1:-eth0}

echo "=== Mimic 服务诊断工具 ==="
echo "接口: $IFACE"
echo

echo "=== [1/7] 检查 Mimic 是否已安装 ==="
if ! command -v mimic >/dev/null 2>&1; then
  echo "❌ Mimic 未安装"
  exit 1
else
  echo "✅ Mimic 已安装: $(which mimic)"
  mimic --version 2>/dev/null | head -n1 || echo "⚠️  无法获取版本信息"
fi

echo
echo "=== [2/7] 检查内核模块 ==="
if lsmod | grep -q "^mimic "; then
  echo "✅ 内核模块已加载"
  lsmod | grep mimic
else
  echo "❌ 内核模块未加载"
  echo "尝试加载..."
  if modprobe mimic 2>&1; then
    echo "✅ 内核模块加载成功"
  else
    echo "❌ 内核模块加载失败"
    echo "错误信息："
    modprobe mimic 2>&1 || true
  fi
fi

echo
echo "=== [3/7] 检查 mimic 用户 ==="
if id mimic >/dev/null 2>&1; then
  echo "✅ mimic 用户存在"
  id mimic
else
  echo "❌ mimic 用户不存在"
  echo "尝试创建..."
  if useradd -r -s /usr/sbin/nologin mimic 2>&1; then
    echo "✅ mimic 用户创建成功"
  else
    echo "⚠️  无法创建 mimic 用户（可能需要手动创建）"
  fi
fi

echo
echo "=== [4/7] 检查配置文件 ==="
CONF_FILE="/etc/mimic/${IFACE}.conf"
if [[ -f "$CONF_FILE" ]]; then
  echo "✅ 配置文件存在: $CONF_FILE"
  echo "配置文件内容："
  cat "$CONF_FILE"
  echo
else
  echo "❌ 配置文件不存在: $CONF_FILE"
fi

echo
echo "=== [5/7] 检查网络接口 ==="
if ip link show "$IFACE" >/dev/null 2>&1; then
  echo "✅ 网络接口存在: $IFACE"
  ip link show "$IFACE" | head -n2
else
  echo "❌ 网络接口不存在: $IFACE"
  echo "可用的网络接口："
  ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//'
fi

echo
echo "=== [6/7] 测试直接运行 Mimic ==="
echo "尝试以 root 用户直接运行 Mimic（仅测试，不会启动服务）..."
if [[ -f "$CONF_FILE" ]]; then
  echo "命令: mimic run $IFACE -F $CONF_FILE"
  timeout 3 mimic run "$IFACE" -F "$CONF_FILE" 2>&1 || {
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 124 ]]; then
      echo "⚠️  命令超时（这可能是正常的，因为 Mimic 会持续运行）"
    else
      echo "❌ Mimic 运行失败，退出码: $EXIT_CODE"
      echo "错误信息："
      mimic run "$IFACE" -F "$CONF_FILE" 2>&1 || true
    fi
  }
else
  echo "⚠️  配置文件不存在，跳过测试"
fi

echo
echo "=== [7/7] 检查 systemd 服务状态 ==="
systemctl status mimic@${IFACE}.service --no-pager -l || true

echo
echo "=== 诊断完成 ==="
echo
echo "如果问题仍然存在，请检查："
echo "1. 内核版本是否 >= 6.1"
echo "2. BPF 支持是否启用"
echo "3. 查看完整日志: journalctl -xeu mimic@${IFACE}.service -n 100"
echo "4. 查看内核日志: dmesg | tail -50"

