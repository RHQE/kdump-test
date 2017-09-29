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
# Author: Qiao Zhao <qzhao@redhat.com>

. ../lib/kdump.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

insert_hung_task_module()
{
    log_info "- Build hung-task.ko module."
    mkdir hung-task
    cd hung-task
    cp ../hung-task.c .
    cp ../Makefile.hung-task Makefile
    cp ../run-hung-task.c .

    unset ARCH
    make && make install || log_error "- Can not make/insmod module."
    log_info "- Sleep 20 seconds to wait run-hung-task trigger panic."
    sleep 20
    ./run-hung-task
    export ARCH=$(uname -m)

    cd ..
}

crash-hung-task()
{
    if [[ ! -f "${C_REBOOT}" ]]; then
        kdump_prepare
        report_system_info
        reset_efiboot

        # Trigger hung-task
        touch "${C_REBOOT}"
        sync

        log_info "- Enable kernel.hung_task_panic=1"
        sysctl -w kernel.hung_task_panic=1
        [[ $? -ne 0 ]] && log_error "- Error to sysctl -w kernel.hung_task_panic=1."

        log_info "- Triggering crash."
        insert_hung_task_module

        # Wait for a while
        sleep 600
        log_error "- Failed to trigger panic_on_warn after waiting for 600s."

    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

run_test crash-hung-task

