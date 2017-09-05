#!/usr/bin/env bash

# Basic Library for Kdump Test

# Copyright (c) 2016 Red Hat, Inc. All rights reserved.
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
#
# Author: Qiao Zhao <qzhao@redhat.com>

((LIB_KDUMP_SH)) && return || LIB_KDUMP_SH=1
. ../lib/log.sh

K_ARCH="$(uname -m)"
K_DIST_NAME="$(rpm -E %{?dist} | sed 's/[.0-9]//g')"
K_DIST_VER="$(rpm -E %{?dist} | sed 's/[^0-9]//g')"

K_CONFIG="/etc/kdump.conf"
K_DEFAULT_PATH="/var/crash"
K_SSH_CONFIG="${HOME}/.ssh/config"
K_SYS_CONFIG="/etc/sysconfig/kdump"
K_SCRIPT="../lib/gen-helper-script"

NETWORK_CONFIG="/etc/sysconfig/network-scripts/"

# Test Parameters:
KDEBUG=${KDEBUG:-"false"}
TESTARGS=${TESTARGS:-}
KPATH=${KPATH:-${K_DEFAULT_PATH}}
OPTION=${OPTION:-}
MP=${MP:-/}
LABEL=${LABEL:-label-kdump}
RAW=${RAW:-"false"}
TESTAREA=${TESTAREA:-"/mnt/testarea"}

# Test dirs:
K_TMP_DIR="${TESTAREA}/tmp"
K_INF_DIR="${TESTAREA}/info"
K_BAK_DIR="${TESTAREA}/bk"

K_REBOOT="${K_TMP_DIR}/K_REBOOT"
C_REBOOT="./C_REBOOT"

# KDUMP-PATH stores the full path to vmcore files.
# e.g. cat KDUMP-PATH: ${MP%/}${KPATH}
K_PATH="${K_TMP_DIR}/KDUMP-PATH"
K_RAW="${K_TMP_DIR}/KDUMP-RAW"
K_NFS="${K_TMP_DIR}/KDUMP-NFS"  # file storing the nfs exports path
K_RAID="${K_TMP_DIR}/KDUMP-RAID"

K_HWINFO_FILE="${K_INF_DIR}/hwinfo.log"
K_INITRAMFS_LIST="${K_INF_DIR}/initramfs.list"

K_PREFIX_FWD="${K_INF_DIR}/FIREWALLD"
K_PREFIX_IPT="${K_INF_DIR}/IPTABLES"
K_PREFIX_SSH="${K_INF_DIR}/SSHD_ENABLE"


MD_DEVICE="${MD_DEVICE:-/dev/md0}"
RAID_DEVICES="${RAID_DEVICES:-}"

readonly K_EXPORT="/mnt/testarea/nfs"
readonly K_LOCK_AREA="/root"
readonly K_LOCK_SSH_ID_RSA="${K_LOCK_AREA}/.ssh/id_rsa_kdump"
readonly K_RETRY_COUNT=1000
readonly K_CPU_THRESHOLD=8

[[ "${KDEBUG,,}" == "true" ]] && set -x

[ ! -d "${K_TMP_DIR}" ] &&  mkdir -p "${K_TMP_DIR}"
[ ! -d "${K_INF_DIR}" ] &&  mkdir -p "${K_INF_DIR}"
[ ! -d "${K_BAK_DIR}" ] &&  mkdir -p "${K_BAK_DIR}"


# @usage: backup_files
# @description: backup kdump config
backup_files()
{
    cp "${K_CONFIG}" "${K_BAK_DIR}"/
    cp "${K_SYS_CONFIG}" "${K_BAK_DIR}"/
}


