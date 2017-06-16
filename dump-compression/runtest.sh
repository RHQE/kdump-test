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
# Author: Yahuan Cong <ycong@redhat.com>
# Update: Xiaowu Wu <xiawu@redhat.com>

TESTARGS=${TESTARGS:="-c"}

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

dump_compression()
{
    if [ ! -f "${C_REBOOT}" ]; then
        kdump_prepare
        # allowed compression options: -c -l -p

        [[ "${TESTARGS}" =~ ^(-c|-l|-p)$ ]] || {
            log_error "- Invalid compression option ${TESTARGS}"
        }
        config_kdump_filter "${TESTARGS} -d 31"
        report_system_info

        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

run_test dump_compression

