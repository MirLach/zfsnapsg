# Note

**This is experimental Work In Progress version of zfsnap**

The original `zfsnap` is good for servers running 24/7, but if you use it on a desktop, go on holiday, come home, turn on your computer and want to restore some file changes you made last week, for example, you may easily find that you no longer have a snapshot from that time. This is because snapshots expire after a certain amount of time.

Instead of time, I prefer to specify how many snapshots I want to keep, and delete the oldest ones above that number.

For periodic creation of snapshots (from cron) there is a new option `-g `_<group>_ to specify to which snapshot group this snapshot belongs to. Group can be `M`, `H`, `d`, `w`, `m`, `y` for Minutely, Hourly .. to monthly, yearly.

Example of snapshot names with additional prefix `-p zfsnapsg_`
```
tank0/usr/home/user1@zfsnapsg_2023-04-28_21.40.00--M
tank0/usr/home/user1@zfsnapsg_2023-04-28_21.02.00--H
tank0/usr/home/user1@zfsnapsg_2023-04-27_15.07.00--d
tank0/usr/home/user1@zfsnapsg_2023-04-24_16.29.00--w
```

Then you need one periodic command to destroy the oldest snapshots where you must define how many snapshots to keep for each snapshot group created.
The following command will keep 120 minutely snapshots, 36 hourly, 10 daily, 6 weekly and 3 monthly snapshots.
```
zfsnap destroysg -p zfsnapsg_ -g M120 -g H36 -g d10 -g w6 -g m3 -r -s -S tank0
```

Even if you leave your computer turn off for a year and then turn it on again, this `zfsnap` will still keep that number of snapshots for you, so you can examine the history of your work from before the computer was turned off.

Example of crontab entries
```
## create periodic snapshots
*/5	*	*	*	*	/usr/local/sbin/zfsnap snapshot -p zfsnapsg_ -g M -r -z tank0
4	*	*	*	*	/usr/local/sbin/zfsnap snapshot -p zfsnapsg_ -g H -r -z tank0
7	12	*	*	*	/usr/local/sbin/zfsnap snapshot -p zfsnapsg_ -g d -r -z tank0
27	13	*	*	1	/usr/local/sbin/zfsnap snapshot -p zfsnapsg_ -g w -r -z tank0
47	14	1	*	*	/usr/local/sbin/zfsnap snapshot -p zfsnapsg_ -g m -r -z tank0

## delete old snapshots
2	*	*	*	*	/usr/local/sbin/zfsnap destroysg -p zfsnapsg_ -g M120 -g H36 -g d10 -g w6 -g m3 -r -s -S tank0
```

# About zfsnap

`zfsnap` makes rolling ZFS snapshots easy and — with cron — automatic.

The main advantages of `zfsnap` are its portability, simplicity, and performance.
It is written purely in `/bin/sh` and does not require any additional software —
other than a few core *nix utilies.

`zfsnap` stores all the information it needs about a snapshot directly in its name;
no database or special ZFS properties are needed. The information is stored in
a way that is human readable, making it much easier for a sysadmin to manage
and audit backup schedules.

Snapshot names are in the format of pool/fs@[prefix]Timestamp--SG (e.g.
pool/fs@zfsnapsg_2023-04-28_21.02.00--H). The prefix is optional but can be quite
useful for filtering, Timestamp is the date and time when the snapshot was
created, and SG is the Snapshot Group to later filter snapshots for deletion.

# Need help?

Forked from original `zfsnap` https://github.com/zfsnap/zfsnap/

For information about `zfsnap` 2.0, please refer to the manpage or the [zfsnap
website](http://www.zfsnap.org).

# Will zfsnap run on my system?

`zfsnap` is written with portability in mind, and our aim is for it to run on
any and every OS that supports ZFS.

Currently, `zfsnap` supports FreeBSD, Solaris (and Solaris-like OSs), Linux,
GNU/kFreeBSD, and OS X. It should run on your system as long as:
- ZFS is installed
- your Bourne shell is POSIX compliant and supports "local" variables (all modern systems should)
- your system provides at least the most basic of POSIX utilities (uname, head, etc)
- your system uses the Gregorian calendar

See the PORTABILITY file for additional information on specific shells and OSs.
