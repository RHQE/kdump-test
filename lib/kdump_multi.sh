#!/usr/bin/env bash

# Library for Kdump Multi-Host Test

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


# @usage: get_role
# @description: get role for current host
# @return: server/client
get_role()
{
    if [[ "${SERVERS}" == "${HOSTNAME}" ]]; then
        echo "server"; return
    elif [[ "${CLIENTS}" == "${HOSTNAME}" ]]; then
        echo "client"; return
    fi

    if ipcalc -c "${SERVERS}" && is_host_ip "${SERVERS}"; then
        echo "server"; return
    elif ipcalc -c "${CLIENTS}" && is_host_ip "${CLIENTS}"; then
        echo "client"; return
    fi

    log_error "- Unable to determine host role."
}


# @usage: is_host_ip <ip>
# @description: check if host ip matches the ip passed in
# @param1: ip
# @return: 0 - matches / 1 - not match
is_host_ip()
{
    for ip in $(ip -o addr | awk '!/^[0-9]*: ?lo|link\/ether/ {gsub("/", " "); print $4}'); do
        [[ $ip == "$1" ]] && return 0
    done
    return 1
}


# @usage: open_firewall_service <fw_service>
# @description:
#       open a service on firewall using firewall-cmd
#       skip the step if no firewalld is running.
# @param1: fw_service
open_firewall_service()
{
    [ $# -lt 1 ] && log_error "- Syntax error: Expecting a service name."

    local fw_service=$1

    log_info "- Opening service ${fw_service} on firewall"
    systemctl status firewalld
    if [ $? == 0 ]; then
            firewall-cmd --list-service | grep "${fw_service}"
            if [ $? -ne 0 ]; then
                touch "${K_PREFIX_FWD}_service_${fw_service}"
                firewall-cmd --add-service="${fw_service}"
                firewall-cmd --add-service="${fw_service}" --permanent
            fi
    else
        log_info "- Skipped. The iptables service is not running."
    fi
}


# @usage: open_firewall_service <fw_protocol> <fw_port>
# @description:
#       open a port on firewall using firewall-cmd or iptables
#       skip the step if o firewalld or iptables is running.
# @param1: fw_protocol
# @param2: fw_port
open_firewall_port()
{
    [ $# -lt 2 ] && log_error "- Syntax error: Expecting a protocol and port"

    local fw_protocol=$1
    local fw_port=$2

    log_info "- Opening port ${fw_port}/${fw_protocol} on firewall"
    local mode=off
    service iptables status && mode=iptables
    systemctl status firewalld && mode=firewalld

    case $mode in
        firewalld)
            firewall-cmd --list-ports | grep "${fw_port}/${fw_protocol}"
            if [ $? -ne 0 ]; then
                touch "${K_PREFIX_FWD}_${fw_protocol}_${fw_port}"
                firewall-cmd --add-port="${fw_port}/${fw_protocol}"
                firewall-cmd --add-port="${fw_port}/${fw_protocol}" --permanent
            fi
            ;;
        iptables)
            iptables-save | grep -i "${fw_protocol}" | grep "${fw_port}"
            if [ $? -ne 0 ]; then
                touch "${K_PREFIX_IPT}_${fw_protocol}_${fw_port}"
                iptables -I INPUT -p "${fw_protocol}" --dport "${fw_port}" -j ACCEPT
                service iptables save
                ip6tables -I INPUT -p "${fw_protocol}" --dport "${fw_port}" -j ACCEPT
                service ip6tables save
            fi
            ;;
        off)
            log_info "- Skipped. The firewalld or iptables service is not running."
            ;;
    esac
}


# @usage: wait_for_signal <port>
# @description:
#       wait for signal at given port.
#       used for client/server sync
# @param1: port
wait_for_signal()
{
    nc -l "$1"
    if [ $? == 0 ]; then
        log_info "- Received signal at port $1"
    else
        log_error "- Failed to listen for signal at port $1"
    fi
}


# @usage: send_notify_signal <hostname|ip><port>
# @description:
#       send signal to server <hostname|ip> at <port>
#       used for client/server sync
# @param1: hostname or ip
# @param1: port
send_notify_signal()
{
    local server=$1
    local port=$2

    local count=${K_RETRY_COUNT}
    local retval=1

    # try dump message to /dev/tcp/${server}/${port}
    while [ "$count" -gt 0 ]; do
        echo "Success" > "/dev/tcp/${server}/${port}"
        if [ $? -eq 0 ]; then
            retval=0
            break
        else
            sleep 10s
        fi
        (( count = count - 1 ))
    done

    if [ "${retval}" -eq 1 ]; then
        log_error "- Failed to notify server, got timeout."
    else
        log_info "- Sent notify signal to ${server} at ${port} successfully"
    fi
}


