#!/usr/bin/env bash

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

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/log.sh

KEXEC_VER=${KEXEC_VER:-"$(uname -r)"}

kexec_boot()
{
    if [ ! -f "${C_REBOOT}" ]; then
        install_rpm kexec-tools

        touch "${C_REBOOT}"
        report_system_info

        # load new kernel
        local cmdline="$(cat /proc/cmdline) rd.memdebug=3 earlyprintk=serial"
        local cmd="kexec -l"

        # if secureboot is enabled
        if [ -f /sys/kernel/security/securelevel ]; then
            local securelevel=$(cat /sys/kernel/security/securelevel)
            log_info "- Secureboot is enabled."
            [ "$securelevel" == "1" ] && cmd="${cmd} -s"
        fi

        ${cmd} /boot/vmlinuz-"$KEXEC_VER" --initrd=/boot/initramfs-"$KEXEC_VER".img --command-line="${cmdline}"
        [ "$(cat /sys/kernel/kexec_loaded)" = "0" ] && log_error "- Loading new kernel failed."

        log_info "- Load new kernel $KEXEC_VER successful."
        log_info "- Kexec rebooting to new kernel $KEXEC_VER."
        reboot_system
        sleep 60 && log_error "- Failed to reboot to new kernel $KEXEC_VER."
    else
        rm -f "${C_REBOOT}"
        grep "rd.memdebug=3" /proc/cmdline || log_error "- Kexec boot failed."
        log_info "- Kexec boot to new kernel $KEXEC_VER successfully."
    fi
}

run_test kexec_boot
