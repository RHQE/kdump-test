/*
 * Copyright (c) 2017 Red Hat, Inc. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Qiao Zhao <qzhao@redhat.com>
 */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PAGE_SIZE (1<<12)  // 4KB for one page

int main() {
    int i;
    int tb = 128;

    for (i = 0; i < ((unsigned long)tb<<40)/PAGE_SIZE ; ++i) {
        void *mem = malloc(PAGE_SIZE);
        if (!mem)
            break;
        memset(mem, 0, 1);
    }
    printf("Allocated %lu MB\n", ((unsigned long)i*PAGE_SIZE)>>20);
    getchar();
    return 0;
}