#!/usr/bin/env bash

# Library for Kdump Test Reporting

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
# Author: Ziqian Sun <zsun@redhat.com>

. ../lib/kdump.sh

# @usage: report_hw_info
# @description: report hardware info
report_hw_info()
{
    log_info "- Reporting system hardware info:"

    echo -e "CPU Info:"     >> "${K_HWINFO_FILE}"
    lscpu >> "${K_HWINFO_FILE}"

    echo -e "\n----\n"      >> "${K_HWINFO_FILE}"
    echo -e "Memory Info:"  >> "${K_HWINFO_FILE}"
    free -h >> "${K_HWINFO_FILE}"

    echo -e "\n----\n"      >> "${K_HWINFO_FILE}"
    echo -e "Storage Info:" >> "${K_HWINFO_FILE}"
    lsblk >> "${K_HWINFO_FILE}"

    echo -e "\n----\n"      >> "${K_HWINFO_FILE}"
    echo -e "Network Info:" >> "${K_HWINFO_FILE}"
    ip link >> "${K_HWINFO_FILE}"
    for i in $(ip addr | grep -i ': <' | grep -v 'lo:' | awk '{print $2}' | sed "s/://g") ; do
        echo "--$i--" >> "${K_HWINFO_FILE}"
        ethtool -i $i >> "${K_HWINFO_FILE}"
    done

    report_file "${K_HWINFO_FILE}"
}

# @usage: report_lsinitrd
# @description: report file list in initramfs*kdump.img
# @param1: img_key # default to "kdump.img"
report_lsinitrd()
{
    local img_key=${1:-"kdump.img"}

    log_info "- Reporting the file list in initramfs*${img_key}:"

    local initramfs_name=$(ls /boot | grep "$(uname -r)${img_key}")
    [ -z "${initramfs_name}" ] && log_warn "- No initramfs*${img_key} is found."

    lsinitrd "/boot/${initramfs_name}" >> "${K_INITRAMFS_LIST}"
    report_file "${K_INITRAMFS_LIST}"
}


# @usage: report_system_info
# @description: report system info inclufing hw/initrd/kdump.config
# @param1:fadump (optional) # fadump is using initramfs*.img, not initramfs*kdump.img
report_system_info()
{
    local opt=${1}

    log_info "- Reporting system info."
    report_hw_info

    if [ "${opt}" == "fadump" ]; then
        report_lsinitrd ".img"
    else
        report_lsinitrd
    fi

    log_info "- Reporting kdump config"
    grep -v ^# "${K_CONFIG}" | grep -v ^$ > ./kdump.config
    report_file ./kdump.config

    log_info "- Reporting kdump sys config"
    grep -v ^# "${K_SYS_CONFIG}" | grep -v ^$ > ./kdump.sysconfig
    report_file ./kdump.sysconfig

    rm ./kdump.config
    rm ./kdump.sysconfig
}
