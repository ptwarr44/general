#!/bin/bash
# @brief script that runs at the end of patching (post-reboot if reboot is
#        required) that checks uptime, running kernel, prints latest update
#        actions, and performs various system checks defined for a given
#        environment

# Load config file

source /usr/local/scripts/post_update_conf.env

###########################
# Begin Functions         #
function log_msg {
  current_time=$(date "+%Y-%m-%d %H:%M:%S.%3N")
  log_level=$1
  # all arguments except for the first one, since that is the level
  log_msg="${@:2}"
  echo "[$current_time] $log_level - $log_msg" >> "$logFile"
}

function log_error {
  log_msg "ERROR" "$@"
}

function log_info {
  log_msg "INFO " "$@"
}

function log_debug {
  log_msg "DEBUG" "$@"
}

function compare_errata {
  # Function code adapted from code by R. Paxton
  (yum updateinfo list installed | tail -n +3 | grep -v updateinfo | sort > "$workDir"/.current.errata)

  #Initialize last errata info if none (display full errar list)
  if [[ ! -s "$workDir"/.last.errata ]]; then
    touch "$workDir"/.last.errata
  fi

  # Compare last errata to current errata and only log changes.
  comm -3 "$workDir"/.last.errata "$workDir"/.current.errata > "$workDir"/.new.errata

  mv -f "$workDir"/.current.errata "$workDir"/.last.errata

  # Massage new errata list
  if [[ ! -s "$workDir"/.new.errata  ]]; then
    echo -e "\n========== new errata ===========\n" > "$workDir"/.new.errata
    echo "No new errata applied to this host since last update." >> "$workDir"/.new.errata
  else
    # Remove leading whitespace from comm
    sed -i 's/^\s*//' "$workDir"/.new.errata
    sed -i '1s/^/\n========== new errata ===========\n\n/' "$workDir"/.new.errata
  fi

  # Get last yum history info
  lastUpdate=$(yum history | head -1 | awk '{print $1}')

  # Massage update history info
  yum history info "$lastUpdate" > "$workDir"/.yum.history
  echo -e "\n========== last update history ===========\n" >> "$workDir"/.new.errata
  cat "$workDir"/.yum.history >> "$workDir"/.new.errata
  cat "$workDir"/.new.errata >> "$logFile"

}
# End Functions           #
###########################
###########################
# Begin Body              #
errorCheck=0

cat /dev/null > "$logFile"

log_info "========================================================"
log_info "= Post-update status for $HOSTNAME"
log_info "========================================================"

log_info "Running Kernel: "
result=$(uname -r)
log_info "${result}"

log_info "System Uptime: "
result=$(uptime)
log_info "${result}"
log_info ""

log_info "========================================================"
log_info "= Update history:"
log_info "========================================================"

# Collect and clean up update information
compare_errata

# Execute environment/system-specific validation script if it exists
if [ -f "$snowFlake" ]; then
  . "$snowFlake"
  errorCheck=$?
fi

# Final status of healthchecks - prepend to top of logFile
if [ ${errorCheck} != 0 ]; then
        statusMsg="STATUS: ERROR: Something went wrong.  Please review results"
        sed -i "1s/^/$statusMsg\n\n/" "$logFile"
else
        statusMsg="STATUS: OK"
        sed -i "1s/^/$statusMsg\n\n/" "$logFile"
fi

/bin/mail -s "Post-patching report for $HOSTNAME" "$email"  < "$logFile"
