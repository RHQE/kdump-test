#!/usr/bin/env bash

# Library for Crash Test

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

. ../lib/kdump.sh

K_CRASH_REPORT="${K_TMP_DIR}/crash_report.txt"  # Filtered crash cmd output for error/warns
SKIP_WARNING_PAT=${SKIP_WARNING_PAT:-}

DEBUG_PATH=/sys/kernel/debug
TRACE_PATH=${DEBUG_PATH}/tracing

# @usage: get_vmcore_path <vmcore_format>
# @description:
#   get the full path to the vmcore
#   it searches vmcore/vmcroe.flat/vmcore-dmesg based on the <vmcore_format>
# @param1: vmcore_format # "vmcore" "flat" "dmesg". default to "dmesg"
# @return: if >1 vmcore is found, exit with error.
get_vmcore_path()
{
    local vmcore_format=$1
    local vmcore_path
    local vmcore_name

    case "${vmcore_format}" in
        "flat")
            vmcore_name="vmcore.flat"
            ;;
        "dmesg")
            vmcore_name="vmcore-dmesg.txt"
            ;;
        *)
            vmcore_name="vmcore"
            ;;
    esac

    [ -f "${K_PATH}" ] && vmcore_path=$(cat "${K_PATH}") || vmcore_path="${K_DEFAULT_PATH}"

    [ -f "${K_NFS}" ] && {
        local export_path
        export_path=$(cat "${K_NFS}")
        vmcore_path=${export_path}${vmcore_path}
    }

    [ ! -d "${vmcore_path}" ] && {
        log_error "- Failed to find vmcore. ${vmcore_path} is not a directory"
    }

    local vmcore_full_path
    vmcore_full_path=$(find "${vmcore_path}" -newer "${K_CONFIG}" -name "${vmcore_name}" -type f | sort -r | head -n 1)
    echo "${vmcore_full_path}"
}


# @usage: validate_vmcore_exists <vmcore_format>
# @description:
#   check whether the vmcore exists
#   it checks vmcore/vmcroe.flat/vmcore-dmesg based on the <vmcore_format>
# @param1: vmcore_format # "vmcore" "flat" "dmesg".
#          if not specified, validate existence of both "vmcore" and "dmesg"
# @return: if no vmcore is found, exit with error.
validate_vmcore_exists()
{
    local vmcore_format=$1
    local vmcore_full_path

    log_info "- Validate if ${vmcore_format:-vmcore} exists"
    vmcore_full_path=$(get_vmcore_path "${vmcore_format}")

    [ -z "${vmcore_full_path}" ] && log_error "- No vmcore file is found."
    log_info "- Found vmcore file at ${vmcore_full_path}"

    # if vmcore format is not specified, check vmcore-dmesg as well.
    [[ -z ${vmcore_format} ]] && {
        log_info "- Validate if vmcore-dmesg.txt exists"
        vmcore_full_path=$(get_vmcore_path "dmesg")
        if [ ! -z "${vmcore_full_path}" ]; then
            log_info "- Found vmcore-dmesg file at ${vmcore_full_path}"
        else
            log_error "- No vmcore-dmesg is found."
        fi
    }
}

# @usage: validate_vmcore_not_exists <vmcore_format>
# @description:
#   check whether the vmcore doesn't exists
#   it checks vmcore/vmcroe.flat/vmcore-dmesg based on the <vmcore_format>
# @param1: vmcore_format # "vmcore" "flat" "dmesg". default to "dmesg"
# @return: if vmcore is found, exit with error.
validate_vmcore_not_exists()
{
    local vmcore_format=$1
    local vmcore_full_path

    log_info "- Validate if vmcore not exists"
    vmcore_full_path=$(get_vmcore_path "${vmcore_format}")

    if [ ! -z "${vmcore_full_path}" ]; then
        log_error "- Found vmcore file at ${vmcore_full_path}"
    else
        log_info "- No vmcore file is found."
    fi
}