# @usage: install_rpm <pkg> <pkg>
# @description: install rpm packages if they are not installed
# @param1: list of pkg
install_rpm()
{
    log_info "- Installing rpm(s) $*"

    if [[ $# -gt 0 ]]; then
        for pkg in $@; do
            rpm -q "$pkg" || yum install -y "$pkg" || log_error "- Install package $pkg failed!"
        done
        log_info "- Installed $* successfully"
    fi
}


# @usage: install_rpm <pkg> <repo>
# @description: install a rpm package from a repo
# @param1: pkg
# @param2: repo
install_rpm_from_repo()
{
    log_info "- Installing a rpm from a repo."

    if [ $# -lt 2 ]; then
        log_error "- Expecting pkg and repo name. But got $# args only."
    fi

    local pkg=$1
    local repo=$2

    rpm -q "$pkg" || yum install -y --enablerepo="$repo" "$pkg" || \
        log_error "- Install package $pkg from $repo failed!"

    log_info "- Installed/upgraded $pkg from $repo successfully"
}


# @usage: make_module <name> <from> <to>
# @description: make a module
# @param1: name  # name of the module
# @param2: from  # path where "${name}".c and Makefile."${name}" are stored
# @param3: dest  # path to dir where .ko will be generated to. defaul to <name>
make_module()
{
    [ $# -lt 2 ] && log_error "- No module name or from path"
    local name=$1
    local from=$2
    local dest=${3:-$name}

    mkdir "${dest}"
    cp "${from}"/"${name}".c "${dest}/"
    cp "${from}"/Makefile."${name}" "${dest}/Makefile"

    unset ARCH
    make -C "${name}/" || log_error "- Can not make module."
    export ARCH
    ARCH=$(uname -m)
}


# @usage: make_install_module <name> <from> <to>
# @description: make and install a module
# @param1: name  # name of the module
# @param2: from  # path where "${name}".c and Makefile."${name}" are stored
# @param3: dest  # path to dir where .ko will be generated to. defaul to <name>
make_install_module()
{
    [ $# -lt 2 ] && log_error "- No module name or from path"
    local name=$1
    local from=$2
    local dest=${3:-$name}

    make_module "${name}" "${from}" "${dest}"

    insmod "${dest}/${name}.ko" || log_error "- Failed to insmod module."
}


##  Preparing Kdump/Crash Test Environment ###

# @usage: multihost_prepare
# @description: install required packakges for multi-host tests
multihost_prepare()
{
    which nc || yum install -y nmap-ncat || yum install -y nc || log_error "- Failed to install nc client"
}


# @usage: crash_prepare
# @description: install required packakges for crash test
crash_prepare()
{
    # The version of kernel-debuginfo to be installed must be same as
    # the version of current kernel.
    # if not, exit with error as it cannot be used for crash analysis.
    if [[ "${K_DIST_NAME}" == "fc" ]]; then
        ret_value=$(yum list --enablerepo=updates-debuginfo kernel-debuginfo \
            | grep kernel-debuginfo \
            | awk '{print $2}'
        )

        [ "${ret_value}.${K_ARCH}" ==  "$(uname -r)" ] || \
            log_error "- Cannot find kernel-debuginfo.$(uname -r) in repo updates-debuginfo."

        install_rpm_from_repo kernel-debuginfo updates-debuginfo
        install_rpm crash
    else
        install_rpm kernel-debuginfo crash
    fi
}


# @usage: kdump_prepare
# @description: to make sure crash mem is reserved and kdump is started.
# @param1: options # valid values: empty of fadump
kdump_prepare()
{
    local opt=$1

    if [ ! -f "${K_REBOOT}" ]; then
        # install kexec-tools package
        install_rpm kexec-tools

        # backup config files
        backup_files

        local default=/boot/vmlinuz-$(uname -r)
        [ ! -s "$default" ] && default=/boot/vmlinux-$(uname -r)

        # temporarily comment out this line to set default to grubby
        # seems if it's executed too quickly with rebuilding kdump img,
        # system would hange after rebooting.
        # need to figure out why it requires to set default to grub
        # /sbin/grubby --set-default="${default}"

        # for uncompressed kernel, i.e. vmlinux
        [[ "${default}" == *vmlinux* ]] && {
            log_info "- Modifying ${K_SYS_CONFIG} properly for 'vmlinux'."
            sed -i 's/\(KDUMP_IMG\)=.*/\1=vmlinux/' ${K_SYS_CONFIG}
        }

        # In Fedora/upstream kernel, crashkernel=auto is not suppored.
        # By checking if /sys/kernel/kexec_crash_size is zero, we can tell if
        # auto crashkernel is supported and if crash memory is allocated.

        # If it is not supported, we need to specify the memory by changing
        # kernel param to crashkernel=<>M, and reboot system.

        if [ "${opt}" != "fadump" ]; then
            grep -q 'crashkernel' <<< "${KERARGS}" || {
                    log_info "- Checking if crash memory is reserved from /sys/kernel/kexec_crash_size"
                    [ "$(cat /sys/kernel/kexec_crash_size)" -eq 0 ] && {
                        log_info "- Crash memory is not reserved."
                        log_info "- $(grep MemTotal /proc/meminfo)"
                        KERARGS+=" $(get_kdump_mem)"
                    }
            }
        fi

        [ "${KERARGS}" ] && {
            # K_REBOOT is to mark system's been rebooted for kernel cmdline change.
            touch "${K_REBOOT}"
            log_info "- Changing boot loader: ${KERARGS}"
            {
                /sbin/grubby    \
                    --args="${KERARGS}"    \
                    --update-kernel="${default}" &&
                if [ "${K_ARCH}" = "s390x" ]; then zipl; fi
            } || {
                log_error "- Changing boot loader failed!"
            }
            log_info "- Reboot system for system preparing."
            reboot_system
        }
    fi

    # exit with error if there is still no crash memory reserved for kdump.
    if [ "${opt}" != "fadump" ]; then
        local mem_reserved=$(cat /sys/kernel/kexec_crash_size)

        if [ "${mem_reserved}" -eq 0 ]; then
            log_info "- Kernel Boot Cmdline is: $(cat /proc/cmdline)"
            log_error "- No memory is reserved for crashkernel!"
        else
            log_info "- Crash memory with size ${mem_reserved} is reserved for kdump."
        fi
    else
        local mem_reserved=$(dmesg | grep "firmware-assisted dump" | grep "Reserved")
        [ "${mem_reserved}" == "" ] && {
           log_error "- No memory is reserved for fadump!"
        }
        if [ "$(cat /sys/kernel/kexec_crash_size)" -ne 0 ]; then
            log_info "# cat /sys/kernel/kexec_crash_size: $(cat /sys/kernel/kexec_crash_size)"
            log_error "- kexec_crash_size should be 0 when fadump is active!"
        fi
        log_info "- Crash memory is reserved for fadump."
    fi

    # enable sysrq
    sysctl -w kernel.sysrq="1"
    sysctl -p

    # enable kdump service: systemd
    /bin/systemctl enable kdump.service || /sbin/chkconfig kdump on || log_error "- Failed to enable kdump!"
    log_info "- Enabled kdump service."

    # make sure kdumpctl is operational
    kdumpctl status 2>&1 || service kdump status 2>&1 || log_error "- Kdump is not running!"
}


# @usage: get_kdump_mem
# @description: get default memory reserved for crashkernel
get_kdump_mem()
{
    local args=""
    case "${K_ARCH}" in
        "x86_64")
            args="crashkernel=160M"
            ;;
        "ppc64")
            args="crashkernel=320M"
            ;;
        "ppc64le")
            args="crashkernel=320M"
            ;;
        "s390x")
            args="crashkernel=160M"
            ;;
        "aarch64")
            args="crashkernel=2048M"
            ;;
        *)
            ;;
    esac
    echo "$args"
}


