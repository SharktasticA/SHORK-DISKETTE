#!/bin/bash

######################################################
## SHORK DISKETTE build script                      ##
######################################################
## Kali (sharktastica.co.uk)                        ##
######################################################



START_TIME=$(date +%s)



set -e



# The highest working directory
CURR_DIR=$(pwd)



# TUI colour palette
RED='\033[0;31m'
LIGHT_RED='\033[0;91m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'



# A general confirmation prompt
confirm()
{
    while true; do
        read -p "$(echo -e ${YELLOW}Do you want to $1? [Yy/Nn]: ${RESET})" yn
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo -e "${RED}Please answer [Y/y] or [N/n]. Try again.${RESET}" ;;
        esac
    done
}



echo -e "${BLUE}================================="
echo -e "${BLUE}== SHORK DISKETTE build script =="
echo -e "${BLUE}=================================${RESET}"



# General global vars
BUILD_TYPE="default"
BOOTLDR_USED=""
DISK_CYLINDERS=0
DISK_HEADS=16
DISK_SECTORS_TRACK=63
DONT_DEL_ROOT=false
EST_MIN_RAM="16"
EXCLUDED_FEATURES=""
INCLUDED_FEATURES=""
ROOT_PART_SIZE=""
TOTAL_DISK_SIZE=""
USED_PARAMS=""

# Process arguments
ALWAYS_BUILD=false
ENABLE_PATA=false
FIX_SYSLINUX=false
IS_ARCH=false
IS_DEBIAN=false
SKIP_BB=false
SKIP_KRN=false

while [ $# -gt 0 ]; do
    USED_PARAMS+="\n  $1"
    case "$1" in
        --always-build)
            ALWAYS_BUILD=true
            ;;
        --enable-pata)
            ENABLE_PATA=true
            BUILD_TYPE="PATA capable"
            ;;
        --fix-syslinux)
            FIX_SYSLINUX=true
            ;;
        --is-arch)
            IS_ARCH=true
            IS_DEBIAN=false
            ;;
        --is-debian)
            IS_ARCH=false
            IS_DEBIAN=true
            ;;
        --skip-busybox)
            SKIP_BB=true
            DONT_DEL_ROOT=true
            ;;
        --skip-kernel)
            SKIP_KRN=true
            DONT_DEL_ROOT=true
            ;;
    esac
    shift
done



# Desired versions
BUSYBOX_VER="1_36_1"
KERNEL_VER="6.14.11"

# MBR binary
MBR_BIN=""



# Common compiler/compiler-related locations
PREFIX="${CURR_DIR}/build/i486-linux-musl-cross"
AR="${PREFIX}/bin/i486-linux-musl-ar"
CC="${PREFIX}/bin/i486-linux-musl-gcc"
CC_STATIC="${CURR_DIR}/i486-linux-musl-gcc-static"
DESTDIR="${CURR_DIR}/build/root"
HOST=i486-linux-musl
RANLIB="${PREFIX}/bin/i486-linux-musl-ranlib"
STRIP="${PREFIX}/bin/i486-linux-musl-strip"
SYSROOT="${PREFIX}/i486-linux-musl"



######################################################
## House keeping                                    ##
######################################################

# Deletes build directory
delete_root_dir()
{
    if [ -n "$CURR_DIR" ] && [ -d "${DESTDIR}" ]; then
        echo -e "${GREEN}Deleting existing SHORK DISKETTE root directory to ensure fresh changes can be made...${RESET}"
        sudo rm -rf "${DESTDIR}"
    fi
}

# Fixes directory and diskette image file permissions after root build
fix_perms()
{
    if [ "$(id -u)" -eq 0 ]; then
        echo -e "${GREEN}Fixing directory and diskette image file permissions so they can be accessed by a non-root user/program after a root build...${RESET}"

        HOST_GID=${HOST_GID:-1000}
        HOST_UID=${HOST_UID:-1000}

        if [ -d . ]; then
            sudo chown -R "$HOST_UID:$HOST_GID" .
            sudo chmod 755 .
        fi

        sudo chown "$HOST_UID:$HOST_GID" $CURR_DIR/images/shork-diskette.img
        sudo chmod 644 $CURR_DIR/images/shork-diskette.img
    fi
}

