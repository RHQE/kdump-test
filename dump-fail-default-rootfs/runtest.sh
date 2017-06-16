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
# Author: Yahuan Cong <ycong@redhat.com>

MP=${MP:-"/ext4"}

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

dump_fail_default_rootfs()
{
    if [ ! -f "${C_REBOOT}" ]; then
        kdump_prepare

        config_kdump_fs
        if [[ $K_DIST_VER -le 6 ]]; then
            config_kdump_any "default mount_root_run_init"
        else
            config_kdump_any "default dump_to_rootfs"
        fi
        config_kdump_filter "-nosuchoption"
        report_system_info

        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        # Expect vmcore to be dumped to root not $MP
        echo "${K_DEFAULT_PATH}" > "${K_PATH}"
        validate_vmcore_exists "dmesg"
    fi
}

run_test dump_fail_default_rootfs
