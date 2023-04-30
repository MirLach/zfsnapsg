#!/bin/sh

# This file is licensed under the BSD-3-Clause license.
# See the AUTHORS and LICENSE files for more information.

DELETE_ALL_SNAPSHOTS='false'        # Should all snapshots be deleted, regardless of TTL
RM_SNAPSHOTS=''                     # List of specific snapshots to delete
FORCE_DELETE_BY_AGE='false'         # Ignore TTL expiration and delete if older than "AGE" (in TTL format).
FORCE_AGE_TTL=''                    # Used to store "age" TTL if FORCE_DELETE_BY_AGE is set.
RECURSIVE='false'
PREFIXES=''                         # List of prefixes

# FUNCTIONS
Help() {
    cat << EOF
${0##*/} v${VERSION}

Syntax:
${0##*/} destroysg [ options ] zpool/filesystem ...

OPTIONS:
  -D           = Delete *all* zfsnap snapshots — regardless of their TTL
                 expiration — on all ZFS file systems that follow this option
  -F age       = Force delete all snapshots exceeding "age" — regardless
                 of their TTL expiration — on all ZFS file systems that
                 follow this option
  -g sgCount   = Snapshot group: M, H, d, w, m, y for Minutely, Hourly .. to monthy, yearly.
                 followed by number of snapshots to keep
                 Can be specified multiple times, for each SG with different number
                 e.g.: -g M100 -g H36 -g d10 -g w5 -g m2 -g y1
  -h           = Print this help and exit
  -n           = Dry-run. Perform a trial run with no actions actually performed
  -p prefix    = Enable filtering to only consider snapshots with "prefix";
                 it can be specified multiple times to build a list.
  -P           = Disable filtering for prefixes.
  -r           = Operate recursively on all ZFS file systems after this option
  -R           = Do not operate recursively on all ZFS file systems after this option
  -s           = Skip pools that are resilvering
  -S           = Skip pools that are scrubbing
  -v           = Verbose output

LINKS:
  website:          http://www.zfsnap.org
  repository:       https://github.com/MirLach/zfsnapsg
  bug tracking:     https://github.com/MirLach/zfsnapsg/issues

EOF
    Exit 0
}

# main loop; get options, process snapshot creation
while [ -n "$1" ]; do
    OPTIND=1
    while getopts :DF:g:hnp:PrRsSvz OPT; do
        case "$OPT" in
            D) DELETE_ALL_SNAPSHOTS='true';;
            F) ValidTTL "$OPTARG" || Fatal "Invalid TTL: $OPTARG"
               [ "$OPTARG" = 'forever' ] && Fatal '-F does not accept the "forever" TTL'
               FORCE_AGE_TTL=$OPTARG
               FORCE_DELETE_BY_AGE='true'
               ;;
            g) SGO=$OPTARG; SGOPT="${SGOPT:+$SGOPT }$SGO";;
            h) Help;;
            n) DRY_RUN='true';;
            p) PREFIX=$OPTARG; PREFIXES="${PREFIXES:+$PREFIXES }$PREFIX";;
            P) PREFIX=''; PREFIXES='';;
            r) RECURSIVE='true';;
            R) RECURSIVE='false';;
            s) PopulateSkipPools 'resilver';;
            S) PopulateSkipPools 'scrub';;
            v) VERBOSE='true';;

            :) Fatal "Option -${OPTARG} requires an argument.";;
           \?) Fatal "Invalid option: -${OPTARG}.";;
        esac
    done


    # discard all arguments processed thus far
    shift $(($OPTIND - 1))

    if IsTrue $DRY_RUN ; then
        Note "Dry-Run executed, nothing will bechanged."
    fi

    # operate on pool/fs supplied
    if [ -n "$1" ]; then
        Note "processing '$1' '$SGOPT' '$SG'"

        for SG in $SGOPT; do
            #echo "SG: $SG"
            #SG_T=${SG:0:1}  # bash only
            #SG_C=${SG#w}    # only with predefined character
            #SG_T=$(printf %.1s "$SG")  # can save a fork, '%.1s' instead of '%c' To avoid an error message if $SG is empty string
            SG_T=$(echo $SG | cut -c1)
            SG_C=$(echo $SG | cut -c2-)

            if ! ValidSG $SG_T ; then
                Err "$SG_T is not a valid SG type"
                continue
            fi
            KEEP_SNAP=$((SG_C + 1))

            SG_PREFIXES=$PREFIXES
            # run at least once if there is no prefix
            while true; do
                SG_PREFIX=${SG_PREFIXES%% *}          # get the first prefix from the space separated list
                SG_PREFIXES=${SG_PREFIXES#$SG_PREFIX} # remove first prefix from the list
                SG_PREFIXES=${SG_PREFIXES# }          # remove leading space

                IsTrue "$VERBOSE" && Note "Snapshots with prefix: $SG_PREFIX"

                ## list of filesystems for recursive
                #zfs list -H -o name -S name -t filesystem -r tank0/usr/home
                ## same list built of existing snapshots parent detasets
                #zfs list -H -o name -S name -t snapshot -r tank0/usr/home | cut -d@ -f1 | uniq

                ZFS_SNAPSHOTS=''

                if IsTrue "$RECURSIVE"; then
                    IsTrue "$VERBOSE" && Note "Searching recursive for $1"
                    FS_R=$(zfs list -H -o name -s name -t snapshot -r $1 | grep -E -- "@${SG_PREFIX}${DATE_PATTERN}--${SG_T}\$" | cut -d@ -f1 | uniq)
                    IsTrue "$VERBOSE" && [ -n "$FS_R" ] && Note "Found datasets with expired snapshots to destroy: $FS_R"
                    for FS in $FS_R; do
                        THIS_FS_SNAPS=$($ZFS_CMD list -H -o name -S name -t snapshot $FS | grep -E -- "@${SG_PREFIX}${DATE_PATTERN}--${SG_T}\$" | tail -n+${KEEP_SNAP}) >&2 || Fatal "'$1' does not exist!"
                        ZFS_SNAPSHOTS="${ZFS_SNAPSHOTS:+$ZFS_SNAPSHOTS }$THIS_FS_SNAPS"
                        IsTrue "$VERBOSE" && Note "$SG: $FS Found $(echo "$THIS_FS_SNAPS" | wc -l) to destroy"
                    done
                else
                    IsTrue "$VERBOSE" && Note "Gathering snapshots for $1"
                    ZFS_SNAPSHOTS=$($ZFS_CMD list -H -o name -S name -t snapshot $1 | grep -E -- "@${SG_PREFIX}${DATE_PATTERN}--${SG_T}\$" | tail -n+${KEEP_SNAP}) >&2 || Fatal "'$1' does not exist!"
                    IsTrue "$VERBOSE" && Note "$SG: $FS Found $(echo "$ZFS_SNAPSHOTS" | wc -l) to destroy"
                fi
                # exit while loop if there are no more prefixes
                [ -z "$SG_PREFIXES" ] && break
            done

            for SNAPSHOT in $ZFS_SNAPSHOTS; do
                if IsFalse "$RECURSIVE"; then
                    TrimToFileSystem "$SNAPSHOT" && [ "$RETVAL" = "$1" ] || continue
                fi

                # gets and validates snapshot name
                TrimToSnapshotNameSG "$SNAPSHOT" && SNAPSHOT_NAME=$RETVAL || continue

                RM_SNAPSHOTS="$RM_SNAPSHOTS $SNAPSHOT"
            done
        done
 
        IsTrue "$VERBOSE" && Note "Going to destroy: $RM_SNAPSHOTS"
        printf "%s %d snapshots\n" "Destroying:" $(echo "$RM_SNAPSHOTS" | wc -w)

        for I in $RM_SNAPSHOTS; do
            RmZfsSnapshot "$I"
        done
        RM_SNAPSHOTS=''

        shift
    fi
done
