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

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

dump_nr_cpus()
{
    if [ ! -f "${C_REBOOT}" ]; then
        kdump_prepare

        local cpu_count=$(grep -c "processor" /proc/cpuinfo)
        log_info "- Number of processors: ${cpu_count}"

        [ -z "${TESTARGS}" ] &&
        {
            if [ ${cpu_count} -le ${K_CPU_THRESHOLD} ]; then
                TESTARGS=2
            else
                TESTARGS=4
            fi
        }

        local key=KDUMP_COMMANDLINE_APPEND
        config_kdump_sysconfig $key replace nr_cpus=1 nr_cpus=${TESTARGS}
        report_system_info
        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

run_test dump_nr_cpus
