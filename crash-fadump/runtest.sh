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

crash_fadump()
{
    if [ ! -f "${C_REBOOT}" ]; then

        log_info "- Checking if machine supports FAD"
        [[ ! -f /proc/device-tree/rtas/ibm,extended-os-term ||\
           ! -f /proc/device-tree/rtas/ibm,configure-kernel-dump-sizes || \
           ! -f /proc/device-tree/rtas/ibm,configure-kernel-dump \
        ]] && log_error "- FAD not supported."

        grep -q 'fadump' <<< "${KERARGS}" || {
            KERARGS+=" fadump=on"
        }
        kdump_prepare fadump
        report_system_info fadump

        [ "$(cat /sys/kernel/fadump_enabled)" == "1" ] || log_error "- Fadump is not enabled!"
        [ "$(cat /sys/kernel/fadump_registered)" == "1" ] || log_error "- Fadump is not registered!"

        trigger_sysrq_crash
    else
        rm -f "${C_REBOOT}"
        # release memory
        echo 1 > /sys/kernel/fadump_release_mem

        validate_vmcore_exists
    fi
}

run_test crash_fadump