# Cleans up any stale mounts and block-device mappings left by image builds
clean_stale_mounts()
{
    echo -e "${GREEN}Cleaning up any stale mounts and block-device mappings left by image builds ...${RESET}"
    sudo umount -lf /mnt 2>/dev/null || true
    sudo losetup -a | grep shork-diskette.img | cut -d: -f1 | xargs -r sudo losetup -d || true
    sudo dmsetup remove_all 2>/dev/null || true
}



######################################################
## Copy functions                                   ##
######################################################

# Copies a config file to a destination and makes sure any @CC@, @CC_STATIC@, @AR@
# or @STRIP@ placeholders are replaced
copy_config()
{
    # Input parameters
    SRC="$1"
    DST="$2"

    # Ensure source exists
    [ -f "$SRC" ] || return 1

    # Copy file
    sudo cp "$SRC" "$DST"

    # Replace all placeholders with their respective values
    sudo sed -i -e "s|@CC@|$CC|g" -e "s|@CC_STATIC@|$CC_STATIC|g" -e "s|@AR@|$AR|g" -e "s|@STRIP@|$STRIP|g" "$DST"
}

# Copies a sysfile to a destination and makes sure any @NAME@ @VER@, @ID@
# or @URL@ placeholders are replaced
copy_sysfile()
{
    # Input parameters
    SRC="$1"
    DST="$2"

    # Ensure source exists
    [ -f "$SRC" ] || return 1

    # Copy file
    sudo cp "$SRC" "$DST"

    # Read NAME, VER, ID and URL
    NAME="$(cat ${CURR_DIR}/branding/NAME | tr -d '\n')"
    VER="$(cat ${CURR_DIR}/branding/VER | tr -d '\n')"
    ID="$(cat ${CURR_DIR}/branding/ID | tr -d '\n')"
    URL="$(cat ${CURR_DIR}/branding/URL | tr -d '\n')"

    # Replace all placeholders with their respective values
    sudo sed -i -e "s|@NAME@|$NAME|g" -e "s|@VER@|$VER|g" -e "s|@ID@|$ID|g" -e "s|@URL@|$URL|g" "$DST"
}



######################################################
## Host environment prerequisites                   ##
######################################################

install_arch_prerequisites()
{
    echo -e "${GREEN}Installing prerequisite packages for an Arch-based system...${RESET}"

    PACKAGES="bc bison bzip2 cpio dosfstools flex git make mtools sudo syslinux wget xz"

    if $FIX_SYSLINUX; then
        PACKAGES+=" nasm python"
    fi

    sudo pacman -Syu --noconfirm --needed $PACKAGES || true
}

install_debian_prerequisites()
{
    echo -e "${GREEN}Installing prerequisite packages for a Debian-based system...${RESET}"
    sudo apt-get update

    PACKAGES="bc bison bzip2 cpio dosfstools flex git make sudo syslinux wget xz-utils"

    if $FIX_SYSLINUX; then
        PACKAGES+=" nasm python3 python-is-python3 uuid-dev"
    fi

    sudo apt-get install -y $PACKAGES || true
}

# Installs needed packages to host computer
get_prerequisites()
{
    if [ -z "$IN_DOCKER" ]; then
        if $IS_ARCH; then
            install_arch_prerequisites
        elif $IS_DEBIAN; then
            install_debian_prerequisites
        else
            echo -e "${YELLOW}Select host Linux distribution:${RESET}"
            select host in "Arch based" "Debian based"; do
                case $host in
                    "Arch based")
                        install_arch_prerequisites
                        break ;;
                    "Debian based")
                        install_debian_prerequisites
                        break ;;
                    *)
                esac
            done
        fi
    else
        # Skip if inside Docker as Dockerfile already installs prerequisites
        echo -e "${LIGHT_RED}Running inside Docker, skipping installing prerequisite packages...${RESET}"
    fi
}



######################################################
## Compiled software toolchains & prerequisites     ##
######################################################

# Download and extract i486 musl cross-compiler
get_i486_musl_cc()
{
    cd "$CURR_DIR/build"

    echo -e "${GREEN}Downloading i486 cross-compiler...${RESET}"
    [ -f i486-linux-musl-cross.tgz ] || wget https://musl.cc/i486-linux-musl-cross.tgz
    [ -d "i486-linux-musl-cross" ] || tar xvf i486-linux-musl-cross.tgz
}