# @usage: kdump_restart
# @description: restart kdump service
kdump_restart()
{
    log_info "- Restart kdump service."

    # delete initrd*kdump.img and update timestamp of kdump.conf
    rm -f /boot/initrd-*kdump.img
    rm -f /boot/initramfs-*kdump.img  # for rhel7
    touch "${K_CONFIG}"

    /usr/bin/kdumpctl restart 2>&1 || /sbin/service kdump restart 2>&1 || log_error "- Failed to start kdump!"
    log_info "- Kdump service starts successfully."

    sync; sync; sleep 10
}


###  Configuring KDUMP.CONF ###

# @usage: append_config <config>
# @description:
#   append config to kdump.config
# @param1: config
append_config()
{
    log_info "- Modifying ${K_CONFIG}"
    local config="$1"

    if [[ -z "$config" ]]; then
        log_info "- Nothing to modify."
        return
    fi

    log_info "- Removing existing ${1%%[[:space:]]*} settings."
    sed -i "/^${1%%[[:space:]]*} /d" ${K_CONFIG}
    log_info "- Adding new config '$1'."
    echo "$config" >> "${K_CONFIG}"
    sync;sync;sync
}

# @usage: remove_config <config>
# @description:
#   remove config from kdump.config
# @param1: config
remove_config()
{
    log_info "- Modifying ${K_CONFIG}"
    local config="$1"

    if [[ -z "$config" ]]; then
        log_info "- Nothing to modify."
        return
    fi

    log_info "- Removing existing ${1%%[[:space:]]*} settings."
    sed -i "/^${1%%[[:space:]]*} /d" ${K_CONFIG}
    sync;sync;sync
}

