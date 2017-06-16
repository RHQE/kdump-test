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

. ../lib/crash.sh

analyse_gdb()
{
    crash_prepare

    # prepare gdb.cmd
    cat <<EOF > "${K_TMP_DIR}/gdb.cmd"
list
bt
bt full
frame
up
down
disassemble
info threads
info registers
info all-registers
quit
EOF

    local vmx="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    [ ! -f "${vmx}" ] && log_error "- Unable to find vmlinux."

    local core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    log_info "- # gdb < ${K_TMP_DIR}/gdb.cmd ${vmx} ${core}"
    gdb < "${K_TMP_DIR}"/gdb.cmd "${vmx}" "${core}" > "${K_TMP_DIR}/gdb.log" 2>&1

    report_file "${K_TMP_DIR}/gdb.cmd"
    report_file "${K_TMP_DIR}/gdb.log"

    check_gdb_output "${K_TMP_DIR}/gdb.log"
}

run_test analyse_gdb
