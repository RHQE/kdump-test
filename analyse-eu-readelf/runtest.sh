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

analyse_eu_readelf()
{
    crash_prepare

    local core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    log_info "- # eu-readelf -a ${core}"
    eu-readelf -a "${core}" 2>&1 | tee "${K_TMP_DIR}/eu-readelf.log"
    error_found=${PIPESTATUS[0]}

    report_file "${K_TMP_DIR}/eu-readelf.log"
    if [ "${error_found}" -ne 0 ]; then
        log_error "- Fail: eu-readelf returns errors"
    fi

    ready_to_exit
}

log_info "- Start"
analyse_eu_readelf