# @usage: config_kdump_any <config>
# @description:
#   add a kdump config line to kdump.config
#   restart kdump service after configuring
# @param1: config
# @example:
#   config_kdump_any "kdump_post /bin/your_script"
config_kdump_any()
{
    [ $# -eq 0 ] && log_error "- Expect a config line"
    append_config "$1"
    kdump_restart
}


# @usage: label_fs <fstype> <dev> <mntpnt> <label>
# @description: add label to specified fs
# @param1: fstype
# @param2: device
# @param3: mount point
# @param4: label
label_fs()
{
    local fstype="$1"
    local dev="$2"
    local mp="$3"
    local label="$4"

    case "$fstype" in
        xfs)
            umount "$dev" &&
            xfs_admin -L "$label" "$dev" &&
            mount "$dev" "$mp"
            ;;
        ext[234])
            e2label "$dev" "$label"
            ;;
        btrfs)
            umount "$dev" &&
            btrfs filesystem label "$dev" "$label" &&
            mount "$dev" "$mp"
            ;;
        *)
            false
            ;;
    esac

    [ $? -ne 0 ] && log_error "- Failed to label $fstype with $label on $dev"
}


# @usage: config_kdump_fs <required_fstype>
# @description:
#    configure local dump target in kdump.conf
#    restart kdump service after configuring
# @param1: required_fstype  # check if fs at MP is <required_fstype>. optional.
# @param2: MP      # mount point of dump device. default to '/'
# @param3: KPATH   # specify 'path' in kdump.conf. default to '/var/crash'.
# @param4: OPTION  # 'uuid', 'label' or 'softlink'
# @param5: LABEL   # Only applicable when OPTION=label. Specifying a label to the particular fs
# @param6: RAW     # 'yes' means raw dump, default to 'no'
config_kdump_fs()
{

    log_info "- Editing kdump configuration"
    local required_fstype="$1"
    local dev=""
    local fstype=""
    local target=""

    # get dev, fstype
    if [[ "${RAW,,}" == "false" && -f "${K_RAW}" ]]; then
        dev=$(cut -d" " -f1 "${K_RAW}")
        fstype=(cut -d" " -f2 "${K_RAW}")
        rm -f "${K_RAW}"
        mkfs."${fstype[0]}" "$dev" && mount "$dev" "$MP"
    else
        dev=$(findmnt -kcno SOURCE "$MP")
        fstype=$(findmnt -kcno FSTYPE "$MP")
    fi

    if [[ -n "$required_fstype" &&  "$required_fstype" != "$fstype" ]]; then
        log_error "- Expect ${MP} to be fs_type ${required_fstype}, but it's ${fstype}"
    fi

    # get target
    case $OPTION in
        uuid)
            # some partitions have both UUID= and PARTUUID=, we only want UUID=
            target=$(blkid "$dev" -o export -c /dev/null | grep '\<UUID=')
            ;;
        label)
            target=$(blkid "$dev" -o export -c /dev/null | grep LABEL=)
            if [ -z "$target" ]; then
                label_fs "$fstype" "$dev" "$MP" "$LABEL"
                target=$(blkid "$dev" -o export -c /dev/null | grep LABEL=)
            fi
            ;;
        softlink)
            ln -s "$dev" "$dev-softlink"
            target=$dev-softlink
            ;;
        *)
            target=$dev
            ;;
    esac

    if [[ "${RAW,,}" == "true" && -n "$target" ]]; then
        append_config "raw $target"
        sed -i "/[ \t]\\$MP[ \t]/d" /etc/fstab
        echo "$dev $fstype" > "${K_RAW}"
    elif [ -n "$fstype" -a -n "$target" ]; then
        append_config "$fstype $target"
        append_config "path $KPATH"
        mkdir -p "$MP/$KPATH"
        # tell crash analyse procedure where to find vmcore
        echo "${MP%/}${KPATH}" > "${K_PATH}"
    else
        log_error "- Null dump_device/uuid/label or wrong type."
    fi

    kdump_restart
}


