#!/usr/bin/env bash

# Library for Kdump Test Logging

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

((LIB_LOG_SH)) && return || LIB_LOG_SH=1

readonly K_LOG_FILE="./result.log"
readonly K_ERROR_FILE="./K_ERROR"
readonly K_WARN_FILE="./K_WARN"
readonly K_TEST_SUMMARY="../test_summary.log"

K_TEST_NAME=$(basename "$(pwd)")


# @usage: is_beaker_env
# @description: check it is a beaker environment
# #return: 0 - yes, 1 - no
is_beaker_env()
{
    if [ -f /usr/bin/rhts-environment.sh ]; then
        . /usr/bin/rhts-environment.sh
        return 0
    else
        log_info "- This is not executed in beaker."
        return 1
    fi
}


# @usage: log <level> <mesg>
# @description: Print Log info into ${K_LOG_FILE}
# @param1: level # INFO, WARN, ERROR, FATAL
# @param2: mesg
log()
{
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $level $*" >> "${K_LOG_FILE}"
    if [ "$level" == "ERROR" -o "$level" == "FATAL" ]; then
        echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $level $*" >&2
    else
        echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $level $*"
    fi
}


# @usage: report_file <filename>
# @description:
#       upload file to beaker server if beaker env
#       otherwise print it to console
# @param1: filename
report_file()
{
    local filename="$1"
    if [ -f "${filename}" ]; then
        if is_beaker_env; then
            rhts-submit-log -l "$filename"
        else
            cat "${filename}"
        fi
    else
        # if file doesn't exist.
        log_warn "- File ${filename} doesn't exist!"
    fi
}


# @usage: log_info <mesg>
# @description: log INFO message
# @param1: mesg
log_info()
{
    log "INFO" "$@"
}

# @usage: log_warn <mesg>
# @description: log WARN message
# @param1: mesg
log_warn()
{
    log "WARN" "$@"
    printf n >> "${K_WARN_FILE}"
}

# @usage: log_error <mesg>
# @description: log ERROR message and exit current task
# @param1: mesg
log_error()
{
    log "ERROR" "$@"
    printf n >> "${K_ERROR_FILE}"
    ready_to_exit
}

# @usage: log_fatal<mesg>
# @description: log ERROR message
#               and abort recipeset (only if beaker env)
# @param1: mesg
log_fatal()
{
    log "FATAL" "$@"

    local result="FAIL"
    local code=1

    echo -e "${K_TEST_NAME}\t\t\t${result}" >> "${K_TEST_SUMMARY}"

    if is_beaker_env; then
        report_result "${TEST}" "${result}" "${code}"
        rhts-abort -t recipeset
        exit ${code}
    else
        log_info "- [${result}] Please check test logs!"
        exit $code
    fi
}


# @usage: ready_to_exit <exit_code>
# @description:
#       report test log/status and exit
#       # of warns/errors reported during tests
#       will be fetched from K_ERROR_FILE and K_WARN_FILE
ready_to_exit()
{
    report_file "${K_LOG_FILE}"

    local result
    local code

    if [ -f "${K_ERROR_FILE}" ]; then
        result="FAIL"
        code=$(wc -c < "${K_ERROR_FILE}")
    elif [ -f "${K_WARN_FILE}" ]; then
        result="WARN"
        code=$(wc -c < "${K_WARN_FILE}")
    else
        result="PASS"
        code=0
    fi

    rm -f "$K_ERROR_FILE" "$K_WARN_FILE"

    # log [test name and result] to K_TEST_SUMMARY
    echo -e "${K_TEST_NAME}\t\t\t${result}" >> "${K_TEST_SUMMARY}"

    if is_beaker_env; then
        report_result "${K_TEST_NAME}" "${result}" "$code"
        exit
    else
        if [ "${result}" != "PASS" ]; then
            log_info "- [${result}] Please check test logs!"
            exit $code
        else
            log_info "- [${result}] Tests finished successfully!"
            exit 0
        fi
    fi
}


# @usage: reboot_system
# @description: reboot system
reboot_system()
{
    sync

    if is_beaker_env; then
        rhts-reboot
    else
        reboot
    fi
}
