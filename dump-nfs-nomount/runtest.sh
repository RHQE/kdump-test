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

. ../lib/kdump.sh
. ../lib/kdump_multi.sh
. ../lib/kdump_report.sh
. ../lib/crash.sh

# This is a muli-host tests has to be ran on both Server/Client.
nfs_sysrq_nomount()
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
            # Since kexec-tools-2.0.7-50.el7, it allows vmcore to be dumped to
            # a nfs target without specifying and mounting the nfs target
            # before creating the kdump initrd img.
            # Instead, users can pass the mount options via dracut_args which
            # will be used in 2nd kernel.
            # When building the initrd img, it won't validate if target
            # is mounted.
            # Example of kdump.conf
            #  path /var/crash
            #  core_collector makedumpfile -l --message-level 1 -d 31
            #  dracut_args --mount "192.168.1.1:/share /test nfs defaults"
            umount ${K_EXPORT}
            remove_config nfs
            local args="dracut_args --mount \"${SERVERS}:${K_EXPORT} ${K_EXPORT} nfs defaults\""
            config_kdump_any "${args}"

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

run_test nfs_sysrq_nomount
