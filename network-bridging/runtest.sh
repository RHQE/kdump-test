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

. ../lib/kdump_multi.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

bridging_prepare()
{
    install_rpm bridge-utils

    local eth="$(ip route | grep default | awk '{print $5}')"
    local eth_config="${NETWORK_CONFIG}/ifcfg-${eth}"
    local br=br0
    local br_config="${NETWORK_CONFIG}/ifcfg-${br}"

    log_info "- Adding ${br_config}"
    cat <<EOF > "${br_config}"
DEVICE=br0
TYPE=Bridge
NM_CONTROLLED=no
BOOTPROTO=dhcp
ONBOOT=yes
EOF
    report_file "${br_config}"

    log_info "- Updating ${eth_config}"
    sed -i "/^${BOOTPROTO=*} /d" "${eth_config}"
    sed -i "/^${BRIDGE=*} /d" "${eth_config}"
    sed -i "/^${NM_CONTROLLED=*} /d" "${eth_config}"
    echo "BOOTPROTO=none" >> "${eth_config}"
    echo "BRIDGE=br0" >> "${eth_config}"
    echo "NM_CONTROLLED=no" >> "${eth_config}"
    report_file "${eth_config}"

    sync;sync;sync

    log_info "- Restarting network"
    systemctl restart network 2>&1 || service network restart  2>&1
    [ $? -eq 0 ] || log_error "- Failed to restart network!"

    log_info "- Checking bridge status"
    brctl show | grep "$br" | grep "$eth" || {
        log_info $(brctl show)
        log_error "- Failed to set up a bridge."
    }

}


# This is a mutli-host tests has to be ran on both Server/Client.
# Test to dump to nfs server via bridged network
dump_bridging()
{
    if [ -z "${SERVERS}" -o -z "${CLIENTS}" ]; then
        log_error "No Server or Client hostname"
    fi

    # port used for client/server sync
    local done_sync_port=35413
    open_firewall_port tcp "${done_sync_port}"

    if [[ ! -f "${C_REBOOT}" ]]; then
        kdump_prepare
        multihost_prepare
        config_nfs

        if [[ $(get_role) == "client" ]]; then
            bridging_prepare
            kdump_restart
            report_system_info

            trigger_sysrq_crash

            log_info "- Notifying server that test is done at client."
            send_notify_signal "${SERVERS}" ${done_sync_port}
            log_error "- Failed to trigger crash."

        elif [[ $(get_role) == "server" ]]; then
            log_info "- Waiting for signal that test is done at client."
            wait_for_signal ${done_sync_port}
        fi
    else
        rm -f "${C_REBOOT}"
        copy_nfs
        local retval=$?

        log_info "- Notifying server that test is done at client."
        send_notify_signal "${SERVERS}" ${done_sync_port}

        [ ${retval} -eq 0 ] || log_error "- Failed to copy vmcore"

        validate_vmcore_exists
    fi
}

run_test dump_bridging