# @usage: crash_cmd <args> <vmx> <vmcore> <crash_cmd> <func_check_output>
# @description: run crash cmd to analyze vmcore with pre-defined crash.cmd
# @param1: args  # crash args
# @param2: vmx   # location of vmlinux
# @param3: core  # location of vmcore
# @param4: crash_cmd_file # file contains a set of crash cmd
# @param5: func_check_output # the func to validate output. (optional)
crash_cmd()
{
    local args=$1
    local vmx=$2
    local core=$3
    local crash_cmd_file=$4
    local func_check_output=$5

    local log_suffix
    [ -z "$core" ] && log_suffix=log || log_suffix="${core##*/}.log"

    [ -f "${crash_cmd_file}" ] || log_error "- No such file ${crash_cmd_file}."

    local retval
    log_info "- # crash ${args} -i ${crash_cmd_file} ${vmx} ${core}"
    # The EOF part is a workaround of a crash utility bug - crash utility
    # session would fail during the initialization when invoked from a
    # script without a control terminal.
    # This issue has been fixed in crash 4.0-7.2.1
    if [ -z "${core}" ]; then
        crash ${args} -i "${crash_cmd_file}"\
            > "${crash_cmd_file}.${log_suffix}" 2>&1 <<EOF
EOF
    else
        crash ${args} -i "${crash_cmd_file}" "${vmx}" "${core}" \
            > "${crash_cmd_file}.${log_suffix}" 2>&1 <<EOF
EOF
    fi

    retval=$?
    report_file "${crash_cmd_file}"
    report_file "${crash_cmd_file}.${log_suffix}"


    # check return code of the crash command
    [ $retval == 0 ] || log_error "- Crash returns error code ${retval}"

    # check output of the crash command
    if [ -n "${func_check_output}" ]; then
        ${func_check_output} "${crash_cmd_file}.${log_suffix}"
        [ $? == 0 ] || log_error "- Failed to run: \
            ${func_check_output} ${crash_cmd_file}.${log_suffix}"
    fi
    log_info "- Done running and checking crash cmd."
}

