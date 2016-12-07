#!/usr/bin/env bash

((LIB_CRASH_SH)) && return || LIB_CRASH_SH=1
. ../lib/log.sh

check_vmcore_file()
{
    log_info "- Find vmcore file"
    find /var/crash/ -newer /etc/kdump.conf -name "vmcore*" -type f | grep vmcore
    [ $? -ne 0 ] && log_error "- Failed to find vmcore!"
    log_info "- Found vmcore file successfully!"
    log_info $(ls "${K_DEFAULT_PATH}")
}

# To Do
analyse_by_crash()
{
    echo "analyse vmcore by crash commend"
}

analyse_live()
{
    echo "analyse in live system"
}

analyse_by_basic()
{
    echo "analyse vmcore use basic option"
}

analyse_by_gdb()
{
    echo "analyse vmcore by gdb"
}

analyse_by_readelf()
{
    echo "analyse vmcore by readelf"
}

analyse_by_dmesg()
{
    echo "analyse vmcore-dmesg.txt"
}

analyse_by_trace_cmd()
{
    echo "analyse vmcore by trace_cmd"
}

analyse_by_gcore_cmd()
{
    echo "analyse vmcore by gcore_cmd"
}
