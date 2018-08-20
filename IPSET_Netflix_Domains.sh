#!/bin/sh
####################################################################################################
# Script: IPSET_Netflix_Domains.sh
# Version 1.0
# Author: Xentrk
# Date: 20-August-2018 
#
# Description:
#    Selective Routing Script for Netflix using Asuswrt-Merlin firmware.
#  
# Grateful:
#   Thank you to @Martineau on snbforums.com for sharing his Selective Routing expertise
#   and on-going support!  
#
####################################################################################################
logger -t "($(basename $0))" $$ Starting Script Execution

# Uncomment the line below for debugging
#set -x

### Define interface/bitmask to route traffic to below
# 0x7000/0x7000- WAN
# 0x1000/0x1000 - VPN Client 1
# 0x2000/0x2000 - VPN Client 2
# 0x3000/0x3000 - VPN Client 3
# 0x4000/0x4000 - VPN Client 4
# 0x5000/0x5000 - VPN Client 5
FWMARK_WAN="0x7000/0x7000"
FWMARK_OVPNC1="0x1000/0x1000"
FWMARK_OVPNC2="0x2000/0x2000"
FWMARK_OVPNC3="0x3000/0x3000"
FWMARK_OVPNC4="0x4000/0x4000"
FWMARK_OVPNC5="0x5000/0x5000"

create_fwmarks () {
# WAN
    ip rule del fwmark "$FWMARK_WAN" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_WAN" table 254 prio 10000
    
#VPN Client 1
    ip rule del fwmark "$FWMARK_OVPNC1" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_OVPNC1" table 111 prio 10100

#VPN Client 2
    ip rule del fwmark "$FWMARK_OVPNC2" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_OVPNC2" table 112 prio 10300

#VPN Client 3
    ip rule del fwmark "$FWMARK_OVPNC3" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_OVPNC3" table 113 prio 10500

#VPN Client 4
    ip rule del fwmark "$FWMARK_OVPNC4" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_OVPNC4" table 114 prio 10700

#VPN Client 5
    ip rule del fwmark "$FWMARK_OVPNC5" > /dev/null 2>&1
    ip rule add fwmark "$FWMARK_OVPNC5" table 115 prio 10800

    ip route flush cache
}


# Chk_Entware function provided by @Martineau at snbforums.com

Chk_Entware () {

    # ARGS [wait attempts] [specific_entware_utility]

    local READY=1                   # Assume Entware Utilities are NOT available
    local ENTWARE="opkg"
    ENTWARE_UTILITY=                # Specific Entware utility to search for
    local MAX_TRIES=30

    if [ ! -z "$2" ] && [ ! -z "$(echo $2 | grep -E '^[0-9]+$')" ];then
        local MAX_TRIES=$2
    fi
 
    if [ ! -z "$1" ] && [ -z "$(echo $1 | grep -E '^[0-9]+$')" ];then
        ENTWARE_UTILITY=$1
    else
        if [ -z "$2" ] && [ ! -z "$(echo $1 | grep -E '^[0-9]+$')" ];then
            MAX_TRIES=$1
        fi
    fi

   # Wait up to (default) 30 seconds to see if Entware utilities available.....
   local TRIES=0

   while [ $TRIES -lt $MAX_TRIES ];do
      if [ ! -z "$(which $ENTWARE)" ] && [ "$($ENTWARE -v | grep -o "version")" == "version" ];then
         if [ ! -z "$ENTWARE_UTILITY" ];then            # Specific Entware utility installed?
            if [ ! -z "$($ENTWARE list-installed $ENTWARE_UTILITY)" ];then
                READY=0                                 # Specific Entware utility found
            else
                # Not all Entware utilities exists as a stand-alone package e.g. 'find' is in package 'findutils'
                if [ -d /opt ] && [ ! -z "$(find /opt/ -name $ENTWARE_UTILITY)" ];then
                  READY=0                               # Specific Entware utility found
                fi
            fi
         else
            READY=0                                     # Entware utilities ready
         fi
         break
      fi
      sleep 1
      logger -st "($(basename $0))" $$ "Entware" $ENTWARE_UTILITY "not available - wait time" $((MAX_TRIES - TRIES-1))" secs left"
      local TRIES=$((TRIES + 1))
   done
 
   return $READY
}
 
# check if /jffs/configs/dnsmasq.conf.add contains entry for iplayer website
check_dnsmasq () {
    if [ -s /jffs/configs/dnsmasq.conf.add ]; then  # dnsmasq.conf.add file exists
        grep "ipset=btstatic.com/netflix.com/nflxext.com/nflximg.net/nflxso.net/nflxvideo.net/thebrighttag.com/NETFLIX" "/jffs/configs/dnsmasq.conf.add"  # see if line exists for NETFLIX
        if [ "$?" = "1" ]; then  # no line for NETFLIX found
            printf "ipset=btstatic.com/netflix.com/nflxext.com/nflximg.net/nflxso.net/nflxvideo.net/thebrighttag.com/NETFLIX\n" >> /jffs/configs/dnsmasq.conf.add # add NETFLIX entry to dnsmasq.conf.add
            service restart_dnsmasq > /dev/null 2>&1
        fi
    else
        printf "ipset=btstatic.com/netflix.com/nflxext.com/nflximg.net/nflxso.net/nflxvideo.net/thebrighttag.com/NETFLIX" > /jffs/configs/dnsmasq.conf.add # dnsmasq.conf.add does not exist, create dnsmasq.conf.add
        service restart_dnsmasq > /dev/null 2>&1
    fi
}

# Create IPSET list NETFLIX
check_ipset_list () {    
    if [ "`ipset list -n NETFLIX`" != "NETFLIX" ]; then #does NETFLIX ipset list exist?
        if [ -s /opt/tmp/NETFLIX ]; then # does NETFLIX ipset restore file exist? 
            ipset restore -! < /opt/tmp/NETFLIX   # Restore ipset list if restore file exists at /opt/tmp/NETFLIX
        else
            ipset create NETFLIX hash:net family inet hashsize 1024 maxelem 65536  # No restore file, so create NETFLIX ipset list from scratch
        fi
    fi
}

# if ipset list NETFLIX is older than 24 hours, save the current ipset list to disk   
check_NETFLIX_restore_file_age () {
    if [ -s /opt/tmp/NETFLIX ]; then
        if [ "`find /opt/tmp/NETFLIX -name NETFLIX -mtime +1 -print /dev/null 2>&1`" = "/opt/tmp/NETFLIX" ] ; then
            ipset save NETFLIX > /opt/tmp/NETFLIX
        fi
    fi
}

# If cronjob to back up the NETFLIX ipset list every 24 hours @ 2:00 AM does not exist, then create it
check_cron_job () {
    cru l | grep NETFLIX_ipset_list 
    if [ "$?" = "1" ]; then  # no cronjob entry found, create it
        cru a NETFLIX_ipset_list "0 2 * * * ipset save NETFLIX > /opt/tmp/NETFLIX"
    fi
}

# Route Netflix to WAN
create_routing_rules () {
    iptables -t mangle -D PREROUTING -i br0 -p tcp -m set --match-set NETFLIX dst,dst -j MARK --set-mark "$FWMARK_WAN" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -p tcp -m set --match-set NETFLIX dst,dst -j MARK --set-mark "$FWMARK_WAN" 

    ip route flush cache
}

create_fwmarks
Chk_Entware
check_dnsmasq
check_ipset_list
check_NETFLIX_restore_file_age
check_cron_job
create_routing_rules

logger -t "($(basename $0))" $$ Ending Script Execution
