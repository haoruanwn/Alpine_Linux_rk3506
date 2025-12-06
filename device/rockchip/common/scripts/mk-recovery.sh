#!/bin/bash -e

usage_hook()
{
	usage_oneline "recovery" "build recovery"
}

clean_hook()
{
	rm -rf buildroot/output/$RK_RECOVERY_CFG
	rm -rf "$RK_OUTDIR/recovery"

	rm -rf "$RK_FIRMWARE_DIR/recovery.img"
}

BUILD_CMDS="recovery"
build_hook()
{
	message "=========================================="
	message "          Skipping Buildroot Recovery     "
	message "=========================================="
	
	# Determine output directory
	DST_DIR="$RK_OUTDIR/recovery"
	mkdir -p "$DST_DIR"

	# Core logic: use boot.img as fake recovery.img
	# Check if boot.img exists (normally generated during build_kernel stage)
	local boot_img="$RK_FIRMWARE_DIR/boot.img"
	
	if [ -f "$boot_img" ]; then
		notice "Nexus: Using boot.img as fake recovery.img..."
		cp "$boot_img" "$DST_DIR/recovery.img"
	else
		# If boot.img doesn't exist, create empty placeholder to prevent errors
		warning "boot.img not found! Creating empty recovery.img placeholder."
		dd if=/dev/zero of="$DST_DIR/recovery.img" bs=1M count=16 status=none
	fi

	# Link to firmware directory for packaging tools
	ln -rsf "$DST_DIR/recovery.img" "$RK_FIRMWARE_DIR/recovery.img"

	message "Recovery image (fake) generated successfully."
	finish_build build_recovery
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

build_hook $@
