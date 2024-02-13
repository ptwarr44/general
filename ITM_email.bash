#!/bin/ksh
#
# Purpose: To send formatted emails from ITM for UNIX servers
# Requirements: Arguments must be passed in the correct order listed below format
#
# ARGV[x] from ITM or custom script
# 1: Source Node (hostname)
# 2: Subject
# 3: Key:Value description comma (,) delimited. Comma will be replaced with newline character
#      e.x. - "Mount Point:${MP},Used Percent:${USED}"
#
# Usage:
#
# /prod/OSS/ITM/itmMail.sh &{Disk.System_Name} "UNIX Filesystem Usage" "Mount Point:&{Disk.Mount_Point},Used Percent:&{Disk.Space_Used_Percent} %"

ADMIN_EMAILS="LPNT.DLUnixInfrastructureServices@lpnt.net"

# Used in SUBJECT
HEADER="IBM Tivoli Monitoring -"
TIMESTAMP=`date '+%H:%M:%S %D'`

# Variables
HOSTNAME=$1
HN=`echo "$HOSTNAME" | sed 's/:KUX//g'`
SUBJECT="$HEADER $2"
OTHER=$3

NL=`echo "$OTHER" | tr ',' '\n'`
SPACE=`echo "$NL" | sed 's/:/: /g'`

# Body of alert
BODY="IBM Tivoli Monitoring

Server: $HN
Timestamp: $TIMESTAMP

$SPACE
"
echo "$BODY" | mailx -s "$SUBJECT" "$ADMIN_EMAILS "

