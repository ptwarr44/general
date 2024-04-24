#!/usr/bin/ksh

# Script: to migrate JFS file systems to JFS2
# Author: Unix team 
# Date written: November 30th, 2018
# ---------------------------------------------------------------------------
# Note: Pre-requisite is ptraid volume group and ptraid2 volume group
# where ptraid is the input VG (JFS) and ptraids is output VG (JFS2)
# 1. Present a new volume group ptraid2 with enough storage for the migration
# 2. Ensure all processes have been stopped and no one is using the file systems
#    script will abort when file system detected as in use
# 3. New replacement JFS2 file system will be created 1G larger than the existing JFS
#
# Note: once migrated, the original FS will be appended with _OLD
# example: /ptvol1 will be renamed to /ptvol1_OLD
# ---------------------------------------------------------------------------

FROM_VG=ptraid
TO_VG=protvg
TMP_FILE=/tmp/migrate_jfs.tmp
NEW_JFS2_FS='/NEW_JFS2'

# Function to check volume groups (FROM and TO VG) to make sure exists
check_VG_Exists()
{
  VG_EXISTS=`lsvg | grep $FROM_VG`
  # check if from volume group exists
  if [[ -z $VG_EXISTS ]];
     then
        print "FROM Volume group: $VG_EXISTS does not exist! No migration \n"
        exit
     fi

  VG_EXISTS=`lsvg | grep $TO_VG`
  # check if from volume group exists
  if [[ -z $VG_EXISTS ]];
     then
        print "TO Volume group: $TO_VG does not exist! No migration \n"
        exit
  fi
}

# Function to check if FS is in use
check_FS_INUSE()
{
if [[ -a $TMP_FILE ]];
   then
        rm -f $TMP_FILE
   fi

# Check if any file system is in use
for JFS_FS in `lsvg -l $FROM_VG | grep -v jfslog | grep -v OLD| grep -v jfs2log | grep jfs | awk '{print $7}'`
  do
        fuser -cu $JFS_FS > $TMP_FILE
        if [[ -s $TMP_FILE ]];
           then
                print "***  $JFS_FS is in use and no migration! *** \n"
                exit
           else
                print " $JFS_FS is not in use - continue... \n"
        fi
  done
}

# Function to list JFS file systems to be migrated and prompt for confirmation
list_JFS_Migration()
{

# List number of JFS file systems to be migrated
COUNT=0
for JFS_FS in `lsvg -l $FROM_VG | grep -v jfslog | grep -v OLD| grep -v jfs2log | grep jfs | awk '{print $7}'`
  do
        ((COUNT = $COUNT+1))
        print "$COUNT . $JFS_FS \n"
  done
  if [[ $COUNT != 0 ]];
     then
        print "Above is a list of JFS file system found to be migrated: \n"
        read input_migration?'Press enter to begin migration or "n" to abort: '
        if [[ $input_migration == 'n' || $input_migration == 'N' ]];
           then
           print "n selected.  Migration aborted! \n"
           exit
           fi
     else
        print "No JFS file system found in ptraid volume group to be migrated! \n"
     fi
}

# Function to umount and remount of JFS FS
umount_remount_JFS()
{
# umount and remount of existing JFS file system prior to the migration
for JFS_FS in `lsvg -l $FROM_VG | grep -v jfslog | grep -v OLD| grep -v jfs2log | grep jfs | awk '{print $7}'`
  do
        print "umounting and remount of $JFS_FS prior to migration \n"
        umount $JFS_FS
        if [[ $? -eq 0  ]]
           then
                mount $JFS_FS
        else
                print "unable to umount $JFS_FS .  Migration abort! \n"
                exit
        fi
  done
}

# Function to kill axon processes to unlock file systems
axon_process_Kill()
{
# umount and remount of existing JFS file system prior to the migration
for PROCESS in `ps -ef | grep -v grep | grep axon| awk '{print $2}'`
  do
        print "Terminating axon process - $PROCESS \n"
        kill -9 $PROCESS
  done
  # wait for 10 seconds to ensure processes terminated before continuing
  sleep 10
}

#
# Main script
#

  # In case of non-root user, exit
  if [[ $USER != 'root' ]];
    then
        print "to be used by root user only! \n"
        exit
    fi

  # kill axon processes if they are still running...
    axon_process_Kill

  # check for pre-requisite VGs
    check_VG_Exists

  # check if FS is in use
    check_FS_INUSE

  # umount and remount of JFS before migration
    umount_remount_JFS

  # List of JFS file systems to be migrated and prompt for confirmation to migrate
    list_JFS_Migration

# Display Date/Time (begin)
echo "Begin: current date/time is:" `date +"%m%d%y_%H%M"`

# Stop SSHD
stopsrc -s sshd

# Loop to create JFS2 file system and migrate data
for JFS_FS in `lsvg -l $FROM_VG | grep -v jfslog | grep -v jfs2log | grep -v OLD | grep jfs | awk '{print $7}'`
  do
        # find the size of existing mount point and add 1G to the existing size in GB
        SIZE=`df -g | grep -w $JFS_FS | awk '{print $2}' | awk -F\. '{print $1}'`
        ((SIZE = $SIZE+1))

        # create the new JFS2 file system
        print "Temporary JFS2 File System: $NEW_JFS2_FS will be created with size of $SIZE GB \n"
        crfs -v jfs2 -g $TO_VG -a size=${SIZE}G -A yes -m $NEW_JFS2_FS

        # mount the new JFS2 file system
        print "Mounting temporary JFS2 file system - $NEW_JFS2_FS \n"
        mount $NEW_JFS2_FS

        # copy the data from existing JFS filesystem to new JFS2 file system
        print "Copying data from $JFS_FS to $NEW_JFS2_FS using pax command... \n"
        cd $JFS_FS; pax -r -w -x pax -p e * $NEW_JFS2_FS

        # kill axon processes if they are still running...
        axon_process_Kill

        # capture the owner and group for the old file system
        OWNER=`ls -al $JFS_FS | grep -v total | grep dr | head -1 | awk '{print $3}'`
        GROUP=`ls -al $JFS_FS | grep -v total | grep dr | head -1 | awk '{print $4}'`

        # unmount the JFS and JFS filesystem
        print "unmounting $JFS_FS and $NEW_JFS2_FS \n"
        cd /; umount $JFS_FS; umount $NEW_JFS2_FS;

        # rename the JFS file system and append it with _OLD
        print "Renaming $JFS_FS to ${JFS_FS}_OLD... \n"
        chfs -m ${JFS_FS}_OLD $JFS_FS

        # rename the JFS2 file system as the existing filesystem name
        print "Renaming $NEW_JFS2_FS to ${JFS_FS}... \n"
        chfs -m $JFS_FS $NEW_JFS2_FS

        # mount the converted JFS2 file system using the same mount point before
        print "Mounting new JFS2 file system - $JFS_FS \n"
        mount $JFS_FS

        # update the owner:group for the new FileSystem
        print "Update the new file system $JFS_FS with correct owner and group: $OWNER:$GROUP \n"
        chown $OWNER:$GROUP $JFS_FS

        #Completed one migration
        print "Completed JFS to JFS2 migration for $JFS_FS. \n"
  done

# Start SSHD
startsrc -s sshd

# Display Date/Time (completed)
echo "Completed: current date/time is:" `date +"%m%d%y_%H%M"`

exit
