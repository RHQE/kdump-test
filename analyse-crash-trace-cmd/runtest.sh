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
# Update: Xiaowu Wu <xiawu@redhat.com>

. ../lib/crash.sh

enable_tracer()
{
    log_info "- Check & mount debugfs"
    if ! grep -q debugfs /proc/filesystems; then
        log_error "- No debugfs available"
    else
        mount -t debugfs nodev ${DEBUG_PATH}
    fi
    local current_tracer=wakeup

    echo 1 > ${TRACE_PATH}/tracing_on

    echo " - tracer: ${current_tracer} enabled"
    echo "${current_tracer}" > ${TRACE_PATH}/current_tracer

    log_info "- TRACING_ENABLED: " $(cat "${TRACE_PATH}/tracing_on")
    log_info "- AVAILABLE_TRACERS: " $(cat "${TRACE_PATH}/available_tracers")
    log_info "- CURRENT_TRACER: " $(cat "${TRACE_PATH}/current_tracer")

    grep "tracer: ${current_tracer}" "${TRACE_PATH}/trace"
    [ $? -ne 0 ] && log_error "- Tracer is not enabled. No trace data in pipe!"
}

analyse_crash_trace_cmd()
{
    crash_prepare

    local package_name="crash-trace-command"
    local tracer
    local nr_core
    local dump_dir=${K_TMP_DIR}/DUMP_M_DIR

    install_rpm "${package_name}"
    tracer=$(rpm -ql "${package_name}" | grep trace.so)
    nr_core=$(grep processor /proc/cpuinfo | wc -l)
    mkdir -p "${dump_dir}"

    enable_tracer

    #Prepare crash.cmd
    cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
extend ${tracer}
help trace
trace dump
ls ${K_TMP_DIR}/*
trace dump -m ${dump_dir}
ls ${K_TMP_DIR}/*
trace show | head
trace show -f nocontext_info | head
trace show -f context_info | head
trace show -f sym_offset | head
trace show -f nosym_offset | head
trace show -f sym_addr | head
trace show -f nosym_addr | head
trace show -f nograph_print_duration | head
trace show -f graph_print_duration | head
trace show -f nograph_print_overhead | head
trace show -f graph_print_overhead | head
trace show -f graph_print_abstime | head
trace show -f nograph_print_abstime | head
trace show -f nograph_print_cpu | head
trace show -f graph_print_cpu | head
trace show -f graph_print_proc | head
trace show -f nograph_print_proc | head
trace show -f graph_print_overrun | head
trace show -f nograph_print_overrun | head
trace show -c 0 | head
EOF

    [ "${nr_core}" -gt 1 ] && {
        echo "trace show -c 0,$((${NR_CORE}-1)) | head" >> "${K_TMP_DIR}/crash.cmd"
        echo "trace show -c 0-$((${NR_CORE}-1)) | head" >> "${K_TMP_DIR}/crash.cmd"
    }

    echo "extend -u ${tracer}" >> "${K_TMP_DIR}/crash.cmd"
    echo "exit" >> "${K_TMP_DIR}/crash.cmd"

    local vmx="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    [ ! -f "${vmx}" ] && log_error "- Unable to find vmlinux."

    local core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    crash_cmd "" "${vmx}" "${core}" "${K_TMP_DIR}/crash.cmd" check_crash_output
}

run_test analyse_crash_trace_cmd
