#!/bin/sh
# common/.chips/rk3506/alpine/alpine-setup-rockchip_rk3502_robot_defconfig.sh
# Board-specific Alpine Linux setup for RK3506/RK3502 Robot variant
# This script is automatically loaded when BOARD_CONFIG=rockchip_rk3502_robot_defconfig

echo "=== Nexus: Starting Alpine Setup (Board: RK3506/RK3502 Robot) ==="

# 1. 配置源 (Mirrors)
echo "Step 1: Setting up mirrors..."
sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
apk update

# 2. 安装基础包 (包括robotics特定的包)
echo "Step 2: Installing base packages..."
apk add openrc util-linux btop bash bash-completion openssh tzdata \
    mdev-conf dhcpcd wpa_supplicant wireless-tools

# Robot variant specific packages (可根据需要扩展)
# apk add python3 py3-requests  # For robot control
# apk add can-utils              # For CAN bus (common in robotics)
# apk add usbutils pciutils      # For hardware debugging

# 3. 配置 OpenRC 和 基础服务
echo "Step 3: Configuring OpenRC..."
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot

# 4. 硬件热插拔与驱动自动加载 (Hardware Hotplug)
echo "Step 4: Configuring Hardware Hotplug..."

# 启用 mdev (Busybox 的 udev 替代品)
rc-update add mdev sysinit

# 配置 mdev 自动加载模块 
# 当内核发现新硬件 ($MODALIAS) 时，自动执行 modprobe 加载驱动
cat > /etc/mdev.conf <<'EOF'
# 基础设备节点权限
null    0:0 666
zero    0:0 666
full    0:0 666
random  0:0 666
urandom 0:0 666
tty     0:0 666
console 0:0 600
ptmx    0:0 666

# 语法: <正则> <用户:组> <权限> <命令>
# $MODALIAS 是内核传递的环境变量，代表设备 ID
$MODALIAS=.* 0:0 660 @modprobe -b "$MODALIAS"
EOF

# 5. 网络配置 (有线自启，无线按需)
echo "Step 5: Configuring Networking..."

mkdir -p /etc/network
cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

# 板载有线网口 1 (自启)
auto eth0
iface eth0 inet dhcp

# 板载有线网口 2 (自启)
auto eth1
iface eth1 inet dhcp

# --- 以下为预留配置，不加 auto，需手动 ifup 开启 ---

# USB 4G/5G 网卡 (通常识别为 eth2 或 usb0)
iface eth2 inet dhcp
iface usb0 inet dhcp

# Wi-Fi (需配合 wpa_supplicant)
iface wlan0 inet dhcp
EOF

# 启用网络服务
rc-update add networking default

# 预配置 Wi-Fi (方便后续使用)
mkdir -p /etc/wpa_supplicant
cat > /etc/wpa_supplicant/wpa_supplicant.conf <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=CN
EOF

# 6. 配置串口 ttyFIQ0 自动登录
echo "Step 6: Configuring Serial Console..."
echo "ttyFIQ0" >> /etc/securetty

# 修改 /etc/inittab，移除VT配置
sed -i '/tty[1-6]/d' /etc/inittab

# 添加 ttyFIQ0 (RK3506 debugging console)
echo "ttyFIQ0::respawn:/sbin/agetty --autologin root ttyFIQ0 vt100" >> /etc/inittab

# 7. 设置主机名 (使用defconfig名作为主机名)
echo "Step 7: Setting hostname..."
BOARD_NAME="${BOARD_CONFIG:-rk3506-robot}"
echo "$BOARD_NAME" > /etc/hostname

# 8. 配置 SSH
echo "Step 8: Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rc-update add sshd default

# 9. 配置时区
echo "Step 9: Configuring Timezone..."
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 10. 修改默认 Shell 为 Bash
echo "Step 10: Setting default shell to Bash..."
sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

# 11. 设置 root 密码 (root:rockchip)
echo "Step 11: Setting root password..."
echo "root:rockchip" | chpasswd

# 12. 重新生成模块依赖
echo "Step 12: Regenerating module dependencies..."
depmod -a

# ====================================================
# RK3506/RK3502 Robot specific configuration
# ====================================================

# 增强系统配置示例 (可根据实际需求调整)
echo "Step 13: Applying RK3506 Robot specific configurations..."

# 示例：添加 robot-specific 环境变量
cat >> /etc/profile <<'EOF'
# RK3506 Robot Configurations
export BOARD_VARIANT="rk3502-robot"
export RK_CHIP="rk3506"

# GPIO/ADC tools (如果需要)
# export PATH=/usr/local/bin/rk-tools:$PATH
EOF

# 示例：预配置日志轮转
mkdir -p /etc/logrotate.d
cat > /etc/logrotate.d/robot <<'EOF'
/var/log/robot/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF

# 创建 robot 日志目录
mkdir -p /var/log/robot

# 示例：系统监控脚本 (可选)
# 创建一个简单的监控服务来记录系统状态
cat > /etc/init.d/robot-monitor <<'EOF'
#!/sbin/openrc-run
# Robot system monitoring service

description="RK3506 Robot System Monitor"
pidfile="/var/run/robot-monitor.pid"
command="/usr/local/sbin/robot-monitor.sh"
command_args="-D"
command_background=yes

depend() {
    after localmount
}
EOF
chmod +x /etc/init.d/robot-monitor

# 创建监控脚本模板
mkdir -p /usr/local/sbin
cat > /usr/local/sbin/robot-monitor.sh <<'EOF'
#!/bin/bash
# Simple robot system monitor
LOG_FILE="/var/log/robot/system.log"

while true; do
    {
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "CPU Temp: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 'N/A')°C"
        echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
        echo "Uptime: $(uptime)"
    } >> "$LOG_FILE" 2>&1
    sleep 300  # 每5分钟记录一次
done
EOF
chmod +x /usr/local/sbin/robot-monitor.sh

# 可选：启用robot-monitor服务
# rc-update add robot-monitor default

# 清理缓存
echo "Cleaning up..."
rm -rf /var/cache/apk/*

echo ""
echo "=========================================="
echo "=== Alpine Setup Complete (RK3506 Robot) ==="
echo "=========================================="
echo "Board Config: ${BOARD_CONFIG:-rk3502-robot}"
echo "Hostname: $(cat /etc/hostname)"
echo "Timezone: $(cat /etc/timezone)"
echo "=========================================="
