#!/bin/bash -e

# Cleanup mounts on exit (trap)
cleanup_mounts()
{
	local rootfs_dir="$1"
	[ -z "$rootfs_dir" ] && return 0

	# Try to unmount in reverse order
	for mp in dev/pts dev sys proc; do
		if mountpoint -q "$rootfs_dir/$mp" 2>/dev/null; then
			umount "$rootfs_dir/$mp" 2>/dev/null || true
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
    local alpine_url="https://mirrors.aliyun.com/alpine/v3.19/releases/armv7/alpine-minirootfs-3.19.1-armv7.tar.gz"
    local alpine_tar="$RK_SDK_DIR/alpine-minirootfs.tar.gz"

    message "Target RootFS Image: $rootfs_img"
    message "Target RootFS Directory: $rootfs_target"

    mkdir -p "$image_dir" "$rootfs_target"
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

    # Step 2: Extract RootFS
    notice "Extracting Alpine RootFS..."
    rm -rf "$rootfs_target"
    mkdir -p "$rootfs_target"
    if ! tar -xzf "$alpine_tar" -C "$rootfs_target"; then
        error "Failed to extract Alpine rootfs"
        return 1
    fi

    # Step 3: Prepare QEMU static binary for ARM emulation
    local qemu_bin
    if qemu_bin=$(which qemu-arm-static 2>/dev/null); then
        notice "Found QEMU ARM static: $qemu_bin"
        mkdir -p "$rootfs_target/usr/bin"
        cp "$qemu_bin" "$rootfs_target/usr/bin/" 2>/dev/null || true
    else
        warning "qemu-arm-static not found - chroot configuration will be limited"
        warning "Install qemu-user-static to enable full Alpine customization"
        # Even without qemu, we can still create a placeholder image
    fi

    # Step 4: Try to mount system directories and run setup script
    if mountpoint -q / 2>/dev/null; then
        # We're running in a capable environment
        notice "Mounting system directories for chroot configuration..."

        # Setup trap to cleanup mounts on exit
        trap "cleanup_mounts '$rootfs_target'" EXIT

        # Mount required filesystems
        mount -t proc /proc "$rootfs_target/proc" 2>/dev/null || true
        mount -t sysfs /sys "$rootfs_target/sys" 2>/dev/null || true
        mount -o bind /dev "$rootfs_target/dev" 2>/dev/null || true
        mount -o bind /dev/pts "$rootfs_target/dev/pts" 2>/dev/null || true

        # Copy DNS configuration for networking
        cp /etc/resolv.conf "$rootfs_target/etc/resolv.conf" 2>/dev/null || true

        # Copy setup script
        if [ -f "$RK_SCRIPTS_DIR/alpine-setup.sh" ]; then
            mkdir -p "$rootfs_target/tmp"
            cp "$RK_SCRIPTS_DIR/alpine-setup.sh" "$rootfs_target/tmp/"
            
            notice "Running Alpine setup script in chroot environment..."
            if chroot "$rootfs_target" /bin/sh /tmp/alpine-setup.sh; then
                notice "Alpine chroot setup completed successfully"
            else
                warning "Alpine chroot setup encountered some errors (non-fatal)"
            fi
            rm -f "$rootfs_target/tmp/alpine-setup.sh"
        fi

        # Cleanup qemu binary
        rm -f "$rootfs_target/usr/bin/qemu-arm-static" 2>/dev/null || true

        # Cleanup will be called by trap
    else
        notice "Skipping chroot configuration (not in capable environment)"
        notice "Creating basic Alpine rootfs placeholder..."
    fi

    # Step 5: Create placeholder image(s)
    case "$fs_type" in
        ubi)
            notice "Creating UBI placeholder image..."
            dd if=/dev/zero of="$rootfs_img" bs=1M count=64 status=none
            ;;
        ext4)
            notice "Creating ext4 placeholder image..."
            dd if=/dev/zero of="$rootfs_img" bs=1M count=64 status=none
            if command -v mkfs.ext4 >/dev/null 2>&1; then
                mkfs.ext4 -F -L "alpine_root" "$rootfs_img" >/dev/null 2>&1 || true
            fi
            ;;
        *)
            notice "Creating generic placeholder image..."
            dd if=/dev/zero of="$rootfs_img" bs=1M count=64 status=none
            ;;
    esac

    if [ ! -f "$rootfs_img" ]; then
        error "Failed to create $rootfs_img"
        return 1
    fi

    notice "Alpine RootFS prepared:"
    notice "  - Target directory: $rootfs_target"
    notice "  - Image file: $rootfs_img"
    notice "  - Image size: $(du -h "$rootfs_img" 2>/dev/null | cut -f1)"

    finish_build build_alpine $@
}

usage_hook()
{
    usage_oneline "rootfs" "build the Alpine placeholder rootfs"
    usage_oneline "alpine" "alias of rootfs"
}

clean_hook()
{
    rm -rf "$RK_OUTDIR/alpine"
    rm -rf "$RK_OUTDIR/rootfs"
    rm -rf "$RK_FIRMWARE_DIR/rootfs.img"
}

INIT_CMDS=""
PRE_BUILD_CMDS=""
BUILD_CMDS="rootfs alpine"

build_hook()
{
    check_config RK_ROOTFS || false

    ROOTFS_IMG=rootfs.${RK_ROOTFS_TYPE}
    ROOTFS_DIR="$RK_OUTDIR/alpine"
    IMAGE_DIR="$ROOTFS_DIR/images"

    message "=========================================="
    message "          Start building rootfs(alpine)"
    message "=========================================="

    rm -rf "$ROOTFS_DIR" "$RK_OUTDIR/rootfs"
    mkdir -p "$IMAGE_DIR"
    ln -rsf "$ROOTFS_DIR" "$RK_OUTDIR/rootfs"

    touch "$ROOTFS_DIR/.stamp_build_start"
    build_alpine "$IMAGE_DIR"
    touch "$ROOTFS_DIR/.stamp_build_finish"

    if [ ! -f "$IMAGE_DIR/$ROOTFS_IMG" ]; then
        error "There's no $ROOTFS_IMG generated..."
        exit 1
    fi

    if [ "$RK_ROOTFS_INITRD" ]; then
        "$RK_SCRIPTS_DIR/mk-ramboot.sh" "$ROOTFS_DIR" \
            "$IMAGE_DIR/$ROOTFS_IMG" "$RK_BOOT_FIT_ITS"
        ln -rsf "$ROOTFS_DIR/ramboot.img" "$RK_FIRMWARE_DIR/boot.img"
    elif [ "$RK_SECURITY_CHECK_SYSTEM_ENCRYPTION" -o \
        "$RK_SECURITY_CHECK_SYSTEM_VERITY" ]; then
        ln -rsf "$IMAGE_DIR/security_system.img" \
            "$RK_FIRMWARE_DIR/rootfs.img"
    else
        ln -rsf "$IMAGE_DIR/$ROOTFS_IMG" "$RK_FIRMWARE_DIR/rootfs.img"
    fi

    finish_build build_rootfs $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "${1:-rootfs}" in
    rootfs|alpine) build_hook $@ ;;
    *) usage_hook ;;
esac
