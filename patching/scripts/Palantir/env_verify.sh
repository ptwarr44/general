#!/bin/bash
# @brief environment-/system-specific script to be called from post_update.sh
#        returns 0 or 1 value to $errorCheck in post_update.sh for overall
#        status to be emailed out upon script conclusion.  This script
#        will contain environment-specific verification commands.

###########################
# Begin Body              #

errorCheck=0

log_info "========================================================"
log_info "= Environment-specific starts and checks"
log_info "========================================================"

# Start PPM
(su - ppmadmin -c 'cd /home/ppmadmin/eppm_staging/bin && /home/ppmadmin/eppm_staging/bin/kStart.sh -name eppm_stagingu1')

result=$(grep -c '*** Ready!' /home/ppmadmin/eppm_staging/server/eppm_stagingu1/log/serverLog.txt)
count=0

# Watch PPM serverLog.txt file for a couple minutes to make sure it comes up before continuing
while [ "$result" -lt 1 ] && [ "$count" -lt 9 ]; do
    sleep 20
    result=$(grep -c '*** Ready!' /home/ppmadmin/eppm_staging/server/eppm_stagingu1/log/serverLog.txt)
    count=$((count + 1))
done

# If PPM hasn't started by now, manual intervention/review will be necessary
if [ "$result" -lt 1 ] && [ "$count" -ge 9 ]; then
    log_error "PPM has NOT started"
    errorCheck=1
else
    log_info "PPM has started successfully"
fi

return $errorCheck