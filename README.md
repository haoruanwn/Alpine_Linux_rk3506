# Alpine Linux SDK for Rockchip RK3506

  

这是一个深度定制的嵌入式 Linux SDK，旨在为 **Rockchip RK3506** 平台构建 **Alpine Linux** 系统。

本项目基于 Rockchip 原厂 SDK 改造，替换为轻量级的 Alpine RootFS 构建流程。

-----

## 🛠️ 快速开始
本项目仅推荐使用docker进行编译和开发。

### 1\. 安装 Docker

确保你的宿主机安装了 Docker 和 Docker Compose。

### 2\. 注册 QEMU 模拟器 

为了在 x86 机器上 chroot 到 ARM 环境，必须在**宿主机**执行一次以下命令：

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

### 3\. 启动构建容器

```bash
docker compose up -d
docker compose exec alpine_rk3506-builder bash
```

-----

## 🚀 快速开始

### 全编译

在容器内，首先选择你要构建的板型配置。

```bash
builder@fedora:/workspace$ ./build.sh 
Log colors: message notice warning error fatal

Log saved at /workspace/Alpine_Linux_rk3506/output/sessions/2025-12-07_21-11-55
WARN: /workspace/Alpine_Linux_rk3506/output/defconfig not exists
Pick a defconfig:

1. ido_rk3506_b_mipi_nand_defconfig
2. rockchip_rk3502_robot_defconfig
3. rockchip_rk3506_b_evb1_defconfig
4. rockchip_rk3506_g_demo_defconfig
5. rockchip_rk3506_g_evb1_amp_defconfig
6. rockchip_rk3506_g_evb1_defconfig
7. rockchip_rk3506_g_evb1_smp_defconfig
8. vanxoak_rk3506_g_evm_nand_defconfig
Which would you like? [1]: 
```

## ⚙️ 如何定制系统

### 修改默认密码或安装软件

编辑对应的 `alpine-setup-*.sh` 脚本。

每个配置文件都有一个对应的`alpine-setup.sh`脚本，存放在`device/rockchip/.chip/alpine`，通过修改这个脚本即可进行一定程度上的自定义镜像，例如修改root密码、设备名称、开机连接Wi-Fi等


