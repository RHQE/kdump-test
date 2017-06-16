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


. ../lib/crash.sh

analyse_crash_gcore_cmd()
{
    # crash-gcore-command is not supported in s390x/s390
    if [[ "$(uname -m)" =~ "s390" ]]; then
        log_warn "- Crash plugin crash-gcore-command is not supported in s390x/s390"
    fi

    crash_prepare

    local package_name="crash-gcore-command"
    local gcore_log="gcore.vmcore.log"
    local gcore
    local vmx
    local core

    install_rpm "${package_name}"
    gcore=$(rpm -ql "${package_name}" | grep gcore.so)
    vmx="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    [ ! -f "${vmx}" ] && log_error "- Unable to find vmlinux."
    core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    # Get the pid/proc name
    cat<<EOF > pid.cmd
bt|grep "PID"
q
EOF
    report_file pid.cmd
    log_info "- # crash ${vmx} ${core} -s -i pid.cmd | tee ${gcore_log}"
    crash "${vmx}" "${core}" -s -i pid.cmd 2>&1 | tee "${gcore_log}"
    [[ ${PIPESTATUS[1]} -eq "0" ]] || {
        log_error "- Failed to run crash with pid.cmd. See logs in ${gcore.log}"
    }

    log_info "- Getting pid/proc from ${gcore_log}"
    local pid
    local proc
    if [ -s "${gcore_log}" ]; then
        pid=$(grep "PID" ${gcore_log} | awk '{print $2}')
        proc=$(grep "PID"  ${gcore_log} | awk '{print $8}'| cut -d\" -f2)
        log_info "- pid: ${pid}"
        log_info "- proc: ${proc}"
    else
        log_error "- ${gcore_log} is empty!"
    fi

    # Run gcore
    cat<<EOF >gcore.cmd
extend ${gcore}
bt | grep ${pid}
gcore ${pid}
q
EOF
    report_file gcore.cmd
    log_info "- # crash ${vmx} ${core} -s -i gcore.cmd | tee -a ${gcore_log}"
    crash ${vmx} ${core} -s -i gcore.cmd 2>&1 | tee -a ${gcore_log}
    [[ ${PIPESTATUS[1]} -eq "0" ]] || {
        log_error "- Failed to run crash with pid.cmd. See logs in ${gcore.log}"
    }
    report_file ${gcore_log}

    grep -q 'gcore.so: shared object loaded' ${gcore_log} || {
        log_error "Failed to load gcore.so"
    }
    [ -s "core.${pid}.${proc}" ] || log_error "- File core.${pid}.${proc} doesn't exist."

    gdb "core.${pid}.${proc}" --quiet -ex q 2>&1 | tee gdb.log
    [[ ${PIPESTATUS[1]} -eq "0" ]] || {
        log_error "- Fail to process core.${pid}.${proc} using gdb. See logs in gdb.log"
    }
    report_file gdb.log


    rm -f gdb.log "${gcore_log}"
    rm -f *.cmd
}

run_test analyse_crash_gcore_cmd