# @usage: check_crash_output <output_file>
# @description: check crash output for errors or warns
# @param1: output_file  # file where the error/warning msg will be checked.
check_crash_output()
{
    output_file=$1

    rm -f "${K_CRASH_REPORT}"
    touch "${K_CRASH_REPORT}"

    log_info "- Checking crash output for errors"
    log_info "- Search following keywords for errors."
    log_info "- 'fail'"
    log_info "- 'error'"
    log_info "- 'invalid'"

    log_info "- Following patterns will be skipped when searching for errors."

    # Any command that translates addresses found on the stack or in memory
    # into symbol values would show this log
    # e.g. event_attr_PM_L2_CO_FAIL_BUSY_p+24 000000003eb46c8a
    log_info "- '_FAIL_'"

    # This is not a bug, but simply a left-over exception frame that was
    # found by the "bt -E" option
    log_info "- 'Instruction bus error  [400] exception frame:'"

    # In aarch64 vmcore analyse testing, the "err" string that is passed to __die() is
    # preceded by "Internal error: ", shown here in "arch/arm64/kernel/traps.c".
    # PANIC: "Internal error: Oops: 96000047 [#1] SMP" (check log for details)'
    log_info "- 'PANIC'"

    # Dave Anderson <anderson@redhat.com> updated the pageflags_data in
    # crash-7.0.2-2.el7 to include the use of '00000002: error'
    log_info "- '00000002: error'"

    # We have seen those false negative results before
    # e00000010a3b2980 e000000110198fb0 e000000118f09a10 REG
    # /var/log/cups/error_log
    log_info "- 'error_'"

    # flags: 6 (KDUMP_CMPRS_LOCAL|ERROR_EXCLUDED)
    log_info "- 'ERROR_'"

    # e00000010fe82c60 e000000118f0a328 REG
    # usr/lib/libgpg-error.so.0.3.0
    log_info "- '-error'"

    # [0] divide_error
    # [16] coprocessor_error
    # [19] simd_coprocessor_error
    log_info "- '_error'"

    # Data Access error  [301] exception frame:
    log_info "- 'Data Access error'"

    # fph = {{
    #     u = {
    #       bits = {3417217742307420975, 65598},
    #       __dummy = <invalid float value>
    #     }
    #   }, {
    log_info "- 'invalid float value'"

    # [ffff81007e565e48] __down_failed_interruptible at ffffffff8006468b
    log_info "- '_fail'"

    # failsafe_callback_cs = 97,
    # failsafe_callback_eip = 3225441872,
    log_info "- 'failsafe'"

    # [ffff81003ee83d60] do_invalid_op at ffffffff8006c1d7
    # [6] invalid_op
    # [10] invalid_TSS
    log_info "- 'invalid_'"

    # [253] invalidate_interrupt
    log_info "- 'invalidate'"

    # name: a00000010072b4e8  "PCIBR error"
    log_info "- 'PCIBR error'"

    # name: a000000100752ce0  "TIOCE error"
    log_info "- 'TIOCE error'"

    # beaker testing harness has a process 'beah-beaker-bac' which
    # will open a file named  /var/beah/journals/xxxxx/debug/task_beah_unexpected
    # which will be showed by 'foreach files'
    log_info "- 'task_beah_unexpected'"

    log_info "- ERROR MESSAGES BEGIN"
    grep -v -e '_FAIL_' \
         -e 'PANIC:' \
         -e 'Instruction bus error  \[400\] exception frame:' \
         -e '00000002: error' \
         -e 'error_' \
         -e 'ERROR_' \
         -e '-error' \
         -e '_error' \
         -e 'Data Access error' \
         -e 'invalid float value' \
         -e '_fail' \
         -e 'failsafe' \
         -e 'invalid_' \
         -e 'invalidate' \
         -e 'PCIBR error' \
         -e 'TIOCE error' \
         -e 'task_beah_unexpected' \
         "${output_file}" |
    if [ -n "${SKIP_ERROR_PAT}" ]; then grep -v -e "${SKIP_ERROR_PAT}"; else cat; fi |
        grep -i \
             -e 'fail' \
             -e 'error' \
             -e 'invalid' \
             2>&1 | tee -a "${K_CRASH_REPORT}"
    local error_found=${PIPESTATUS[2]}
    log_info "- ERROR MESSAGES END"


    log_info "- Checking crash output for warnings"
    log_info "- Search following words for warnings."
    log_info "- 'warning'"
    log_info "- 'warnings'"
    log_info "- 'cannot'"

    log_info "- Following patterns will be skipped when searching for warnings."

    log_info "- 'mod: cannot find or load object file for crasher module'"
    log_info "- 'mod: cannot find or load object file for altsysrq module'"
    log_info "- 'mod: cannot find or load object file for crash_warn module'"

    log_info "- 'cannot determine file and line number'"

    # It's impossible for Crash to determine the starting backtrace point for
    # the other active (non-crashing) vcpus.
    # msg: cannot be determined: try -t or -T options"
    log_info "- 'cannot be determined: try -t or -T options'"

    # Messages from KASLR
    log_info "- 'WARNING: kernel relocated'"

    log_info "- WARNING MESSAGES BEGIN"
    grep -v \
         -e "mod: cannot find or load object file for crasher module" \
         -e "mod: cannot find or load object file for altsysrq module" \
         -e "mod: cannot find or load object file for crash_warn module" \
         -e "cannot determine file and line number" \
         -e "cannot be determined: try -t or -T options" \
         -e "WARNING: kernel relocated" \
         "${output_file}" |
    if [ -n "${SKIP_WARNING_PAT}" ]; then grep -v -e "${SKIP_WARNING_PAT}"; else cat; fi |
        grep -iw \
             -e 'warning' \
             -e 'warnings' \
             -e 'cannot' \
             2>&1 | tee -a "${K_CRASH_REPORT}"
    local warn_found=${PIPESTATUS[2]}
    log_info "- WARNING MESSAGES END"

    [ -f "${K_CRASH_REPORT}" ] && report_file "${K_CRASH_REPORT}"

    if [ ${warn_found} -eq 0 ]; then
        log_warn "- Found warnings in Crash commands. \
            See ${output_file} for more details."
    fi

    if [ ${error_found} -eq 0 ]; then
        log_error "- Found errors in Crash commands. \
            See ${output_file} for more details."
    fi

    log_info "- Finished analysing crash output."
}

# @usage: check_gdb_output <output_file>
# @description: check gdb output for errors or warns
# @param1: output_file  # file where the error/warning msg will be checked.
check_gdb_output()
{
    output_file=$1

    rm -f "${K_CRASH_REPORT}"
    touch "${K_CRASH_REPORT}"

    log_info "- Checking crash output for errors."
    log_info "- Search following words for errors."
    log_info "- 'fail'"
    log_info "- 'error'"
    log_info "- 'invalid'"

    log_info "- Following patterns will be skipped when searching for warnings."
    log_info "- 'warning: shared library handler failed to enable breakpoint'"


    if grep -v 'warning: shared library handler failed to enable breakpoint' \
        "${output_file}" |
        grep -i -e 'fail' \
                -e 'error' \
                -e 'invalid' \
       2>&1; then
        log_error "- Found errors/warnings in GDB commands. \
            See ${output_file} for more details."
    else
        log_info "- Finished analysing GDB output.\
            See ${output_file} for more details."
    fi

}

