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

. ../lib/crash.sh

analyse_crash()
{
    crash_prepare

    # Prepare crash-simple.cmd/crash.cmd
    # Check only return code of this session.
    cat <<EOF > "${K_TMP_DIR}/crash-simple.cmd"
bt -a
ps
log
exit
EOF

    # Check command output of this session.
    # The "kmem -S" command is tailored to avoid/ignore the exhaustive check
    # of the unusual slab objects in which each 64k slab contains thousands of
    # individual objects.
    cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
help -v
help -m
help -n
swap
mod
mod -S
runq
foreach bt
foreach files
mount
mount -f
vm
net
mach -m
search -u deadbeef
set
set -p
set -v
bt
bt -t
bt -r
bt -T
bt -l
bt -a
bt -f
bt -e
bt -E
bt -F
bt 0
ps
ps -k
ps -u
ps -s
dev
kmem -i
kmem -s
kmem -S -I kmalloc-8,kmalloc-16
task
p jiffies
sym jiffies
rd -d jiffies
set -c 0
EOF

    # In order for the "irq -u" option to work, the architecture
    # must have either the "no_irq_chip" or the "nr_irq_type" symbols to exist.
    # But s390x has none of them:
    if [ "$(uname -m)" != "s390x" ]; then
        cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
irq
irq -b
irq -u
exit
EOF
    else
        cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
exit
EOF
    fi

    # RHEL releases take different version of crash utility respectively, so
    # here add cmds specific to versions.

    if [[ "$K_DIST_VER" =~ ^(6|7)$ ]]; then
        cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
list -o task_struct.tasks -h init_task
exit
EOF
    fi

    local vmx="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    [ ! -f "${vmx}" ] && log_error "- Unable to find vmlinux."

    local core=$(get_vmcore_path)
    [ -z "${core}" ] && log_error "- Unable to find vmcore."

    crash_cmd "" "${vmx}" "${core}" "${K_TMP_DIR}/crash-simple.cmd"
    crash_cmd "" "${vmx}" "${core}" "${K_TMP_DIR}/crash.cmd" check_crash_output
}

run_test analyse_crash