# Download and build our forked SYSLINUX (required if "Fix SYSLINUX" was used)
get_patched_syslinux()
{
    cd "$CURR_DIR/build"

    # Skip if already compiled
    if [ -f "$CURR_DIR/build/syslinux/bios/linux/syslinux" ]; then
        echo -e "${LIGHT_RED}SYSLINUX already compiled, skipping...${RESET}"
        return
    fi

    # Download source
    if [ -d syslinux ]; then
        echo -e "${YELLOW}SYSLINUX source already present, resetting...${RESET}"
        cd syslinux
        git reset --hard
    else
        echo -e "${GREEN}Downloading SYSLINUX...${RESET}"
        git clone https://github.com/SharktasticA/syslinux.git
        cd syslinux
    fi

    # Compile and install
    echo -e "${GREEN}Compiling SYSLINUX...${RESET}"
    CFLAGS="-fcommon" sudo make bios
}



######################################################
## BusyBox & core utilities building                ##
######################################################

# Download and compile BusyBox
get_busybox()
{
    cd "$CURR_DIR/build"

    # Download source
    if [ -d busybox ]; then
        echo -e "${YELLOW}BusyBox source already present, resetting...${RESET}"
        cd busybox
        git config --global --add safe.directory $CURR_DIR/build/busybox
        git reset --hard
    else
        echo -e "${GREEN}Downloading BusyBox...${RESET}"
        git clone --branch $BUSYBOX_VER https://github.com/mirror/busybox.git
        cd busybox
    fi

    # Compile and install
    echo -e "${GREEN}Compiling BusyBox...${RESET}"
    make ARCH=x86 allnoconfig
    sed -i 's/main() {}/int main() {}/' scripts/kconfig/lxdialog/check-lxdialog.sh

    # Patch BusyBox to suppress banner and help message
    sed -i 's/^#if !ENABLE_FEATURE_SH_EXTRA_QUIET/#if 0 \/* disabled ash banner *\//' shell/ash.c

    echo -e "${GREEN}Copying base SHORK DISKETTE BusyBox .config file...${RESET}"
    cp $CURR_DIR/configs/busybox.config .config

    # Ensure BusyBox behaves with our toolchain
    sed -i "s|^CONFIG_CROSS_COMPILER_PREFIX=.*|CONFIG_CROSS_COMPILER_PREFIX=\"${PREFIX}/bin/i486-linux-musl-\"|" .config
    sed -i "s|^CONFIG_SYSROOT=.*|CONFIG_SYSROOT=\"${CURR_DIR}/build/i486-linux-musl-cross\"|" .config
    sed -i "s|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS=\"-I${PREFIX}/include\"|" .config
    sed -i "s|^CONFIG_EXTRA_LDFLAGS=.*|CONFIG_EXTRA_LDFLAGS=\"-L${PREFIX}/lib\"|" .config

    make ARCH=x86 -j$(nproc)
    make ARCH=x86 install

    echo -e "${GREEN}Install BusyBox compilation as the basis for the root file system...${RESET}"
    if [ -d "${DESTDIR}" ]; then
        sudo rm -r "${DESTDIR}"
    fi
    mv _install "${DESTDIR}"

    # Copy licence file
    cp LICENSE $CURR_DIR/build/LICENCES/busybox.txt
}



######################################################
## Kernel building                                  ##
######################################################

download_kernel()
{
    cd "$CURR_DIR/build"
    echo -e "${GREEN}Downloading the Linux kernel...${RESET}"
    if [ ! -d "linux" ]; then
        git clone --depth=1 --branch v$KERNEL_VER https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git || true
        cd "$CURR_DIR/build/linux"
        configure_kernel
    fi
}

configure_kernel()
{
    echo -e "${GREEN}Copying base SHORK DISKETTE Linux kernel .config file...${RESET}"
    cp $CURR_DIR/configs/linux.config .config

    FRAGS=""

    if $ENABLE_PATA; then
        echo -e "${GREEN}Enabling kernel PATA CD, DVD and hard drive support...${RESET}"
        FRAGS+="$CURR_DIR/configs/linux.config.cdrom.frag "
    fi
    
    if [ -n "$FRAGS" ]; then
        ./scripts/kconfig/merge_config.sh -m $CURR_DIR/configs/linux.config $FRAGS
        make olddefconfig
    fi
}

reset_kernel()
{
    cd "$CURR_DIR/build/linux"
    echo -e "${GREEN}Resetting and cleaning Linux kernel...${RESET}"
    git config --global --add safe.directory $CURR_DIR/build/linux || true
    git reset --hard || true
    make clean
    configure_kernel
}

