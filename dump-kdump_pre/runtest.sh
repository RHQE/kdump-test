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
# Author: Xiaowu Wu <xiawu@redhat.com>

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

dump_kdump_pre()
{
    if [ ! -f "${C_REBOOT}" ]; then
        kdump_prepare

        ./"$K_SCRIPT"
        config_kdump_any "kdump_pre /bin/kdump-pre.sh"
        rm /bin/kdump-{pre,post}.sh; sync

        report_system_info
        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        report_file /root/kdump-pre.log
        [ -f /root/kdump-pre.log ] && error_log "- Not found kdump-pre.log"
        validate_vmcore_exists
    fi
}

run_test dump_kdump_pre