# @usage: config_ssh <hostname|ip><port>
# @description:
#       config ssh for kdump on server/client
#       applicable for both ipv4 and ipv6
#       including,
#           set up ssh connection without passwd between s/c
#           config kdump.conf on client for ssh dump
# @param1: ip_version   # v4 or v6. default to 'v4'
config_ssh()
{
    install_rpm openssh-server openssh-clients
    local server=${SERVERS}
    local client=${CLIENTS}

    # Path where server will save its ipv6 addr to and where client will fetch
    local path_ipv6_addr="/root/server-ipv6-address"

    # port used for client/server sync
    local sync_port=35412
    open_firewall_port tcp "${sync_port}"

    local ip_version=${1:-"v4"}
    [[  "${ip_version}" =~ ^(v4|v6)$ ]] || {
        log_error "- ${ip_version} is not supported. Onlyl ipv4 or ipv6 is supported."
    }

    if [[ $(get_role) == "client" ]]; then  # copy keys
        ## Note:
        ## if client exits with error during config. It must notify server.
        ## otherwise server will keep waiting for the client to proceed.

        prepare_ssh_connection client

        # config kdump.config for ssh dump
        append_config "sshkey ${K_LOCK_SSH_ID_RSA}"

        if [[ ${ip_version} == "v6" ]]; then
            # get server ipv6 address
            ssh -i "${K_LOCK_SSH_ID_RSA}" "${server}" "cat ${path_ipv6_addr}" > ${path_ipv6_addr}.out
            [ $? -eq 0 ] || log_error "- Failed to get server ipv6 address."
            server_ipv6=$(grep -P '^[0-9]+' "${path_ipv6_addr}".out | head -1)
            append_config "ssh root@${server_ipv6}"
        else
            append_config "ssh root@${server}"
        fi

        config_kdump_filter  # add -F for ssh dump
        # config 'path' to client hostname
        # so client can fetch vmcore only belong to itself.
        config_kdump_any "path ${KPATH}/${client}"

        if [[ "${K_DIST_VER}" == "6" ]]; then
            # Only required for RHEL6.
            # It needs to wait for while for network readyness
            config_kdump_any "link_delay 60"
        fi

        log_info "- Updated kdump.config for ssh kdump."
        log_info "- Notifying server that kdump config is done at client."
        send_notify_signal "${server}" "${sync_port}"

    elif [[ $(get_role) == "server" ]]; then
        prepare_ssh_connection server "${ip_version}"

        log_info "- Waiting for signal that kdump config is done at client"
        wait_for_signal ${sync_port}

    else
        log_error "- Can not determine the role of host."
    fi
}


# @usage: config_nfs <ip_version>
# @description:
#       config nfs on server/client
# @param1: ip_version   # v6 or empty
config_nfs()
{
    install_rpm nfs-utils

    if [ "${K_DIST_VER}" -lt 7 ]; then
        open_firewall_port tcp 2049 # nfs
        open_firewall_port udp 2049
        open_firewall_port tcp 111 # rpcbind
        open_firewall_port udp 111
    else
        open_firewall_service mountd
        open_firewall_service rpc-bind
        open_firewall_service nfs
    fi

    local ip_version=$1
    local sync_port=35412 # port used for client/server sync
    local retval=0

    local client=${CLIENTS}
    local server=${SERVERS}
    local path_ipv6_addr="/root/server-ipv6-address"

    open_firewall_port tcp "${sync_port}"

    if [[ $(get_role) == "client" ]]; then  # copy keys
        ## Note:
        ## If client exits with error during config. server must be notified.
        ## Otherwise server will wait foever for the client to proceed.

        # Check nfs opt passed through $TESTARGS
        if   [ "$K_DIST_VER" -le "5" ]; then [[ "${TESTARGS:=net}" == net ]]
        elif [ "$K_DIST_VER" -eq "6" ]; then [[ "${TESTARGS:=nfs}" =~ ^(net|nfs|nfs4)$ ]]
        else
            [[ "${TESTARGS:=nfs}" == nfs ]]
        fi
        [ $? == 0 ] || log_error "The nfs opt passed in TESTARGS is invalid."

        local server_addr=${SERVERS}
        [ "${ip_version}" == "v6" ] && {
            prepare_ssh_connection client
            # Fetch server ipv6 address
            ssh -i "${K_LOCK_SSH_ID_RSA}" "${server}" "cat ${path_ipv6_addr}" > ${path_ipv6_addr}.out
            [ $? == 0 ] || {
                log_info "- Notifying server that kdump config is done at client."
                send_notify_signal "${server}" "${sync_port}"
                log_error "- Failed to get server ipv6 address."
            }
            server_addr=[$(grep -P '^[0-9]+' "${path_ipv6_addr}".out | head -1)]
        }

        append_config "${TESTARGS} ${server_addr}:${K_EXPORT}"
        echo "${K_EXPORT}" > "${K_NFS}"

        # Config 'path' to client hostname
        # So client can fetch vmcore belong to itself.
        append_config "path /${client}"
        echo "/${client}" > "${K_PATH}"

        # required only for RHEL6 or earlier
        [ "${K_DIST_VER}" == "6" ] && append_config "link_delay 60"

        log_info "- Waiting for signal that nfs setup is done at server"
        wait_for_signal ${sync_port}

        # mount nfs dir and restart kdump service
        mkdir -p "${K_EXPORT}"
        mount "${server_addr}:${K_EXPORT}"  "${K_EXPORT}"
        kdump_restart

        log_info "- Updated Kdump config for nfs dump."
        log_info "- Notifying server that kdump config is done at client."
        send_notify_signal "${server}" "${sync_port}"

    elif [[ $(get_role) == "server" ]]; then

        # prepare ipv6 address and allow client to obtain it via ssh
        [ "${ip_version}" == "v6" ] && prepare_ssh_connection server "${ip_version}"

        log_info "- Setting up NFS server"
        mkdir -p "${K_EXPORT}"
        echo "${K_EXPORT} *(rw,no_root_squash,sync,insecure)" > "/etc/exports"

        mkdir -p "${K_EXPORT}/${client}"  # Required since kexec-2.0.7

        exportfs -ra && systemctl restart nfs || service nfs restart
        retval=$?
        log_info "- Notifying client that nfs setup is done at server"
        send_notify_signal "${client}" "${sync_port}"
        if [ ${retval} -eq 0 ]; then
            log_info "- NFS server is started"
        else
            log_error "- Failed to start NFS server."
        fi

        log_info "- Waiting signal that kdump config is done at client"
        wait_for_signal ${sync_port}
    else
        log_error "- Can not determine the role of host."
    fi
}