reclone_kernel()
{
    cd "$CURR_DIR/build"
    echo -e "${GREEN}Deleting and recloning Linux kernel...${RESET}"
    sudo rm -r linux
    download_kernel
}

compile_kernel()
{   
    cd "$CURR_DIR/build/linux/"
    echo -e "${GREEN}Compiling Linux kernel...${RESET}"
    make ARCH=x86 olddefconfig
    make ARCH=x86 bzImage -j$(nproc)
    sudo mv arch/x86/boot/bzImage "$CURR_DIR/build" || true
    sudo cp COPYING $CURR_DIR/build/LICENCES/linux.txt
}

# Download and compile Linux kernel
get_kernel()
{
    cd "$CURR_DIR/build"

    if $ALWAYS_BUILD; then
        if [ ! -d "linux" ]; then
            download_kernel
        else
            reset_kernel
        fi
    else
        if [ ! -d "linux" ]; then
            download_kernel
        else
            echo -e "${YELLOW}A Linux kernel has already been downloaded and potentially compiled. Select action:${RESET}"
            select action in "Proceed with current kernel" "Reset & clean" "Delete & reclone"; do
                case $action in
                    "Proceed with current kernel")
                        echo -e "${GREEN}Proceeding with the current kernel...${RESET}"
                        return
                        break ;;
                    "Reset & clean")
                        reset_kernel
                        break ;;
                    "Delete & reclone")
                        reclone_kernel
                        break ;;
                    *)
                esac
            done
        fi
    fi

    compile_kernel
}

# Makes sure that the after-build report includes kernel statistics
# This is separate to configure_kernel so that these are still recorded if
# the "skip kernel" parameter is used.
get_kernel_features()
{
    if $ENABLE_PATA; then
        INCLUDED_FEATURES+="\n  * kernel-level PATA CD, DVD and hard drive support"
    else
        EXCLUDED_FEATURES+="\n  * kernel-level PATA CD, DVD and hard drive support"
    fi
}



######################################################
## Packaged software building                       ##
######################################################

# Copies all licences for included software
copy_licences()
{
    echo -e "${GREEN}Copy all needed licences for included software...${RESET}"
    sudo mkdir -p "$DESTDIR/LICENCES"
    sudo cp -a "$CURR_DIR/build/LICENCES/." "$DESTDIR/LICENCES/"
}



######################################################
## File system & diskette image building            ##
######################################################

# Builds the root system
build_file_system()
{
    cd "${DESTDIR}"

    echo -e "${GREEN}Building the root system...${RESET}"

    echo -e "${GREEN}Creating required directories...${RESET}"
    sudo mkdir -p {dev,proc,etc/init.d,sys,tmp,home,banners}

    echo -e "${GREEN}Configure permissions...${RESET}"
    chmod +x $CURR_DIR/sysfiles/rc
    chmod +x $CURR_DIR/shorkutils/shorkfetch
    chmod +x $CURR_DIR/shorkutils/shorkhelp

    echo -e "${GREEN}Copying pre-defined files...${RESET}"
    copy_sysfile $CURR_DIR/sysfiles/welcome $DESTDIR/banners/welcome
    copy_sysfile $CURR_DIR/sysfiles/hostname $DESTDIR/etc/hostname
    copy_sysfile $CURR_DIR/sysfiles/issue $DESTDIR/etc/issue
    copy_sysfile $CURR_DIR/sysfiles/os-release $DESTDIR/etc/os-release
    copy_sysfile $CURR_DIR/sysfiles/rc $DESTDIR/etc/init.d/rc
    copy_sysfile $CURR_DIR/sysfiles/inittab $DESTDIR/etc/inittab

    echo -e "${GREEN}Copying shorkutils...${RESET}"
    copy_sysfile $CURR_DIR/shorkutils/shorkfetch $DESTDIR/usr/bin/shorkfetch
    INCLUDED_FEATURES+="\n  * shorkfetch"
    copy_sysfile $CURR_DIR/shorkutils/shorkhelp $DESTDIR/usr/bin/shorkhelp
    INCLUDED_FEATURES+="\n  * shorkhelp"

    cd "${DESTDIR}"
    sudo chown -R root:root .
    echo -e "${GREEN}Compressing root file system into one file...${RESET}"
    find . | cpio -H newc -o | xz --check=crc32 --lzma2=dict=512KiB -e > $CURR_DIR/build/rootfs.cpio.xz
}

