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

crash-oops-oom()
{
    if [[ ! -f "${C_REBOOT}" ]]; then
        kdump_prepare
        report_system_info

        # Enable panic_on_oom
        sysctl -w vm.panic_on_oom=1

        # Prepare for panic
        reset_efiboot
        touch "${C_REBOOT}"
        sync

        # Trigger panic_on_oom
        log_info "- Triggering panic_on_oom."
        local pid=0
        gcc -o bigmem ./bigmem.c
        ./bigmem &
        pid=$(echo $!)

        log_info "- Set oom_score_adj of pid $pid to 500."
        [ "$pid" -ne 0 ] && echo 500 > /proc/$pid/oom_score_adj

        # Wait for a few minutes for oom panic
        sleep 600
        log_error "- Failed to trigger panic_on_oom after waiting for 10 mins."
    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

run_test crash-oops-oom

