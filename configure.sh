#!/bin/bash
#
# Mimic 配置脚本 - 自动配置和启动 Mimic 服务
#

set -e

# 显示帮助信息
show_help() {
  cat << 'EOF'
Mimic 配置脚本 - 自动配置和启动 Mimic 服务

用法:
  bash configure.sh [MODE] [IFACE] [PORTS] [SERVER_IP/REMOTE_IP]
  bash configure.sh -h|--help

参数:
  MODE            运行模式: server 或 client (默认: server)
  IFACE           网络接口名称 (默认: eth0)
  PORTS           端口号，支持以下格式:
                  - 单个端口: 5678
                  - 多个端口: 5678,5679,5680
                  - 端口范围: 5678-5680
                  - 混合使用: 5678,5680-5682,5690
                  (默认: 5678)
  SERVER_IP       服务端 IP 地址 (服务端模式可选)
                  - 不指定: 自动检测所有 IP (外网+内网, IPv4+IPv6)
                  - 指定: 使用指定的 IP，支持多个 IP，逗号分隔
  REMOTE_IP       远程 IP 地址 (客户端模式必需)
                  - 支持多个 IP 地址，逗号分隔 (IPv4 和 IPv6)

选项:
  -h, --help  显示此帮助信息并退出

服务端模式说明:
  1. 自动检测模式（不指定 SERVER_IP）:
     自动检测服务器的所有 IP 地址，包括:
     - 外网 IPv4 地址 (通过 curl -4 ip.sb 获取)
     - 外网 IPv6 地址 (通过 curl -6 ip.sb 获取)
     - 本地 IPv4 地址 (包括内网地址如 10.x.x.x, 192.168.x.x)
     - 本地 IPv6 地址 (排除本地回环和链接本地地址)
  
  2. 手动指定模式（指定 SERVER_IP）:
     使用您指定的 IP 地址，跳过自动检测
     支持多个 IP 地址，逗号分隔 (IPv4 和 IPv6)
  
  然后为每个 IP 地址和每个端口生成过滤规则。

客户端模式说明:
  客户端模式需要指定要连接的远程 IP 地址。
  支持同时指定多个远程 IP，脚本会为每个 IP 和每个端口生成过滤规则。

示例:

  1. 服务端模式 - 自动检测 IP (推荐)
     bash configure.sh server eth0 5678

  2. 服务端模式 - 自动检测 + 多端口
     bash configure.sh server eth0 "5678,5679,5680"

  3. 服务端模式 - 手动指定单个 IP
     bash configure.sh server eth0 5678 "1.2.3.4"

  4. 服务端模式 - 手动指定多个 IP
     bash configure.sh server eth0 5678 "1.2.3.4,10.0.0.1"

  5. 服务端模式 - 手动指定 IPv4 + IPv6
     bash configure.sh server eth0 "5678-5680" "1.2.3.4,2001:db8::1"

  6. 服务端模式 - 手动指定多 IP + 多端口
     bash configure.sh server eth0 "5678,5679" "1.2.3.4,10.0.0.1,2001:db8::1"

  7. 客户端模式 - 单个远程 IP
     bash configure.sh client eth0 5678 "1.2.3.4"

  8. 客户端模式 - 多个远程 IPv4
     bash configure.sh client eth0 "5678,5679" "1.2.3.4,5.6.7.8"

  9. 客户端模式 - 混合 IPv4 和 IPv6
     bash configure.sh client eth0 5678 "1.2.3.4,2001:db8::1,5.6.7.8"

  10. 客户端模式 - 多端口 + 多 IP
      bash configure.sh client eth0 "5678-5680" "1.2.3.4,5.6.7.8,2001:db8::1"

  11. 使用默认参数 (服务端自动检测, eth0, 端口 5678)
      bash configure.sh

配置文件位置:
  /etc/mimic/${IFACE}.conf

服务管理:
  启动服务: systemctl start mimic@${IFACE}
  停止服务: systemctl stop mimic@${IFACE}
  重启服务: systemctl restart mimic@${IFACE}
  查看状态: systemctl status mimic@${IFACE}
  查看日志: journalctl -u mimic@${IFACE} -f

注意事项:
  - 此脚本需要 root 权限运行
  - 确保 Mimic 已经通过 install.sh 安装
  - 端口参数包含逗号或范围时，需要用引号包裹
  - 多个 IP 地址需要用引号包裹
  - IPv6 地址会自动添加方括号格式 [ipv6]:port

更多信息:
  项目地址: https://github.com/hack3ric/mimic
  运行 'mimic --help' 查看 Mimic 命令行用法

EOF
}

# 检查是否需要显示帮助
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  show_help
  exit 0
fi

### === 用户自定义区域 === ###
MODE=${1:-server}
IFACE=${2:-eth0}
PORTS=${3:-5678}
SERVER_OR_REMOTE_IP=${4:-}  # 服务端或客户端 IP，为空表示服务端自动检测

echo "=== [1/5] 检查 Mimic 是否已安装 ==="
if ! command -v mimic >/dev/null 2>&1; then
  echo "❌ Mimic 未安装，请先运行安装脚本："
  echo "   bash install.sh"
  exit 1
