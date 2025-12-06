#!/bin/sh
# device/rockchip/common/scripts/alpine-setup.sh
# 参考自：「当幸狐来敲门」适配Alpine Linux下篇--适配Alpine Linux的详细步骤 https://bbs.eeworld.com.cn/thread-1259967-1-1.html

# 1. 修改源
echo "Setting up mirrors..."
sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
apk update

# 2. 安装基础软件
echo "Installing base packages..."
apk add openrc util-linux btop bash bash-completion openssh tzdata

# 3. 配置 OpenRC 和 串口
echo "Configuring OpenRC..."
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot

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

auto eth0
iface eth0 inet dhcp
EOF
rc-update add networking default

# 设置主机名
echo "rk3506" > /etc/hostname

# 5. 配置 SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rc-update add sshd default

# 6. 配置时区
echo "Configuring Timezone..."
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 7. 修改默认 Shell 为 Bash
sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

# 8. 设置 root 密码，这里设置为 1234
echo "root:1234" | chpasswd

# 清理缓存
rm -rf /var/cache/apk/*

echo "Alpine setup complete!"