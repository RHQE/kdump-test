# **Kdump Test**

Kdump test is the test suite for [kexec-tools](http://pkgs.fedoraproject.org/cgit/rpms/kexec-tools.git) and [crash](https://github.com/crash-utility/crash).
It works on RHEL/CentOS/Fedora and possible their derivations.

## **What Does Kdump Test Do**

Kdump tests can be invided into 2 categories:
* Tests of dumping of vmcore (crash-* dump-* tests)
* Tests of analyzing vmcore (analyse-* tests)

**Dumping tests**

* It triggers system panic in various ways and expects a vmcore to be collected successfully at the end.
* It requires installing package *kexec-tools* during test.

**Vmcore analyzing tests**

* It analyzes and validates the vmcore dumped in a dumping test. So it has to be ran after a dumping test (except analyse-crash-live test).
* It uses [crash](https://github.com/crash-utility/crash) utility to analyze the vmcore. Following packages will be installed during vmcore analyzing tests:
    * crash
    * kernel-debuginfo

## **Execute Kdump Test**

It's very simple to execute a Kdump test. What you need to do is to change directory to each test case directory and execute `./runtest.sh` with root privilege, either manually or by [restraint](http://restraint.readthedocs.io).

**Notes,**

* Before running a dumping test, **make sure** there is enough disk space on dump target to save vmcore. Usually it is the size of physical memory.

* It may requires to update kernel boot cmdline (e.g. update crashkernel=<XX>M in Fedora) to start kdump service. And kdump panic handling will reboot system after collecting vmcore. So in general, system may reboot up to 2 times in each dumping test.

* Make sure the test framework you use to execute Kdump test is able to handle system reboot. Otherwise, you need to re-run `runtest.sh` after each reboot until the test is done.


## **General Test Workflow**

This is the typical workflow in a dumping test + vmcore analyzing test

1. Install *kexec-tools* and configure kernel boot cmdline if needed.

2. Modify kdump configuration file at /etc/kdump.conf.

3. Trigger system crash.

4. Install dependent packages for analyzing vmcore by crash.

5. Analyze and validate vmcore by crash utility.


## Contributing
### Bug report
For bugs of this test suite, feel free to report it in [issue page](https://github.com/RHQE/kdump-test/issues).

For bugs of kdump on Fedora, please file the report in [Bugzilla with product "Fedora"](https://bugzilla.redhat.com/enter_bug.cgi?product=Fedora).

For bugs of kdump on Red Hat Enterprise Linux, please file the report in [Red Hat Bugzilla](https://bugzilla.redhat.com/enter_bug.cgi?classification=Red%20Hat).

### Coding
If you want to contribute in code, feel free to send your pull requests.