fi

MIMIC_VERSION=$(mimic --version 2>/dev/null | head -n1 || echo "未知版本")
echo "✅ Mimic 已安装：${MIMIC_VERSION}"

echo "=== [2/5] 解析端口输入 ==="
IFS=',' read -r -a PORT_LIST <<< "$PORTS"
EXPANDED_PORTS=()

for P in "${PORT_LIST[@]}"; do
  if [[ "$P" =~ ^[0-9]+-[0-9]+$ ]]; then
    START=${P%-*}
    END=${P#*-}
    for ((i=START; i<=END; i++)); do
      EXPANDED_PORTS+=("$i")
    done
  else
    EXPANDED_PORTS+=("$P")
  fi
done

echo "将监听以下端口: ${EXPANDED_PORTS[*]}"

# 解析 IP 地址
if [ "$MODE" = "client" ]; then
  # 客户端模式：解析远程 IP 地址
  echo "=== [3/5] 解析远程 IP 地址 ==="
  if [ -z "$SERVER_OR_REMOTE_IP" ]; then
    echo "❌ 客户端模式必须指定远程 IP 地址"
    echo "用法: bash configure.sh client eth0 5678 \"1.2.3.4\""
    exit 1
  fi
  IFS=',' read -r -a REMOTE_IP_LIST <<< "$SERVER_OR_REMOTE_IP"
  echo "将连接以下远程 IP: ${REMOTE_IP_LIST[*]}"
elif [ "$MODE" = "server" ] && [ -n "$SERVER_OR_REMOTE_IP" ]; then
  # 服务端模式 + 手动指定 IP：解析服务端 IP 地址
  echo "=== [3/5] 解析服务端 IP 地址 ==="
  IFS=',' read -r -a SERVER_IP_LIST <<< "$SERVER_OR_REMOTE_IP"
  echo "将使用以下服务端 IP: ${SERVER_IP_LIST[*]}"
fi

echo "=== [$([ "$MODE" = "client" ] && echo "4" || echo "3")/5] 生成 Mimic 配置文件 ==="
mkdir -p /etc/mimic

CONF_FILE="/etc/mimic/${IFACE}.conf"

cat > "$CONF_FILE" <<EOF
log.verbosity = info
link_type = eth
xdp_mode = skb
use_libxdp = false
max_window = false
EOF

if [ "$MODE" = "server" ]; then
  # 检查是否手动指定了 IP
  if [ -n "$SERVER_OR_REMOTE_IP" ]; then
    # 手动指定模式：使用用户提供的 IP 地址
    echo "使用手动指定的服务端 IP 地址（跳过自动检测）"
    
    # 分离 IPv4 和 IPv6 地址
    ALL_IPV4=""
    ALL_IPV6=""
    
    for ip in "${SERVER_IP_LIST[@]}"; do
      if [[ "$ip" =~ : ]]; then
        # IPv6 地址
        if [ -z "$ALL_IPV6" ]; then
          ALL_IPV6="$ip"
        else
          ALL_IPV6="$ALL_IPV6"$'\n'"$ip"
        fi
      else
        # IPv4 地址
        if [ -z "$ALL_IPV4" ]; then
          ALL_IPV4="$ip"
        else
          ALL_IPV4="$ALL_IPV4"$'\n'"$ip"
        fi
      fi
    done
  else
    # 自动检测模式：检测所有可用的 IP 地址
    echo "自动检测服务器 IP 地址..."
    
    # 获取真实外网 IPv4 地址
    echo "正在获取外网 IPv4 地址..."
    PUBLIC_IPV4=$(curl -4 -s --connect-timeout 5 --max-time 10 ip.sb 2>/dev/null || true)
    if [ -n "$PUBLIC_IPV4" ] && [[ "$PUBLIC_IPV4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "  外网 IPv4: $PUBLIC_IPV4"
    else
      PUBLIC_IPV4=""
    fi
    
    # 获取真实外网 IPv6 地址
    echo "正在获取外网 IPv6 地址..."
    PUBLIC_IPV6=$(curl -6 -s --connect-timeout 5 --max-time 10 ip.sb 2>/dev/null || true)
    if [ -n "$PUBLIC_IPV6" ] && [[ "$PUBLIC_IPV6" =~ : ]]; then
      echo "  外网 IPv6: $PUBLIC_IPV6"
    else
      PUBLIC_IPV6=""
    fi
    
    # 获取所有本地 IPv4 地址（排除 127.0.0.1）
    IPV4_ADDRS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' || true)
    
    # 获取所有本地 IPv6 地址（排除 ::1 和 fe80 本地链接地址）
    IPV6_ADDRS=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-f:]+' | grep -v '^::1$' | grep -v '^fe80:' || true)
    
    # 合并外网 IPv4 和本地 IPv4 地址（去重）
    ALL_IPV4=""
    if [ -n "$PUBLIC_IPV4" ]; then
      ALL_IPV4="$PUBLIC_IPV4"
    fi
    if [ -n "$IPV4_ADDRS" ]; then
      if [ -n "$ALL_IPV4" ]; then
        ALL_IPV4="$ALL_IPV4"$'\n'"$IPV4_ADDRS"
      else
        ALL_IPV4="$IPV4_ADDRS"
      fi
    fi
    # 去重
    ALL_IPV4=$(echo "$ALL_IPV4" | sort -u)
    
    # 合并外网 IPv6 和本地 IPv6 地址（去重）
    ALL_IPV6=""
    if [ -n "$PUBLIC_IPV6" ]; then
      ALL_IPV6="$PUBLIC_IPV6"
    fi
    if [ -n "$IPV6_ADDRS" ]; then
      if [ -n "$ALL_IPV6" ]; then
        ALL_IPV6="$ALL_IPV6"$'\n'"$IPV6_ADDRS"
      else
        ALL_IPV6="$IPV6_ADDRS"
      fi
    fi
    # 去重
    ALL_IPV6=$(echo "$ALL_IPV6" | sort -u)
  fi
  
  # 为每个 IPv4 地址和每个端口生成过滤规则
  if [ -n "$ALL_IPV4" ]; then
    echo "配置 IPv4 地址:"
    while IFS= read -r ip; do
      if [ -n "$ip" ]; then
        echo "  - $ip"
        for port in "${EXPANDED_PORTS[@]}"; do
          echo "filter = local=${ip}:${port}" >> "$CONF_FILE"
        done
      fi
    done <<< "$ALL_IPV4"
  fi
  
  # 为每个 IPv6 地址和每个端口生成过滤规则
  if [ -n "$ALL_IPV6" ]; then
    echo "配置 IPv6 地址:"
    while IFS= read -r ip; do
      if [ -n "$ip" ]; then
        echo "  - $ip"
        for port in "${EXPANDED_PORTS[@]}"; do
          echo "filter = local=[${ip}]:${port}" >> "$CONF_FILE"
        done
      fi
    done <<< "$ALL_IPV6"
  fi
  
  # 如果没有找到任何地址，回退到 0.0.0.0
  if [ -z "$ALL_IPV4" ] && [ -z "$ALL_IPV6" ]; then
    echo "⚠️  未检测到任何 IP 地址，使用 0.0.0.0"
    for port in "${EXPANDED_PORTS[@]}"; do
      echo "filter = local=0.0.0.0:${port}" >> "$CONF_FILE"
    done
  fi
else
  # 客户端模式：为每个远程 IP 和每个端口生成过滤规则
  for remote_ip in "${REMOTE_IP_LIST[@]}"; do
    # 判断是 IPv6 还是 IPv4
    if [[ "$remote_ip" =~ : ]]; then
      # IPv6 地址需要用方括号包裹
      for port in "${EXPANDED_PORTS[@]}"; do
        echo "filter = remote=[${remote_ip}]:${port}" >> "$CONF_FILE"
      done
    else
      # IPv4 地址
      for port in "${EXPANDED_PORTS[@]}"; do
        echo "filter = remote=${remote_ip}:${port}" >> "$CONF_FILE"
      done
    fi
  done
fi

echo "配置文件已生成：$CONF_FILE"
cat "$CONF_FILE"

echo "=== [$([ "$MODE" = "client" ] && echo "5" || echo "4")/5] 启动 Mimic systemd 服务 ==="
systemctl daemon-reexec || true
systemctl daemon-reload || true
systemctl enable mimic@${IFACE}.service || true
systemctl restart mimic@${IFACE}.service || true

sleep 1
systemctl status mimic@${IFACE} --no-pager || true

echo "=== [$([ "$MODE" = "client" ] && echo "6" || echo "5")$([ "$MODE" = "client" ] && echo "/6" || echo "/5")] 防火墙规则（TCP+UDP） ==="
for port in "${EXPANDED_PORTS[@]}"; do
  iptables -A INPUT -p tcp --dport ${port} -j ACCEPT || true
  iptables -A INPUT -p udp --dport ${port} -j ACCEPT || true
done

echo
echo "✅ Mimic 配置完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "模式: $MODE"
echo "接口: $IFACE"
echo "端口: ${EXPANDED_PORTS[*]}"
if [ "$MODE" = "client" ]; then
  echo "远端 IP: ${REMOTE_IP_LIST[*]}"
elif [ "$MODE" = "server" ] && [ -n "$SERVER_OR_REMOTE_IP" ]; then
  echo "服务端 IP: ${SERVER_IP_LIST[*]} (手动指定)"
elif [ "$MODE" = "server" ]; then
  echo "服务端 IP: 自动检测"
fi
echo "配置文件: $CONF_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "现在可以启动 Hysteria（server 或 client）在相同端口上。"
echo "运行 'mimic --help' 查看命令行用法。"
echo "运行 'systemctl status mimic@${IFACE}' 查看服务状态。"
echo "运行 'systemctl restart mimic@${IFACE}' 重启服务。"
echo "运行 'systemctl stop mimic@${IFACE}' 停止服务。"

