#!/bin/sh
# device/rockchip/.chips/rk3506/alpine/alpine-setup-ido_rk3506_b_mipi_nand_defconfig.sh
# 参考自：「当幸狐来敲门」适配Alpine Linux下篇--适配Alpine Linux的详细步骤 https://bbs.eeworld.com.cn/thread-1259967-1-1.html

echo "=== IDO Board Setup: Starting ==="

# 1. 修改源
echo "Setting up mirrors..."
sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
apk update

# 2. 安装基础软件
echo "Installing base packages..."
apk add openrc util-linux btop bash bash-completion openssh tzdata dhcpcd mdev-conf

# 3. 配置 OpenRC 和 串口
echo "Configuring OpenRC..."
rc-update add devfs sysinit
rc-update add procfs sysinit
rc-update add sysfs sysinit
# 启用 mdev 服务，确保 /dev 目录被正确填充
rc-update add mdev sysinit

# 配置串口 ttyFIQ0 自动登录
echo "Configuring Serial Console..."
echo "ttyFIQ0" >> /etc/securetty
# 修改 /etc/inittab 
sed -i '/tty1/d' /etc/inittab
sed -i '/tty2/d' /etc/inittab
sed -i '/tty3/d' /etc/inittab
sed -i '/tty4/d' /etc/inittab
sed -i '/tty5/d' /etc/inittab
sed -i '/tty6/d' /etc/inittab
# 添加 ttyFIQ0
echo "ttyFIQ0::respawn:/sbin/agetty --autologin root ttyFIQ0 vt100" >> /etc/inittab

# 4. 配置网络 
echo "Configuring Network..."
mkdir -p /etc/network
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# 板载网口 1
auto eth0
iface eth0 inet dhcp

# 板载网口 2 (新增)
auto eth1
iface eth1 inet dhcp
EOF
rc-update add networking boot

# 5. 配置驱动加载策略 
echo "Configuring Kernel Module Loading..."

# 将核心驱动写入 /etc/modules，确保在 networking 服务启动前，网卡已经就绪
cat > /etc/modules <<EOF
# --- Ethernet (RK3506) ---
# 必须按顺序加载，否则可能识别不到
stmmac
stmmac_platform
dwmac_rockchip
motorcomm

# --- USB (Optional) ---
phy_rockchip_inno_usb2
dwc2

# --- Wireless (Optional) ---
rfkill_rk
EOF

# 启用 modules 服务 (它会在 boot 阶段极早运行)
rc-update add modules boot

# B. 动态热插拔：用于启动后插入的设备
# 保持之前的 mdev 扫描逻辑，作为补充
mkdir -p /etc/local.d
cat > /etc/local.d/load_modules.start << 'EOF'
#!/bin/sh
echo "Nexus: Scanning for remaining hardware drivers..."
mdev -s
find /sys -name modalias -type f -exec cat '{}' + | sort -u | xargs -n1 modprobe -b -q 2>/dev/null
EOF
chmod +x /etc/local.d/load_modules.start
rc-update add local default

# 设置主机名
echo "ido-rk3506" > /etc/hostname

# 6. 配置 SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rc-update add sshd default

# 7. 配置时区
echo "Configuring Timezone..."
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 8. 修改默认 Shell 为 Bash
sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

# 9. 设置 root 密码
echo "root:1234" | chpasswd

# 10. 重新生成依赖 (防止 modprobe 找不到 ko)
depmod -a

# 清理缓存
rm -rf /var/cache/apk/*

echo "Alpine setup complete!"