#!/bin/bash -e

# ==========================================================
# Alpine Linux Builder with Kernel Modules
# ==========================================================

# Cleanup mounts on exit (trap)
cleanup_mounts()
{
    local rootfs_dir="$1"
    [ -z "$rootfs_dir" ] && return 0

    # Try to unmount in reverse order
    for mp in dev/pts dev sys proc; do
        if mountpoint -q "$rootfs_dir/$mp" 2>/dev/null; then
            sudo umount "$rootfs_dir/$mp" 2>/dev/null || true
        fi
    done
}

build_alpine()
{
    local image_dir="$1"
    image_dir="${image_dir:-$RK_OUTDIR/alpine/images}"

    message "=========================================="
    message "          Start building Alpine Linux     "
    message "=========================================="

    local fs_type="${RK_ROOTFS_TYPE:-ubi}"
    local rootfs_img="$image_dir/rootfs.$fs_type"
    local rootfs_target="$RK_OUTDIR/alpine/target"
    # 这里根据环境选择了 armv7
    local alpine_url="https://mirrors.aliyun.com/alpine/v3.19/releases/armv7/alpine-minirootfs-3.19.1-armv7.tar.gz"
    local alpine_tar="$RK_SDK_DIR/alpine/alpine-minirootfs.tar.gz"

    message "Target RootFS Image: $rootfs_img"
    message "Target RootFS Directory: $rootfs_target"

    mkdir -p "$image_dir"
    rm -f "$rootfs_img"

    # Step 1: Download Alpine Mini RootFS if not present
    if [ ! -f "$alpine_tar" ]; then
        notice "Downloading Alpine Mini RootFS (armv7)..."
        if ! wget -q -O "$alpine_tar" "$alpine_url"; then
            warning "Failed to download from Aliyun mirror, trying primary CDN..."
            alpine_url="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/armv7/alpine-minirootfs-3.19.1-armv7.tar.gz"
            if ! wget -q -O "$alpine_tar" "$alpine_url"; then
                error "Failed to download Alpine rootfs from both mirrors"
                return 1
            fi
        fi
    fi

    # Step 2: Extract RootFS with sudo
    notice "Extracting Alpine RootFS..."
    sudo rm -rf "$rootfs_target"
    mkdir -p "$rootfs_target"
    if ! sudo tar -xzf "$alpine_tar" -C "$rootfs_target"; then
        error "Failed to extract Alpine rootfs"
        return 1
    fi

    # Step 3: Prepare QEMU static binary
    local qemu_bin
    if qemu_bin=$(which qemu-arm-static 2>/dev/null); then
        notice "Found QEMU ARM static: $qemu_bin"
        sudo mkdir -p "$rootfs_target/usr/bin"
        sudo cp "$qemu_bin" "$rootfs_target/usr/bin/" 2>/dev/null || true
    else
        # Fallback for Ubuntu/Debian common path
        if [ -f "/usr/bin/qemu-arm-static" ]; then
             notice "Found QEMU ARM static at /usr/bin/qemu-arm-static"
             sudo mkdir -p "$rootfs_target/usr/bin"
             sudo cp "/usr/bin/qemu-arm-static" "$rootfs_target/usr/bin/"
        else
             warning "qemu-arm-static not found - chroot configuration will be limited"
        fi
    fi

    # Step 4: Mount system directories
    notice "Mounting system directories for chroot configuration..."
    trap "cleanup_mounts '$rootfs_target'" EXIT

    sudo mount -t proc /proc "$rootfs_target/proc" 2>/dev/null || true
    sudo mount -t sysfs /sys "$rootfs_target/sys" 2>/dev/null || true
    sudo mount --bind /dev "$rootfs_target/dev" 2>/dev/null || true
    sudo mount --bind /dev/pts "$rootfs_target/dev/pts" 2>/dev/null || true
    sudo cp /etc/resolv.conf "$rootfs_target/etc/resolv.conf" 2>/dev/null || true

    # Run setup script
    if [ -f "$RK_SCRIPTS_DIR/alpine-setup.sh" ]; then
        sudo mkdir -p "$rootfs_target/tmp"
        sudo cp "$RK_SCRIPTS_DIR/alpine-setup.sh" "$rootfs_target/tmp/"
        
        notice "Running Alpine setup script in chroot environment..."
        if sudo chroot "$rootfs_target" /bin/sh /tmp/alpine-setup.sh; then
            notice "Alpine chroot setup completed successfully"
        else
            warning "Alpine chroot setup encountered some errors (non-fatal)"
        fi
        sudo rm -f "$rootfs_target/tmp/alpine-setup.sh"
    else
        warning "alpine-setup.sh not found in $RK_SCRIPTS_DIR"
    fi

    # ==========================================
    # Step 4.5: Install Kernel Modules
    # ==========================================
    if [ -d "$RK_SDK_DIR/kernel" ]; then
        notice "Installing Kernel Modules to RootFS..."
        
        local cc_path="$RK_SDK_DIR/prebuilts/gcc/linux-x86/arm/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-"
        
        if [ -x "${cc_path}gcc" ]; then
            # Execute install with detailed output
            # 使用 sudo 确保有权限写入 rootfs
            notice "Cross compiler: $cc_path"
            notice "Target RootFS: $rootfs_target"
            notice "Running: make -C $RK_SDK_DIR/kernel ARCH=arm CROSS_COMPILE=$cc_path INSTALL_MOD_PATH=$rootfs_target modules_install"
            notice "=================================================="
            
            if sudo make -C "$RK_SDK_DIR/kernel" \
                ARCH="arm" \
                CROSS_COMPILE="$cc_path" \
                INSTALL_MOD_PATH="$rootfs_target" \
                modules_install; then
                
                notice "=================================================="
                notice "Kernel modules installed successfully!"
                
                # Show what was installed
                notice "Modules installed in: $rootfs_target/lib/modules/"
                if [ -d "$rootfs_target/lib/modules" ]; then
                    sudo find "$rootfs_target/lib/modules" -name "*.ko" | head -20 | while read ko; do
                        notice "  - $ko"
                    done
                    local total_ko=$(sudo find "$rootfs_target/lib/modules" -name "*.ko" | wc -l)
                    notice "  (Total: $total_ko kernel modules)"
                fi
                
                # Clean up symlinks
                notice "Cleaning up kernel module symlinks (build/source)..."
                sudo find "$rootfs_target/lib/modules" -type l -name "build" -delete 2>/dev/null || true
                sudo find "$rootfs_target/lib/modules" -type l -name "source" -delete 2>/dev/null || true
                notice "Module cleanup completed."
            else
                error "Kernel modules install command failed!"
                return 1
            fi
        else
            error "Cross compiler not found at $cc_path"
            warning "Skipping kernel modules install."
        fi
    else
        warning "Kernel source directory not found at $RK_SDK_DIR/kernel"
    fi
    # ==========================================

    # Cleanup qemu binary and mounts (handled by trap too, but good to be explicit)
    sudo rm -f "$rootfs_target/usr/bin/qemu-arm-static" 2>/dev/null || true
    cleanup_mounts "$rootfs_target"

    # ==========================================
    # Step 5: Pack RootFS into Real UBI Image
    # ==========================================
    notice "Packing Alpine RootFS into UBI image..."

    # 1. 定义 NAND 参数 (根据你的 log 中 oem 分区的参数提取)
    # LEB size: 126976, PEB size: 131072, min. I/O: 2048
    local LEB_SIZE=126976
    local MIN_IO_SIZE=2048
    local MAX_LEB_CNT=2048 # 给 rootfs 足够大的空间

    # 2. 生成 ubinize.cfg 配置文件
    cat > "$image_dir/ubinize.cfg" <<EOF
[ubifs]
mode=ubi
image=$image_dir/rootfs.ubifs
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
EOF

    # 3. 制作 UBIFS (文件系统层)
    # 注意：需要 sudo 才能读取 rootfs_target 中的 root 权限文件
    notice "Running mkfs.ubifs..."
    if sudo mkfs.ubifs -r "$rootfs_target" \
        -m $MIN_IO_SIZE \
        -e $LEB_SIZE \
        -c $MAX_LEB_CNT \
        -o "$image_dir/rootfs.ubifs"; then
        notice "UBIFS generated successfully."
    else
        error "Failed to generate UBIFS!"
        return 1
    fi

    # 4. 制作 UBI 镜像 (Flash 层，包含磨损均衡头)
    notice "Running ubinize..."
    if ubinize -o "$rootfs_img" \
        -m $MIN_IO_SIZE \
        -p 128KiB \
        "$image_dir/ubinize.cfg"; then
        notice "UBI image generated successfully: $rootfs_img"
    else
        error "Failed to generate UBI image!"
        return 1
    fi
    
    # 清理中间文件
    rm -f "$image_dir/rootfs.ubifs" "$image_dir/ubinize.cfg"

    # 同时也生成一个 ext4 镜像
    if command -v mkfs.ext4 >/dev/null 2>&1; then
        notice "Generating ext4 image for backup..."
        dd if=/dev/zero of="$image_dir/rootfs.ext4" bs=1M count=256 status=none
        sudo mkfs.ext4 -L "alpine_root" -d "$rootfs_target" "$image_dir/rootfs.ext4" >/dev/null 2>&1 || true
    fi

    # 检查文件生成情况
    if [ ! -s "$rootfs_img" ]; then
        error "Failed to create $rootfs_img (File is empty or missing)"
        return 1
    fi

    notice "Alpine RootFS prepared:"
    notice "  - Target directory: $rootfs_target"
    notice "  - Image file: $rootfs_img"
    notice "  - Image size: $(du -h "$rootfs_img" | cut -f1)"

    finish_build build_alpine $@
}

