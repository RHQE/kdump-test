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

analyse_live()
{
    crash_prepare

    # Prepare crash-simple.cmd/crash.cmd
    # Check only return code of this session.
    # From the maintainer, Dave Anderson:
    #
    #  foreach bt
    #  foreach files
    #
    # Any "foreach" command option should *expect* to fail given that the
    # underlying set of tasks are changing while the command is being run.
    #
    #  runq
    #
    # The runq will constantly be changing, so results are indeterminate.
    #
    #  kmem -i
    #  kmem -s
    #  kmem -S - The "kmem -S" test is invalid when runing on a live system.
    #
    # The VM, and the slab subsystem specifically, is one of the most active
    # areas in the kernel, and so the commands above are very likely to run
    # into stale/changing pointers and such, and may fail as a result.
    cat <<EOF > "${K_TMP_DIR}/crash-simple.cmd"
sym -l
log -m
runq
foreach bt
foreach files
kmem -i
kmem -s
exit
EOF


    # Check command output of this session.
    cat <<EOF >> "${K_TMP_DIR}/crash.cmd"
files
mod
mod -S
mod -s twofish
runq
alias
foreach bt
foreach bash task
foreach files
mount
mount -f
search -u deadbeef
search -s _etext -m ffff0000 abcd
search -p babe0000 -m ffff
vm
vm -p 1
ascii
fuser /
net
set
set -p
set -v
bt
bt -t
bt -r
bt -T
bt -l 1
bt -f 1
bt -e
bt -E
bt 0
gdb help
p init_mm
sig -l
btop 512a000
help help
ps
ps -k
ps -u
ps -s
struct vm_area_struct
whatis linux_binfmt
dev
dev -i
pte d8e067
swap
dis sys_signal
kmem -i
kmem -s
sym -q pipe
ptob 512a
eval (1 << 32)
ptov 56e000
sys config
sys -c
sys -c select
rd jiffies
task
extend
mach
mach -m
timer
EOF

    # In order for the "irq -u" option to work, the architecture
    # must have either the "no_irq_chip" or the "nr_irq_type" symbols to exist.
    # But s390x has none of them.
    if [ "$(uname -m)" != "s390x" ]; then
        cat <<EOF >>"${K_TMP_DIR}/crash.cmd"
irq
exit
EOF
    fi

# RHEL5/6/7 takes different version of crash utility respectively.
# So here adding cmds specific to each version.

    if [[ $K_DIST_VER -eq 5 ]]; then
        cat <<EOF >>"${K_TMP_DIR}/crash.cmd"
mount -i
dev -p
list -s module.version -H modules
exit
EOF
    fi

    if [[ $K_DIST_VER -eq 6 ]]; then
        cat <<EOF >>"${K_TMP_DIR}/crash.cmd"
list -o task_struct.tasks -h init_task
exit
EOF
    fi

    if [[ $K_DIST_VER -eq 7 ]]; then
        cat <<EOF >>"${K_TMP_DIR}/crash.cmd"
list -o task_struct.tasks -h init_task
exit
EOF
    fi

    export SKIP_ERROR_PAT="kmem:.*error.*encountered"
    crash_cmd "" "" "" "${K_TMP_DIR}/crash-simple.cmd"
    crash_cmd "" "" "" "${K_TMP_DIR}/crash.cmd" check_crash_output
}

run_test analyse_live
