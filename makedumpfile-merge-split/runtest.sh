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
# Author: Guangze Bai <gbai@redhat.com>
# Update: Xiaowu Wu <xiawu@redhat.com>

. ../lib/crash.sh

DUMPLV=${DUMPLV:="31"}
DUMPFILE=${DUMPFILE:=${K_TMP_DIR}/vmcore.$(date +%s)}
MISC=${MISC:=""}
CMPRSS=${CMPRSS:=""}
EPPIC=${EPPIC:=""}
CONFIG=${CONFIG:="scrub.conf"}
VMLINUX="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"


verify_scrub()
{
    local log=${K_TMP_DIR}/veri_scrub.log

    expect -c '
      set timeout -1
      spawn crash --hex --no_scroll '${VMLINUX}' '${DUMPFILE}'
      log_file -noappend '${log}'
      expect -re "TASK: (\[^\[:blank:]]+)"; set t $expect_out(1,string)
      expect "crash>"; send "p jiffies\r"
      expect "crash>" {
          send "list task_struct.tasks -s task_struct.utime -h $t\r"
      }
      expect "crash>"; send "q\r"
    '

    report_file "${log}"
    while read line; do
        if [[ "${line}" =~ (jiffies|utime)\ =\ .*0x([[:xdigit:]]+) && \
          ! "${BASH_REMATCH[2]}" =~ ^(58)+$ ]]; then
            return 1
        fi
    done < "${log}"
    return 0
}


parse_option()
{
    local str=''
    [ "${CMPRSS}"  ] && str+="${CMPRSS}"
    [ "${DUMPLV}"  ] && str+=" -d ${DUMPLV}"
    [ "${VMLINUX}" ] && str+=" -x ${VMLINUX}"
    [ "${MISC}"    ] && str+=" ${MISC}"
    [ "${CONFIG}"  ] && str+=" --config ${CONFIG}"
    [ "${EPPIC}"   ] && str+=" --eppic ${EPPIC}"
    echo "${str}"
}


makedumpfile_merge_split()
{
    crash_prepare
    # in case kernel is updated after crash_prepare()
    VMLINUX="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"

    [ ! -f "${VMLINUX}" ] && log_error "- Unable to find vmlinux."

    local core
    core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    local split_cmd
    local merge_cmd
    local dump_files="dumpfile_{1,2,3}"
    local retval

    split_cmd="makedumpfile --split $(parse_option) ${core} ${dump_files}"
    merge_cmd="makedumpfile --reassemble ${dump_files} ${DUMPFILE}"

    log_info "- # ${split_cmd}"
    eval "${split_cmd} 2>&1"
    [ "$?" -ne 0 ] && log_error "- The makedumpfile command returns ${retval}"

    log_info "- # ${merge_cmd}"
    eval "${merge_cmd} 2>&1"
    [ "$?" -ne 0 ] && log_error "- The makedumpfile command returns ${retval}"

    log_info "- Validating the merged dumpfile."
    verify_scrub
}

run_test makedumpfile_merge_split
