#!/bin/bash

# This script shall be placed in /etc/cron.daily and made executable
# This script fetches System Event Log using ipmitool, sends new SEL to syslog
# and make a copy to local file system

set -e

[ -f /etc/sysconfig/ipmi-sel-archive.conf ] && . /etc/sysconfig/ipmi-sel-archive.conf
LOGPATH=${LOGPATH:-"/var/log/ipmi-sel-archive"}
SELDUMP=${SELDUMP:-"/var/run/ipmi-sel-archive.log"}
SELHIGHWATERMARK=${SELHIGHWATERMARK:-"80"}

preflight () {
  BINS="ipmitool openssl readlink cut grep echo test hostname touch date"
  for i in $BINS; do which $i > /dev/null || exit 1; done

  # log path exists?
  [ ! -d $LOGPATH ] && mkdir -p $LOGPATH || exit 1

  # sensible SEL High Water Mark (SELHIGHWATERMARK)?
  [ $SELHIGHWATERMARK -gt 79 ] && [ $SELHIGHWATERMARK -lt 101 ] || exit 1

  # we will set BMC clock, we want a good system clock, do we have one?
  pgrep "(chronyd|ntpd)" > /dev/null || exit 1
  
  # is ipmi accessible?
  lsmod | grep -q ipmi_devintf || modprobe ipmi_devintf
  ipmitool chassis status > /dev/null || exit 2
  # we are going to set bmc clock, log current bmc time just in case
  echo "bmc clock pre-sync: $(ipmitool sel time get)" | logger -t ipmi-sel-archive
  # setting clock as suggested by ipmitool man page (mostly concerning clearing sel)
  ipmitool sel time set "`date +"%m/%d/%Y %H:%M:%S"`" || exit 2
  echo "bmc clock post-sync: $(ipmitool sel time get)" | logger -t ipmi-sel-archive
}

host_id () {
  ipmitool sel elist > $SELDUMP || exit 2

  MACADDR="$(ipmitool lan print 1 | grep -i 'mac addr' | grep -o -e '\(\S\S:\)\{5\}\S\S')"
  [ "$MACADDR" ] && export MACADDR || exit 3

  HOSTFQDN="$(hostname --fqdn)"
  [ "$HOSTFQDN" ] && export HOSTFQDN || exit 3

  SEL1="$(head -1 $SELDUMP)"
  [ "$SEL1" ] && export SELID="$(echo $MACADDR$SEL1 | openssl sha512 | cut -d' ' -f2 | cut -b1-6)" || exit 3
  export SELBASENAME="$HOSTFQDN-$MACADDR-$SELID.log"
  export SELOUT="$(readlink -m $LOGPATH/$SELBASENAME)"

  # make sure we can write out
  touch $SELOUT && [ -w "$SELOUT" ] || exit 1
}

clear_sel_when_full () {
  SELFull="$(ipmitool sel | grep Percent | cut -d: -f2 | cut -d% -f1)"
  [ $SELFull -gt $SELHIGHWATERMARK ] && ipmitool sel clear
}

# Pull SEL from BMC
pull_sel_from_bmc () {
  SELDIFF=$SELDUMP.diff
  if diff -au $SELOUT $SELDUMP > $SELDIFF; then
    # diff empty, we supposed have archived everything
    # Let's empty SEL if it's nearly full.
    clear_sel_when_full
  else
    # we got something new
    export SELDIFF
  fi
}

# Push SEL to syslog
push_sel_to_syslog () {
  # make sure we don't hit the default rate limit of 200 messages / 5s; or we lose records
  if [ -s "$SELDIFF" ]; then
    curp=1 ; curq=20
    while [ "$(sed -n $curp,$curq\p <(grep "^+ " $SELDIFF | cut -d+ -f2-))" ]; do
     sed -n $curp,$curq\p <(grep "^+ " $SELDIFF | cut -d+ -f2-) | logger -t ipmi-sel-archive
      sleep 1
      curp="$(expr $curp + 20)"; curq="$(expr $curq + 20)"
    done
  # archive SEL to file system
  cp -f $SELDUMP $SELOUT
  fi
}

preflight
host_id

pull_sel_from_bmc
push_sel_to_syslog