usage_hook()
{
    usage_oneline "rootfs" "build the Alpine placeholder rootfs"
    usage_oneline "alpine" "alias of rootfs"
}

clean_hook()
{
    # Use sudo for Alpine RootFS directories (they're owned by root from chroot operations)
    if [ -d "$RK_OUTDIR/alpine" ]; then
        sudo rm -rf "$RK_OUTDIR/alpine"
    fi
    rm -rf "$RK_OUTDIR/rootfs"
    rm -rf "$RK_FIRMWARE_DIR/rootfs.img"
}

INIT_CMDS=""
PRE_BUILD_CMDS=""
BUILD_CMDS="rootfs alpine"

build_hook()
{
    check_config RK_ROOTFS || false

    ROOTFS_IMG=rootfs.${RK_ROOTFS_TYPE:-ubi}
    ROOTFS_DIR="$RK_OUTDIR/alpine"
    IMAGE_DIR="$ROOTFS_DIR/images"

    message "=========================================="
    message "          Start building rootfs(alpine)"
    message "=========================================="

    if [ -d "$ROOTFS_DIR" ]; then
        sudo rm -rf "$ROOTFS_DIR"
    fi
    rm -rf "$RK_OUTDIR/rootfs"
    mkdir -p "$IMAGE_DIR"
    ln -rsf "$ROOTFS_DIR" "$RK_OUTDIR/rootfs"

    touch "$ROOTFS_DIR/.stamp_build_start"
    build_alpine "$IMAGE_DIR"
    touch "$ROOTFS_DIR/.stamp_build_finish"

    # 强制豁免逻辑
    if [ -f "$IMAGE_DIR/rootfs.ubi" ]; then
         ln -rsf "$IMAGE_DIR/rootfs.ubi" "$RK_FIRMWARE_DIR/rootfs.img"
    elif [ -f "$IMAGE_DIR/rootfs.ext4" ]; then
         ln -rsf "$IMAGE_DIR/rootfs.ext4" "$RK_FIRMWARE_DIR/rootfs.img"
    else
         error "No rootfs image generated!"
         exit 1
    fi
    
    finish_build build_rootfs $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "${1:-rootfs}" in
    rootfs|alpine) build_hook $@ ;;
    *) usage_hook ;;
esac