# @usage: config_kdump_filter <opt>
# @description:
#    configure Kdump using makedumpfile to collect vmcore.
#    restart kdump service after configuring
# @param1: opt  # options passed to makedumpfile. default to "-c -d 31"
config_kdump_filter()
{
    local opt

    if [[ -n "$1" ]]; then
        opt="$1"
    elif grep -qE '^(ssh|raw)' ${K_CONFIG}; then
        opt="-F -c -d 31"
    else
        opt="-c -d 31"
    fi

    append_config "core_collector makedumpfile ${opt}"
    kdump_restart
}

# @usage: config_kdump_sysconfig <opt>
# @description:
#    add/remove/edit configs in kdump sysconfig
# @param1: key # e.g.  KDUMP_KERNELVER
# @param2: action # remove/add/replace/
# @param3: value1
# @param4: value2  # only required for replacing
# @example:
#   config_kdump_sysconfig KDUMP_COMMANDLINE_APPEND replace nr_cpus=1 nr_cpus=4
config_kdump_sysconfig()
{
    log_info "- Updating kdump sysconfig."

    [ $# -lt 3 ] && log_error "- Expect at least 3 args."
    local key=$1
    local action=$2
    local value1=$3
    local value2=$4

    log_info "- Edit: ${action};${key};${value1};${value2}"
    case $action in
        add)
            # Note "add" will not add spaces between values automatically,
            # because it doesn't know if this is the first value or not in the setting.
            # So pls add space explicitly in your call if needed:
            #       config_kdump_sysconfig KEXEC_ARGS add " value2"
            sed -i  /^"$key="/s/\"/"$value1"\"/2 "${K_SYS_CONFIG}"
            ;;
        remove)
            sed -i  /^"$key="/s/"$value1"//g "${K_SYS_CONFIG}"
            ;;
        replace)
            [ -z "$value2" ] && log_error "- Missing new_value for replacing."
            sed -i  /^"$key="/s/"$value1"/"$value2"/g "${K_SYS_CONFIG}"
            ;;
        *)
            log_error "- Invalid action '${action}' for editing kdump sysconfig."
            ;;
    esac
    [ $? -ne 0 ] && log_error "- Failed to updated kdump sysconfig."
    sync;sync;sync
    # it requires to reload the crash kernel for kdump
    kdump_restart
}

