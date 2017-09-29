/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * Authors: Waiman Long <waiman.long@hp.com>
 *
 * This kernel module enables us to create hung tasks.
 *
 * The following debugfs variable will be created:
 * 1) <debugfs>/hungtest
 *
 * Reading this variable will cause the process to sleep uninterruptibly
 * for 60 seconds.
 */
#include <linux/module.h>	// included for all kernel modules
#include <linux/kernel.h>	// included for KERN_INFO
#include <linux/init.h>		// included for __init and __exit macros
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/atomic.h>
#include <linux/delay.h>
#include <linux/spinlock.h>
#include <linux/sched.h>
#include <linux/debugfs.h>
#include <linux/fs.h>

static ssize_t hung_read(struct file *file, char __user *user_buf,
			 size_t count, loff_t *ppos)
{
	msleep(60000);	/* 60s sleep */
	return 0;
}

static const struct file_operations fops_hungtest = {
	.read = hung_read,
};

static struct dentry *hungtest_dentry;

/*
 * Module init function
 */
static int __init hungtest_init(void)
{
	hungtest_dentry = debugfs_create_file("hungtest", 0400, NULL, NULL,
					      &fops_hungtest);
	if (!hungtest_dentry)
		return -ENOMEM;

	printk(KERN_INFO "hungtest module loaded!\n");

	// Non-zero return means that the module couldn't be loaded.
	return 0;
}

static void __exit hungtest_cleanup(void)
{
	printk(KERN_INFO "hungtest module unloaded.\n");
	if (hungtest_dentry)
		debugfs_remove(hungtest_dentry);
}

module_init(hungtest_init);
module_exit(hungtest_cleanup);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Waiman Long");
MODULE_DESCRIPTION("Hungtest module");
