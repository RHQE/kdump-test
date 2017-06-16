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

analyse_readelf()
{
    crash_prepare

    local error=0
    local warn=0

    local core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    log_info "- # readelf -a ${core}"
    readelf -a "${core}" 2>&1 | tee "${K_TMP_DIR}/readelf.log"
    error=${PIPESTATUS[0]}
    [[ ${error} -ne 0 ]] && log_info "- Readelf returns errors."
    report_file "${K_TMP_DIR}/readelf.log"

    # Catch warnings like,
    # readelf: Warning: corrupt note found at offset e40 into core
    grep -iw \
        -e 'warning' \
        -e 'warnings' \
        "${K_TMP_DIR}/readelf.log" \
        2>&1 | tee "${K_CRASH_REPORT}"
    warn=${PIPESTATUS[0]}
    [[ ${warn} -eq 0 ]] && {
        report_file "${K_CRASH_REPORT}"
        log_info "- Readelf returns warnings"
    }

    if [[  ${error} -ne 0 || ${warn} -eq 0  ]]; then
        log_error "- Fail: readelf returns errors/warnings"
    fi
}

run_test analyse_readelf
