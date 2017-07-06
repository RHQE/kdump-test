#!/usr/bin/env bash

# Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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
# Author: Xiaowu Wu <xiawu@redhat.com>

RAID_DEVICES=${RAID_DEVICES:-"/raid1 /raid2"}
RAID_LEVEL=${RAID_LEVEL:-"0"}
MP=${MP:-"/mnt/raid"}

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh


dump_sw_raid()
{
    if [ ! -f "${C_REBOOT}" ]; then
        kdump_prepare
        install_rpm mdadm

        config_sw_raid
        config_kdump_fs

        report_system_info

        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

# ------ Start Here -------
run_test dump_sw_raid