# Build a floppy diskette image containing our system
build_diskette_img()
{
    cd $CURR_DIR/build/

    # Cleans up diskette mount script exits, fails or interrupted
    cleanup()
    {
        if mountpoint -q /mnt; then
            sudo umount /mnt || true
        fi
        if [[ -n "$LOOP" ]]; then
            sudo losetup -d "$LOOP" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT ERR INT TERM

    # Create a floppy diskette image
    echo -e "${GREEN}Creating a floppy diskette image for containing this system...${RESET}"
    sudo dd if=/dev/zero of=../images/shork-diskette.img bs=1k count=1440
    sudo mkdosfs -n SHORKDISK ../images/shork-diskette.img

    # Install a bootloader
    echo -e "${GREEN}Installing SYSLINUX bootloader...${RESET}"
    SYSLINUX_BIN="syslinux"
    BOOTLDR_USED="SYSLINUX"
    if $FIX_SYSLINUX; then
        SYSLINUX_BIN="$CURR_DIR/build/syslinux/bios/linux/syslinux"
        BOOTLDR_USED="patched SYSLINUX"
    fi 
    sudo "$SYSLINUX_BIN" --install ../images/shork-diskette.img

    # Ensure loop devices exist (Docker does not always create them)
    for i in $(seq 0 255); do
        [ -e /dev/loop$i ] || sudo mknod /dev/loop$i b 7 $i
    done
    [ -e /dev/loop-control ] || sudo mknod /dev/loop-control c 10 237

    # Mount it for copying files
    echo -e "${GREEN}Mounting diskette image for copying files...${RESET}"
    LOOP=$(sudo losetup -f --show ../images/shork-diskette.img)
    sudo mount -t vfat "$LOOP" /mnt

    # Install the kernel
    echo -e "${GREEN}Copying SYSLINUX configuration...${RESET}"
    copy_sysfile $CURR_DIR/sysfiles/syslinux.cfg  /mnt/syslinux.cfg

    # Install the kernel
    echo -e "${GREEN}Installing kernel image...${RESET}"
    sudo cp bzImage /mnt

    # Copy compressed root file system
    echo -e "${GREEN}Copying compressed root file system...${RESET}"
    sudo cp rootfs.cpio.xz /mnt

    # Make directory to be used as /home when booted
    sudo mkdir /mnt/data || true

    # Unmount the image
    echo -e "${GREEN}Unmounting diskette image...${RESET}"
    sudo umount /mnt
    sudo losetup -d "$LOOP"
}



######################################################
## End of build report generation                   ##
######################################################

# Generate a report to go in the images folder to indicate details about this build
generate_report()
{
    DATE=$(date "+%Y-%m-%d %H:%M:%S")
    END_TIME=$(date +%s)
    TOTAL_SECONDS=$(( END_TIME - START_TIME ))
    MINS=$(( TOTAL_SECONDS / 60 ))
    SECS=$(( TOTAL_SECONDS % 60 ))

    local lines=(
        "======================================="
        "== SHORK DISKETTE after-build report =="
        "======================================="
        "==        $DATE        =="
        "======================================="
        ""
        "Build type: $BUILD_TYPE"
        "Build time: $MINS minutes, $SECS seconds"
    )

    if [ -n "$USED_PARAMS" ]; then
        lines+=(
            "Build parameters: $USED_PARAMS"
        )
    fi

    lines+=(
        ""
        "Est. minimum RAM: ${EST_MIN_RAM}MiB"
        "Bootloader used: $BOOTLDR_USED"
    )

    if [ -n "$INCLUDED_FEATURES" ]; then
        lines+=(
            ""
            "Included programs & features: $INCLUDED_FEATURES"
        )
    fi

    if [ -n "$EXCLUDED_FEATURES" ]; then
        lines+=(
            ""
            "Excluded programs & features: $EXCLUDED_FEATURES"
        )
    fi

    printf "%b\n" "${lines[@]}" | sudo tee "$CURR_DIR/images/report.txt" > /dev/null
}



mkdir -p images

if ! $DONT_DEL_ROOT; then
    delete_root_dir
fi

mkdir -p build/LICENCES
get_prerequisites
get_i486_musl_cc

if ! $SKIP_BB; then
    get_busybox
fi

if ! $SKIP_KRN; then
    get_kernel
fi
get_kernel_features

copy_licences

if $FIX_SYSLINUX; then
    get_patched_syslinux
fi

build_file_system
build_diskette_img
fix_perms
clean_stale_mounts
generate_report