# @usage: copy_nfs
# @description:
#       Copy vmcore from nfs server to client at exact same place
#       as it's on server
copy_nfs()
{
    local client=${CLIENTS}
    local server=${SERVERS}

    local vmcore_path=${K_DEFAULT_PATH}
    [ -f "${K_PATH}" ] && vmcore_path=$(cat "${K_PATH}")
    local export_path=${K_EXPORT}
    [ -f "${K_NFS}" ] && export_path=$(cat "${K_NFS}")

    log_info "- Mounting ${SERVERS}:${export_path} to /mnt/tmp"
    mkdir -p "/mnt/tmp"
    mount "${SERVERS}:${export_path}" "/mnt/tmp" || return 1

    log_info "- Copying vmcore to nfs client"
    log_info "- cp -r /mnt/tmp${vmcore_path}/* ${export_path}${vmcore_path}"

    mkdir -p "${export_path}${vmcore_path}"
    cp -r "/mnt/tmp${vmcore_path}/"* "${export_path}${vmcore_path}" || return 1

    umount "/mnt/tmp"
}

# @usage: prepare_ssh_connection <role> <ip_version>
# @description:
#       prepare and test ssh connection at client/server
#       server will output its ipv6 address to a file if ip_version=v6
# @param1: role   # client or server
# @param2: ip_version   # empty or v6.
prepare_ssh_connection()
{
    local role=$1
    local ip_version=${2:-}


    if [ "$role" = "client" ]; then
        mkdir -p "${K_LOCK_AREA}/.ssh"
        cp ../lib/id_rsa "${K_LOCK_SSH_ID_RSA}"
        cp ../lib/id_rsa.pub "${K_LOCK_SSH_ID_RSA}.pub"
        chmod 0600 "${K_LOCK_SSH_ID_RSA}"
        chmod 0600 "${K_LOCK_SSH_ID_RSA}.pub"

        # turn off StrictHostKeyChecking
        [[ -f ${K_SSH_CONFIG} ]] && sed -i "/^StrictHostKeyChecking/d" "${K_SSH_CONFIG}"
        echo "StrictHostKeyChecking no" >> "${K_SSH_CONFIG}"

        log_info "- Waiting for signal from server that sshd service is ready at server."
        wait_for_signal ${sync_port}

        # Test ssh connection
        log_info "- Testing ssh connection."
        ssh -o StrictHostKeyChecking=no -i "${K_LOCK_SSH_ID_RSA}" "${server}" 'touch ${K_LOCK_AREA}/ssh_test'

        [ $? == 0 ] || {
            log_info "- Notifying server that ssh connection failed at client"
            send_notify_signal "${server}" "${sync_port}" ## MUST DO
            log_error "- SSH connection test failed."
        }

        log_info "- SSH connection test passed."

    elif [ "$role" = "server" ]; then
        # prepare for ssh connection
        systemctl status sshd || service sshd status
        [ $? -ne 0 ] && {
            systemctl start sshd || service sshd start
            touch "${K_PREFIX_SSH}"
            systemctl enable sshd || chkconfig sshd on
            open_firewall_port tcp 22
        }

        mkdir -p "/root/.ssh"
        touch "/root/.ssh/authorized_keys"
        cat "../lib/id_rsa.pub" >> "/root/.ssh/authorized_keys"
        restorecon "/root/.ssh/authorized_keys"


        # save ipv6 address to ${path_ipv6_addr}
        local retval=0
        [ "$ip_version" == "v6" ] && {
            ifconfig | grep inet6\ | grep global | awk -F' ' '{print $2}' > ${path_ipv6_addr}
            retval=$?
        }

        log_info "- Notifying client that ssh preparation is done at server"
        send_notify_signal "${client}" "${sync_port}"

        [ "${retval}" == 0 ] || log_error "- Failed to get ipv6 address from Server"

    else
        log_error "- Unknown role: ${role}"
    fi
}