# @usage: config_sw_raid
# @description: config software raid
# @global param1: RAID_DEVICES  # devices to create a RAID
# @global param2: RAID_LEVEL  # valid values: 0,1,5
config_sw_raid()
{
    local device_name=("")
    local count=0
    local expect_count=0

    for i in $RAID_DEVICES; do
        device_name[$count]=$(findmnt -kcno SOURCE "$i")
        [ -z ${device_name[$count]} ] && {
            log_error "- No device is found at $i."
        }

        (( count++ ))
    done

    log_info "- The ready disk(s): ${device_name[*]}"

    # validate RAID_DEVICE and RAID_LEVEL
    if [ "${RAID_LEVEL}" -eq 0 ] || [ "${RAID_LEVEL}" -eq 1 ]; then
        expect_count=2
    elif [ "${RAID_LEVEL}" -eq 5 ]; then
        expect_count=3
    else
        log_error "- Invalid raid level: $RAID_LEVEL"
    fi

    [ "${count}" -lt "${expect_count}" ] && {
        log_error "- Expect ${expect_count} devices for raid${RAID_LEVEL}. \
But only ${count} provided."
    }

    # release disk before create raid devices
    for i in "${device_name[@]}"; do
        umount "$i"
    done

    log_info "- Creating raid${RAID_LEVEL} devices."
    release_md_device

    local cmd="mdadm --create ${MD_DEVICE} --run --level raid${RAID_LEVEL}"
    case $RAID_LEVEL in
        0)
            eval $cmd --raid-devices 2 "${device_name[0]}" "${device_name[1]}"
            [ $? != 0 ] && log_error "- Create raid0 failed."
            mdadm --detail "${MD_DEVICE}"
            ;;
        1)
            eval $cmd --raid-devices 2 "${device_name[0]}" "${device_name[1]}"
            [ $? != 0 ] && log_error "- Create raid1 failed."
            mdadm --detail "${MD_DEVICE}"
            ;;
        5)
            eval $cmd --raid-devices 3 "${device_name[0]}" "${device_name[1]}" "${device_name[2]}"
            [ $? != 0 ] && log_error "- Create raid5 failed."
            mdadm --detail "${MD_DEVICE}"
            ;;
        *)
            log_error "- Invalid raid level: $RAID_LEVEL"
            ;;
    esac

    log_info "- Raid${RAID_LEVEL} is created at ${MD_DEVICE}"

    mkfs.ext4 "${MD_DEVICE}" > /dev/null
    mkdir -p "$MP"
    log_info "- Mounting ${MD_DEVICE} at ${MP}"
    mount "${MD_DEVICE}" "${MP}" || log_error "- Failed to mount ${MD_DEVICE} $MP."

    save_md_config

    # Save RAID device for test clean up
    echo "${MD_DEVICE}" > "${K_RAID}"
    echo "${RAID_DEVICES}" >> "${K_RAID}"
}

# @usage: release_md_device
# @description: release md device $MD_DEVICE if it's in use.
# global param1: MD_DEVICE # default to /dev/md0
release_md_device()
{
    mdadm --detail "${MD_DEVICE}" || {
        log_info "- ${MD_DEVICE} is available!"
        return
    }

    Log "- Releasing ${MD_DEVICE}"
    {
        mdadm --stop "${MD_DEVICE}"
        Log " - ${MD_DEVICE} is available now!"
    }
}

# @usage: save_md_config
# @description: save mdadm config and update device mountings
# global param1: RAID_DEVICE # devices to create a RAID
save_md_config()
{
    log_info "- Saving mdadm config to /etc/mdadm.conf"
    mdadm --detail --brief "${MD_DEVICE}" >> /etc/mdadm.conf
    #mdadm -E -s -v >> /etc/mdadm.conf
    report_file /etc/mdadm.conf

    log_info "- Adding ${MD_DEVICE} to /etc/fstab"

    for i in $RAID_DEVICES; do
        sed -i "\#$i#d" /etc/fstab
    done

    echo "${MD_DEVICE}  $MP         ext4    defaults    0   0" >> /etc/fstab
    report_file /etc/fstab
}


###  Triggering Crash ###

# @usage: trigger_sysrq_crash
# @description: trigger sysrq-trigger crash
trigger_sysrq_crash()
{
    touch "${C_REBOOT}"
    sync;sync;sync

    reset_efiboot

    log_info "- Triggering crash."
    echo c > /proc/sysrq-trigger

    sleep 60
    log_error "- Failed to trigger crash after waiting for 60s."
}


# @usage: trigger_crasher <opt>
# @description:
#       trigger system crash in crasher module
#       /proc/crasher has to be set up before calling this method
# @parma1: opt
trigger_crasher()
{
    [ $# -lt 1 ] && log_error "- Missing opt to trigger crasher"

    local opt=$1
    touch "${C_REBOOT}"

    reset_efiboot

    # enable panic_on_oops
    echo 1 > /proc/sys/kernel/panic_on_oops
    sync;sync;sync

    log_info "- Triggering crash."
    # opt=0 : panic()
    # opt=1 : BUG()
    # opt=2 : a=0;a[1]='A'
    # opt=3 : spin_lock_irq()
    echo $opt > /proc/crasher

    sleep 60
    log_error "- Failed to trigger crash after waiting for 60s."
}

# @usage: trigger_crasher <test_name>
# @description:
#       run <test_name> and exit
# @parma1: test_name
run_test()
{
    func=$1

    log_info "- Start"

    ${func}

    ready_to_exit
}
