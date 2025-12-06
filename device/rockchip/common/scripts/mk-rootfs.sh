#!/bin/bash -e

build_alpine()
{
    local image_dir="$1"
    image_dir="${image_dir:-$RK_OUTDIR/alpine/images}"

    message "=========================================="
    message "          Start building Alpine Linux     "
    message "=========================================="

    local fs_type="${RK_ROOTFS_TYPE:-ext4}"
    local rootfs_img="$image_dir/rootfs.$fs_type"

    message "Target RootFS Image: $rootfs_img"

    mkdir -p "$image_dir"
    rm -f "$rootfs_img"

    notice "Creating placeholder ($fs_type) image for packing check..."
    dd if=/dev/zero of="$rootfs_img" bs=1M count=32 status=none

    if [ "$fs_type" = "ext4" ]; then
        if command -v mkfs.ext4 >/dev/null 2>&1; then
            mkfs.ext4 -F -L "alpine_root" "$rootfs_img" >/dev/null 2>&1
        else
            warning "mkfs.ext4 not found, skipping format. (Placeholder image is enough)"
        fi
    fi

    if [ ! -f "$rootfs_img" ]; then
        error "Failed to create $rootfs_img"
        return 1
    fi

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
