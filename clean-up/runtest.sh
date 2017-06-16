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

. ../lib/kdump.sh

clean_up()
{
    # expend filename patterns to null string if match no files.
    shopt -s nullglob

    if [ -f "${K_PATH}" ]; then
        local path=$(cat "${K_PATH}")
        if [ -d "${path}" ]; then
            log_info "- Removing vmcore files in ${path}."
            rm -rf "${path}"/*
        fi
    elif [ -d "${K_DEFAULT_PATH}" ]; then
        log_info "- Removing vmcore files in ${K_DEFAULT_PATH}"
        rm -rf "${K_DEFAULT_PATH}"/*
    fi

    if [ $? -eq 0 ]; then
        log_info "- Deleted vmcore files."
    else
        log_error "- Failed to delete vmcore files."
    fi

    log_info "- Restoring firewall status."

    log_info "- Restoring iptables/ip6tables rules."
    for iport in "${K_PREFIX_IPT}"_tcp_*    ; do
        iptables -D INPUT -p tcp --dport "$(echo $iport | awk -F '_' '{print $3}')"
        ip6tables -D INPUT -p tcp --dport "$(echo $iport | awk -F '_' '{print $3}')"
        service iptables save
        service ip6tables save
    done
    for iport in "${K_PREFIX_IPT}"_udp_* ; do
        iptables -D INPUT -p udp --dport "$(echo $iport | awk -F '_' '{print $3}')"
        ip6tables -D INPUT -p udp --dport "$(echo $iport | awk -F '_' '{print $3}')"
        service iptables save
        service ip6tables save
    done

    log_info "- Restoring firewall-cmd rules."
    for i in "${K_PREFIX_FWD}"_tcp_* ; do
        firewall-cmd --remove-port="$(echo $i | awk -F '_' '{print $3}')/tcp" --permanent
        firewall-cmd --remove-port="$(echo $i | awk -F '_' '{print $3}')/tcp"
    done
    for i in "${K_PREFIX_FWD}"_udp_* ; do
        firewall-cmd --remove-port="$(echo $i | awk -F '_' '{print $3}')/udp" --permanent
        firewall-cmd --remove-port="$(echo $i | awk -F '_' '{print $3}')/udp"
    done
    for i in "${K_PREFIX_FWD}"_service_* ; do
        firewall-cmd --remove-service="$(echo $i | awk -F '_' '{print $3}')" --permanent
        firewall-cmd --remove-service="$(echo $i | awk -F '_' '{print $3}')"
    done

    # Restore sshd status
    if [ -f "${K_PREFIX_SSH}" ]; then
        log_info "- Restoring sshd status."
        systemctl disable sshd || chkconfig sshd off
        if [ $? -eq 0 ]; then
            log_info "- Disabled sshd service."
        else
            log_error "- Failed to disable sshd service."
        fi
    fi

    log_info "- Restoring kdump conf files."
    cp -f "${K_BAK_DIR}"/kdump.conf ${K_CONFIG}
    cp -f "${K_BAK_DIR}"/kdump ${K_SYS_CONFIG}

    log_info "- Removing temp files."
    rm -rf "${K_TMP_DIR}"
    rm -rf "${K_INF_DIR}"

    log_info "- Done cleaning up"
}

run_test clean_up

