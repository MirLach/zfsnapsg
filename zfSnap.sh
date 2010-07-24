#!/bin/sh
# beerware license, written by Aldis Berjoza (aldis@bsdroot.lv)

[ $# = 0 ] && cat << EOF
Syntax:
${0##./} [-a seconds] [-p prefix] [-P postifx] [-r] z/fs1 [[[-r] z/fs2] ...]

Options:
-a seconds   = set how long snapshot should be kept (in seconds)
-p prefix    = prefix snapshots with prefix
-P postfix   = postifx snapshots with postfix
-r           = recursive snapshots
EOF

age=2592000	# default max snapshot age in seconds (30 days)
[ "$1" = '-a' ] && { age=$2; shift 2; }
[ "$1" = '-p' ] && { prefix=$2; shift 2; } 
[ "$1" = '-P' ] && { postfix=$2; shift 2; }

tfrmt="%Y-%m-%d_%T"

ntime=`date +$tfrmt`
while [ $1 ]; do
	[ $1 = '-r' ] && { zopt=$1; shift; } || zopt=''
	zfs snapshot $zopt $1@${prefix}${ntime}${postfix}
	shift
done

dtime=`date +%s-$age | bc -l`
for i in `zfs list -H -t snapshot | awk '{print $1}' | grep -E -e "^.*@${prefix}20[0-9]{2}-[01][0-9]-[0-3][0-9]_[0-2][0-9]:[0-6][0-9]:[0-6][0-9]${postfix}$"`; do
	[ $dtime -gt $(date -j -f $tfrmt $(echo $i | sed -e "s/^.*@${prefix}//" -e "s/${postfix}$//") +%s) ] && zfs destroy $i
done

exit 0
