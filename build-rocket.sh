# BuildRocket
# Copyright (C) 2017 Ferran Pallarès Roca
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#!/bin/bash

# +--------------------+
# | General parameters |
# +--------------------+

VERILATOR_CONFIG=DualCoreConfig
RUN_VERILATOR_TESTS=false
KERNEL_COMMIT_HASH=riscv-linux-4.15

# +---------------+
# | Phase control |
# +---------------+

BUILD_GNU_LINUX_TOOLCHAIN=true
BUILD_VERILATOR_EMULATOR=true
BUILD_BUSYBOX=false
BUILD_FULL_BUSYBOX=false
BUILD_KERNEL=true

# +--------------------+
# | Rebuilding options |
# +--------------------+

FORCE_REBUILD_TOOLS=false
FORCE_REBUILD_VERILATOR_EMULATOR=false
FORCE_REBUILD_BUSYBOX=false
FORCE_REBUILD_KERNEL=false
FORCE_REBUILD_BBL=false

if [ $# -eq 1 ]
then
    HASH=$1
    RISCV_ROOT="rocket-${HASH:0:7}"
elif [ $# -eq 2 ]
then
    HASH=$2
    RISCV_ROOT=$1
else
    echo -e "\nUsage: ./build-rocket.sh [<NAME>] <COMMIT HASH>\n"
    exit 1
fi

check_status() {
    RET_CODE=$?
    MSG=$1
    if [ "$RET_CODE" -ne 0 ]; then
        echo "ERROR: $MSG"
        exit 1
    fi
}

gen_initramfs() {
    mkdir -p initramfs

    echo "#!/bin/busybox sh" > initramfs/init
    echo >> initramfs/init
    echo "/bin/busybox --install -s" >> initramfs/init
    echo >> initramfs/init
    echo "mount -t devtmpfs none /dev" >> initramfs/init
    echo "mount -t tmpfs none /tmp" >> initramfs/init
    echo "mount -t proc none /proc" >> initramfs/init
    echo >> initramfs/init
    echo "exec /bin/sh" >> initramfs/init

    echo "# # a comment" > initramfs_desc
    echo "# file <name> <location> <mode> <uid> <gid> [<hard links>]" >> initramfs_desc
    echo "# dir <name> <mode> <uid> <gid>" >> initramfs_desc
    echo "# nod <name> <mode> <uid> <gid> <dev_type> <maj> <min>" >> initramfs_desc
    echo "# slink <name> <target> <mode> <uid> <gid>" >> initramfs_desc
    echo "# pipe <name> <mode> <uid> <gid>" >> initramfs_desc
    echo "# sock <name> <mode> <uid> <gid>" >> initramfs_desc
    echo "#" >> initramfs_desc
    echo "# <name>       name of the file/dir/nod/etc in the archive" >> initramfs_desc
    echo "# <location>   location of the file in the current filesystem" >> initramfs_desc
    echo "#              expands shell variables quoted with \${}" >> initramfs_desc
    echo "# <target>     link target" >> initramfs_desc
    echo "# <mode>       mode/permissions of the file" >> initramfs_desc
    echo "# <uid>        user id (0=root)" >> initramfs_desc
    echo "# <gid>        group id (0=root)" >> initramfs_desc
    echo "# <dev_type>   device type (b=block, c=character)" >> initramfs_desc
    echo "# <maj>        major number of nod" >> initramfs_desc
    echo "# <min>        minor number of nod" >> initramfs_desc
    echo "# <hard links> space separated list of other links to file" >> initramfs_desc
    echo "#" >> initramfs_desc
    echo "# example:" >> initramfs_desc
    echo "# # A simple initramfs" >> initramfs_desc
    echo "# dir /dev 0755 0 0" >> initramfs_desc
    echo "# nod /dev/console 0600 0 0 c 5 1" >> initramfs_desc
    echo "# dir /root 0700 0 0" >> initramfs_desc
    echo "# dir /sbin 0755 0 0" >> initramfs_desc
    echo "# file /sbin/kinit /usr/src/klibc/kinit/kinit 0755 0 0" >> initramfs_desc
    echo "#" >> initramfs_desc
    echo "dir /dev 0755 0 0" >> initramfs_desc
    echo "dir /tmp 0755 0 0" >> initramfs_desc
    echo "dir /proc 0755 0 0" >> initramfs_desc
    echo "dir /sbin 0755 0 0" >> initramfs_desc
    echo "dir /bin 0755 0 0" >> initramfs_desc
    echo "dir /usr 0755 0 0" >> initramfs_desc
    echo "dir /usr/sbin 0755 0 0" >> initramfs_desc
    echo "dir /usr/bin 0755 0 0" >> initramfs_desc
    echo "file /init initramfs/init 0755 0 0" >> initramfs_desc
    echo "file /bin/busybox ../busybox/busybox 0755 0 0" >> initramfs_desc
    echo "slink /sbin/init /bin/busybox 0755 0 0" >> initramfs_desc
    echo "nod /dev/console 0622 0 0 c 5 1" >> initramfs_desc
}

gen_linux_config() {
    sed -i '/\<CONFIG_SMP\>/c\CONFIG_SMP=y' .config
    sed -i '/\<CONFIG_NR_CPUS\>/c\CONFIG_NR_CPUS=8' .config
    sed -i '/\<CONFIG_CPU_RV_ROCKET\>/c\CONFIG_CPU_RV_ROCKET=y' .config
    sed -i '/\<CONFIG_EARLY_PRINTK\>/c\CONFIG_EARLY_PRINTK=y' .config
    sed -i '/\<CONFIG_CROSS_COMPILE\>/c\CONFIG_CROSS_COMPILE="riscv64-unknown-linux-gnu-"' .config
    sed -i '/\<CONFIG_CMDLINE_BOOL\>/c\CONFIG_CMDLINE_BOOL=y' .config
    sed -i '/\<CONFIG_CMDLINE\>/c\CONFIG_CMDLINE="earlyprintk"' .config

    # Initramfs configurations
    if $BUILD_BUSYBOX
    then
        sed -i '/\<CONFIG_BLK_DEV_INITRD\>/c\CONFIG_BLK_DEV_INITRD=y' .config
        sed -i '/\<CONFIG_INITRAMFS_SOURCE\>/c\CONFIG_INITRAMFS_SOURCE="initramfs_desc"' .config
    fi
}

gen_busybox_config() {
    sed -i '/\<CONFIG_STATIC\>/c\CONFIG_STATIC=y' .config
    sed -i '/\<CONFIG_CROSS_COMPILER_PREFIX\>/c\CONFIG_CROSS_COMPILER_PREFIX="riscv64-unknown-linux-gnu-"' .config
    sed -i '/\<CONFIG_BUSYBOX\>/c\CONFIG_BUSYBOX=y' .config
    sed -i '/\<CONFIG_FEATURE_INSTALLER\>/c\CONFIG_FEATURE_INSTALLER=y' .config
    sed -i '/\<CONFIG_INIT\>/c\CONFIG_INIT=y' .config
    sed -i '/\<CONFIG_ASH\>/c\CONFIG_ASH=y' .config
    sed -i '/\<CONFIG_MOUNT\>/c\CONFIG_MOUNT=y' .config

    # Full configuration
    if $BUILD_FULL_BUSYBOX
    then
        sed -i '/\<CONFIG_CAT\>/c\CONFIG_CAT=y' .config

        sed -i '/\<CONFIG_CP\>/c\CONFIG_CP=y' .config
        sed -i '/\<CONFIG_FEATURE_PRESERVE_HARDLINKS\>/c\CONFIG_FEATURE_PRESERVE_HARDLINKS=y' .config

        sed -i '/\<CONFIG_HEAD\>/c\CONFIG_HEAD=y' .config
        sed -i '/\<CONFIG_FEATURE_FANCY_HEAD\>/c\CONFIG_FEATURE_FANCY_HEAD=y' .config

        sed -i '/\<CONFIG_LS\>/c\CONFIG_LS=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_FILETYPES\>/c\CONFIG_FEATURE_LS_FILETYPES=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_FOLLOWLINKS\>/c\CONFIG_FEATURE_LS_FOLLOWLINKS=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_RECURSIVE\>/c\CONFIG_FEATURE_LS_RECURSIVE=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_SORTFILES\>/c\CONFIG_FEATURE_LS_SORTFILES=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_TIMESTAMPS\>/c\CONFIG_FEATURE_LS_TIMESTAMPS=y' .config
        sed -i '/\<CONFIG_FEATURE_LS_USERNAME\>/c\CONFIG_FEATURE_LS_USERNAME=y' .config
        sed -i '/\<CONFIG_FEATURE_AUTOWIDTH\>/c\CONFIG_FEATURE_AUTOWIDTH=y' .config
        sed -i '/\<CONFIG_FEATURE_HUMAN_READABLE\>/c\CONFIG_FEATURE_HUMAN_READABLE=y' .config

        sed -i '/\<CONFIG_MKDIR\>/c\CONFIG_MKDIR=y' .config

        sed -i '/\<CONFIG_MV\>/c\CONFIG_MV=y' .config

        sed -i '/\<CONFIG_RM\>/c\CONFIG_RM=y' .config

        sed -i '/\<CONFIG_RMDIR\>/c\CONFIG_RMDIR=y' .config

        sed -i '/\<CONFIG_TAIL\>/c\CONFIG_TAIL=y' .config
        sed -i '/\<CONFIG_FEATURE_FANCY_TAIL\>/c\CONFIG_FEATURE_FANCY_TAIL=y' .config

        sed -i '/\<CONFIG_TOUCH\>/c\CONFIG_TOUCH=y' .config
        sed -i '/\<CONFIG_FEATURE_TOUCH_NODEREF\>/c\CONFIG_FEATURE_TOUCH_NODEREF=y' .config
        sed -i '/\<CONFIG_FEATURE_TOUCH_SUSV3\>/c\CONFIG_FEATURE_TOUCH_SUSV3=y' .config

        sed -i '/\<CONFIG_TOP\>/c\CONFIG_TOP=y' .config
        sed -i '/\<CONFIG_FEATURE_TOP_CPU_USAGE_PERCENTAGE\>/c\CONFIG_FEATURE_TOP_CPU_USAGE_PERCENTAGE=y' .config
        sed -i '/\<CONFIG_FEATURE_TOP_CPU_GLOBAL_PERCENTS\>/c\CONFIG_FEATURE_TOP_CPU_GLOBAL_PERCENTS=y' .config
        sed -i '/\<CONFIG_FEATURE_TOP_SMP_CPU\>/c\CONFIG_FEATURE_TOP_SMP_CPU=y' .config
        sed -i '/\<CONFIG_FEATURE_TOP_DECIMALS\>/c\CONFIG_FEATURE_TOP_DECIMALS=y' .config
        sed -i '/\<CONFIG_FEATURE_TOP_SMP_PROCESS\>/c\CONFIG_FEATURE_TOP_SMP_PROCESS=y' .config
        sed -i '/\<CONFIG_FEATURE_TOPMEM\>/c\CONFIG_FEATURE_TOPMEM=y' .config
        sed -i '/\<CONFIG_FEATURE_SHOW_THREADS\>/c\CONFIG_FEATURE_SHOW_THREADS=y' .config
        sed -i '/\<CONFIG_FEATURE_USE_TERMIOS\>/c\CONFIG_FEATURE_USE_TERMIOS=y' .config

        sed -i '/\<CONFIG_FEATURE_VERBOSE\>/c\CONFIG_FEATURE_VERBOSE=y' .config
        sed -i '/\<CONFIG_CLEAR\>/c\CONFIG_CLEAR=y' .config
    fi
}

# Prepare environment, create directory and get absolute path
mkdir -p $RISCV_ROOT
RISCV_ROOT=`readlink -f $RISCV_ROOT`
ROCKET=$RISCV_ROOT/rocket-chip
TOOLS_INSTALL=$ROCKET/riscv-tools/install

echo "export RV=${RISCV_ROOT}" > $RISCV_ROOT/env.sh
echo "export RISCV=\$RV/rocket-chip/riscv-tools/install" >> $RISCV_ROOT/env.sh
echo "export PATH=\$RISCV/bin:\$PATH" >> $RISCV_ROOT/env.sh
source $RISCV_ROOT/env.sh

echo "export RV=${RISCV_ROOT}"
echo "export RISCV=\$RV/rocket-chip/riscv-tools/install"
echo "export PATH=\$RISCV/bin:\$PATH"

echo -e "\n=============== Obtaining rocket-chip repository =================\n"
cd $RISCV_ROOT

if [ ! -d "$ROCKET" ]
then
    echo "Cloning repository from scratch..."
    git clone --recursive -j$(nproc) https://github.com/ucb-bar/rocket-chip.git
    check_status "Cloning rocket-chip"
else
    echo "rocket-chip repository found, skipping..."
fi

echo -e "\n=============== Building RICV tools =================\n"
cd $ROCKET
if [ ! -d "$TOOLS_INSTALL" ] || $FORCE_REBUILD_TOOLS
then
    echo "Cleaning-up riscv-tools repository..."
    git clean -dfx -f
    git reset --hard
    git submodule foreach --recursive git clean -dfx -f
    git submodule foreach --recursive git reset --hard
    git submodule deinit -f .
    git pull
    git checkout $HASH
    git submodule update --init --recursive

    cd $ROCKET/riscv-tools
    export MAKEFLAGS="$MAKEFLAGS -j$(nproc)"
    ./build.sh
    check_status "Installing riscv-tools"
else
    echo "riscv-tools installations found, skipping..."
fi

echo -e "\n=============== Building RISCV GNU/Linux toolchain =================\n"
if $BUILD_GNU_LINUX_TOOLCHAIN
then
    cd $ROCKET/riscv-tools/riscv-gnu-toolchain/build
    make -j$(nproc) linux
    check_status "Installing GNU/Linux toolchain"
else
    echo "GNU/Linux toolchain build disabled, skipping..."
fi

echo -e "\n=============== Building Verilator emulator =================\n"
if $BUILD_VERILATOR_EMULATOR
then
    cd $ROCKET/emulator
    if [ ! -f "emulator-freechips.rocketchip.system-DualCoreConfig-$VERILATOR_CONFIG" ] || $FORCE_REBUILD_VERILATOR_EMULATOR
    then
        if $FORCE_REBUILD_VERILATOR_EMULATOR
        then
            echo "Cleaning-up emulators..."
            make clean
        fi
        if $RUN_VERILATOR_TESTS
        then
            make -j$(nproc) run CONFIG=$VERILATOR_CONFIG
        else
            make -j$(nproc) CONFIG=$VERILATOR_CONFIG
        fi
    else
        echo "Verilator emulator build found, skipping..."
    fi
else
    echo "Verilator emulator build disabled, skipping..."
fi

check_status "Building Verilator emulator"

echo -e "\n=============== Building BusyBox =================\n"
BUSYBOX=$RISCV_ROOT/busybox
if $BUILD_BUSYBOX
then
    if [ ! -d "$BUSYBOX" ] || $FORCE_REBUILD_BUSYBOX
    then
        rm -rf $BUSYBOX
        mkdir -p $BUSYBOX
        curl -L http://busybox.net/downloads/busybox-1.26.2.tar.bz2 | tar xj --strip-components=1 -C $BUSYBOX
        check_status "Downloading BusyBox"

        cd $BUSYBOX
        make mrproper
        make allnoconfig

        # Run twice, one for enabling submenus (showing suboptions after defconfig), second for enabling those suboptions
        gen_busybox_config
        yes "" | make oldconfig #olddefconfig does not exist, leave new options as default
        check_status "Configuring BusyBox"
        gen_busybox_config
        yes "" | make oldconfig #olddefconfig does not exist, leave new options as default
        check_status "Configuring BusyBox"
    fi

    cd $BUSYBOX
    make -j$(nproc)
    check_status "Building BusyBox"
else
    echo "BusyBox installation found, skipping..."
fi
cd $RISCV_ROOT

echo -e "\n=============== Obtaining RISCV Linux Kernel =================\n"
LINUX=$RISCV_ROOT/riscv-linux

if [ ! -d "$LINUX" ]
then
    echo "Cloning repository from scratch..."
    git clone --recursive -j$(nproc) https://github.com/riscv/riscv-linux.git
    check_status "Cloning RISCV Linux Kernel"
else
    echo "RISCV Linux Kernel repository found, skipping..."
fi

echo -e "\n=============== Building RISCV Linux Kernel =================\n"
if $BUILD_KERNEL
then
    cd $LINUX
    if $FORCE_REBUILD_KERNEL
    then
        git clean -dfx -f
        git reset --hard
        git pull
        git checkout $KERNEL_COMMIT_HASH

        make mrproper
        make ARCH=riscv defconfig
        check_status "Configuring Linux kernel"

        if $BUILD_BUSYBOX
        then
            gen_initramfs
        fi

        # Run twice, one for enabling submenus (showing suboptions after olddefconfig), second for enabling those suboptions
        gen_linux_config
        make ARCH=riscv olddefconfig
        check_status "Configuring Linux kernel"
        gen_linux_config
        make ARCH=riscv olddefconfig
        check_status "Configuring Linux kernel"
    fi

    make ARCH=riscv -j$(nproc) vmlinux
    check_status "Building Linux kernel"
else
    echo "Linux kernel installation found, skipping..."
fi

echo -e "\n=============== Rebuild BBL =================\n"
if $BUILD_KERNEL || $FORCE_REBUILD_BBL
then
    cd $ROCKET/riscv-tools/riscv-pk
    mkdir -p build_payload_bbl
    cd build_payload_bbl
    BBL_CONFIG=`../build/config.status --config`
    rm -rf *
    eval ../configure "$BBL_CONFIG" --with-payload=$LINUX/vmlinux --disable-logo
    check_status "Configuring BBL"
    make install
    check_status "Installing BBL"
else
    echo "Linux kernel build disabled, rebuilding BBL is not needed, skipping..."
fi
