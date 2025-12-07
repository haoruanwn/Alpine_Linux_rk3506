#!/bin/sh
# device/rockchip/common/scripts/alpine-setup.sh
# 参考自：「当幸狐来敲门」适配Alpine Linux下篇--适配Alpine Linux的详细步骤 https://bbs.eeworld.com.cn/thread-1259967-1-1.html

echo "=== Nexus: Starting Generic Alpine Setup ==="

# 1. 配置国内源
sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
apk update

# 2. 安装基础系统包
# mdev-conf: 热插拔支持
# dhcpcd: 稳定的 DHCP 客户端
# ethtool/util-linux: 基础工具
apk add openrc util-linux bash bash-completion openssh tzdata \
    mdev-conf dhcpcd wpa_supplicant wireless-tools ethtool

# 3. 配置 OpenRC 基础挂载服务
echo "Configuring OpenRC Core Services..."
rc-update add devfs sysinit
rc-update add procfs sysinit
rc-update add sysfs sysinit

# 4. 启用 mdev (硬件热插拔)
rc-update add mdev sysinit

# 5. 启用其他基础服务
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add syslog boot

# 配置 mdev 自动加载内核模块
# 逻辑：当内核发现硬件 ($MODALIAS) 时，自动调用 modprobe 加载对应 ko
# 覆盖默认配置以确保生效
cat > /etc/mdev.conf <<EOF
# 基础设备节点权限
null    0:0 666
zero    0:0 666
full    0:0 666
random  0:0 666
urandom 0:0 666
tty     0:0 666
console 0:0 600
ptmx    0:0 666


# 匹配所有带 modalias 的事件 -> 加载驱动
\$MODALIAS=.* 0:0 660 @modprobe -b "\$MODALIAS"
EOF

网络配置 (有线自启)
echo "Configuring Networking (Dual Ethernet)..."

# 生成静态网络配置
# auto: 开机自启
# allow-hotplug: 插线即用
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# 板载网口 1 (默认开启 DHCP)
auto eth0
iface eth0 inet dhcp

# 板载网口 2 (默认开启 DHCP)
auto eth1
iface eth1 inet dhcp
EOF

# 启用网络服务
rc-update add networking boot

echo "Fixing inittab for Embedded System..."

# 1. 备份原始 inittab
cp /etc/inittab /etc/inittab.bak

# 2. 清理 tty1-tty6 的配置
sed -i '/tty[1-6]::respawn/d' /etc/inittab

# 3. 确保串口 (ttyFIQ0) 存在并允许 root 自动登录
# 注意：Rockchip 默认串口通常是 ttyFIQ0 或 ttyS2
sed -i '/ttyFIQ0/d' /etc/inittab
sed -i '/ttyS2/d' /etc/inittab

# 添加 ttyFIQ0 配置
echo "ttyFIQ0::respawn:/sbin/agetty --autologin root --noclear ttyFIQ0 vt100" >> /etc/inittab

# 允许 root 从串口登录
echo "ttyFIQ0" >> /etc/securetty

# 预配置 Wi-Fi 目录
mkdir -p /etc/wpa_supplicant
echo "ctrl_interface=/var/run/wpa_supplicant" > /etc/wpa_supplicant/wpa_supplicant.conf
echo "update_config=1" >> /etc/wpa_supplicant/wpa_supplicant.conf

# 系统杂项配置

# 设置主机名
echo "rk3506" > /etc/hostname

# 允许 Root SSH 登录
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
rc-update add sshd default

# 设置时区 (上海)
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 设置 root 默认 Shell 为 bash
sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

# 设置默认密码 
echo "root:1234" | chpasswd

# 刷新模块依赖
depmod -a

echo "=== Generic Setup Complete ==="