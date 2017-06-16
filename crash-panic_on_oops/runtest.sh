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
. ../lib/kdump_report.sh
. ../lib/crash.sh

crash_panic_on_oops()
{
    if [[ ! -f "${C_REBOOT}" ]]; then
        kdump_prepare
        report_system_info

        make_install_module "crasher" .
        trigger_crasher 2 # a=0;a[1]='A';
    else
        rm -f "${C_REBOOT}"
        validate_vmcore_exists
    fi
}

run_test crash_panic_on_oops

