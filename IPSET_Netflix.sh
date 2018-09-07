#!/bin/sh
####################################################################################################
# Script: IPSET_Netflix.sh
# Author: Xentrk
# 7-September-018 Version 4.0
#
# Thank you to @Martineau on snbforums.com for educating myself and others on Selective
# Routing techniques using Asuswrt-Merlin firmware.
#
# Support Thread: https://www.snbforums.com/threads/selective-routing-for-netflix.42661/
#
#####################################################################################################
# Script Description:
#
# Selectively route Netflix traffic to the WAN interface or OpenVPN interface on
# Asuswrt-Merlin firmware.
#
# Since January 2016, Netflix blocks known VPN servers. The purpose of the IPSET_Netflix.sh
# script is to bypass the OpenVPN Client for Netflix traffic and route it to the WAN interface.
# Netflix also hosts on Amazon AWS servers. Because of this, the script will also route Amazon AWS
# traffic, including Amazon and Amazon Prime traffic, to the WAN interface.
#
#######################################################################
logger -t "($(basename "$0"))" $$ Starting Script Execution

# Uncomment the line below for debugging
#set -x

FILE_DIR="/opt/tmp"


# Prevent script from running concurrently when called from nat-start

PROGNAME=$(basename "$0")
LOCKFILE_DIR=/tmp
LOCK_FD=200

lock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file=$LOCKFILE_DIR/$prefix.lock

    # create lock file
    eval "exec $fd>$lock_file"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}

error_exit() {
    error_str="$@"
    logger -t "($(basename "$0"))" $$ "$error_str"
    exit 1
}

main() {
    lock "$PROGNAME" || error_exit "Exiting $PROGNAME. Only one instance of $PROGNAME can run at one time."

# Create shared-SelectiveRouting-whitelist file if one does not exist
# to prevent ipinfo.io from being blocked by AB-Solution and Skynet

whitelist_ipinfo () {
    if [ ! -s "/jffs/shared-SelectiveRouting-whitelist" ];then
    printf "ipinfo.io\n" > /jffs/shared-SelectiveRouting-whitelist
fi
}

#Download Netflix AS2906 IPv4 addresses

download_AS2906 () {
    curl https://ipinfo.io/AS2906 2>/dev/null | grep -E "a href.*2906\/" | grep -v ":" | sed 's/^.*<a href="\/AS2906\///; s/" >//' > /opt/tmp/x3mRouting_NETFLIX
}

# if ipset list NETFLIX does not exist, create it

check_netflix_ipset_list_exist () {
if [ "$(ipset list -n x3mRouting_NETFLIX 2>/dev/null)" != "x3mRouting_NETFLIX" ]; then
    ipset create x3mRouting_NETFLIX hash:net family inet hashsize 1024 maxelem 65536
fi
}

# if ipset list NETFLIX is empty or source file is older than 24 hours, download source file; load ipset list
check_netflix_ipset_list_values () {
    if [ "$(ipset -L x3mRouting_NETFLIX 2>/dev/null | awk '{ if (FNR == 7) print $0 }' | awk '{print $4 }')" -eq "0" ]; then
        if [ ! -s "$FILE_DIR/x3mRouting_NETFLIX" ] || [ "$(find "$FILE_DIR" -name x3mRouting_NETFLIX -mtime +7 -print)" = "$FILE_DIR/x3mRouting_NETFLIX" ]; then
            download_AS2906
        fi
        awk '{print "add x3mRouting_NETFLIX " $1}' "$FILE_DIR/x3mRouting_NETFLIX" | ipset restore -!
    else
        if [ ! -s "$FILE_DIR/x3mRouting_NETFLIX" ]; then
            download_AS2906
        fi
    fi
}

# Prevent entware funcion jq from executing until entware has mounted
# Chk_Entware function provided by @Martineau

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

# Download Amazon AWS json file

download_AMAZONAWS () {
    wget https://ip-ranges.amazonaws.com/ip-ranges.json -O /opt/tmp/ip-ranges.json

    for REGION in us-east-1 us-east-2 us-west-1 us-west-2
        do
            jq '.prefixes[] | select(.region=='\"$REGION\"') | .ip_prefix' < "$FILE_DIR/ip-ranges.json" | sed 's/"//g' | sort -u >> "$FILE_DIR/x3mRouting_AMAZONAWS"
        done
    rm -rf /opt/tmp/ip-ranges.json
}

# if ipset AMAZONAWS does not exist, create it

check_amazonaws_ipset_list_exist () {
    if [ "$(ipset list -n x3mRouting_AMAZONAWS 2>/dev/null)" != "x3mRouting_AMAZONAWS" ]; then
        ipset create x3mRouting_AMAZONAWS hash:net family inet hashsize 1024 maxelem 65536
    fi
}

# if ipset list AMAZONAWS is empty or source file is older than 24 hours, download source file; load ipset list

check_amazonaws_ipset_list_values () {
    if [ "$(ipset -L x3mRouting_AMAZONAWS 2>/dev/null | awk '{ if (FNR == 7) print $0 }' | awk '{print $4 }')" -eq "0" ]; then
        if [ ! -s "$FILE_DIR/x3mRouting_AMAZONAWS" ] || [ "$(find "$FILE_DIR" -name x3mRouting_AMAZONAWS -mtime +7 -print)" = "$FILE_DIR/x3mRouting_AMAZONAWS" ]; then
            download_AMAZONAWS
        fi
        awk '{print "add x3mRouting_AMAZONAWS " $1}' "$FILE_DIR/x3mRouting_AMAZONAWS" | ipset restore -!
    else
        if [ ! -s "$FILE_DIR/x3mRouting_AMAZONAWS" ]; then
            download_AMAZONAWS
        fi
    fi
}

# Create fwmark for WAN and OpenVPN Interfaces

create_fwmarks () {
# WAN
    ip rule del fwmark "$FWMARK_WAN" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_WAN" table 254 prio 9990

#VPN Client 1
    ip rule del fwmark "$FWMARK_OVPNC1" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_OVPNC1" table 111 prio 9995

#VPN Client 2
    ip rule del fwmark "$FWMARK_OVPNC2" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_OVPNC2" table 112 prio 9994

#VPN Client 3
    ip rule del fwmark "$FWMARK_OVPNC3" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_OVPNC3" table 113 prio 9993

#VPN Client 4
    ip rule del fwmark "$FWMARK_OVPNC4" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_OVPNC4" table 114 prio 9992

#VPN Client 5
    ip rule del fwmark "$FWMARK_OVPNC5" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "$FWMARK_OVPNC5" table 115 prio 9991

    ip route flush cache
}

### Define interface/bitmask to route traffic to below
set_fwmark_parms () {
    FWMARK_WAN="0x8000/0x8000"
    FWMARK_OVPNC1="0x1000/0x1000"
    FWMARK_OVPNC2="0x2000/0x2000"
    FWMARK_OVPNC3="0x4000/0x4000"
    FWMARK_OVPNC4="0x7000/0x7000"
    FWMARK_OVPNC5="0x3000/0x3000"
}

# route NETFLIX and AMAZONAWS traffic to WAN

create_routing_rules () {
    iptables -t mangle -D PREROUTING -i br0 -m set --match-set x3mRouting_NETFLIX dst -j MARK --set-mark "$FWMARK_WAN" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -m set --match-set x3mRouting_NETFLIX dst -j MARK --set-mark "$FWMARK_WAN"

    iptables -t mangle -D PREROUTING -i br0 -m set --match-set x3mRouting_AMAZONAWS dst -j MARK --set-mark "$FWMARK_WAN" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -m set --match-set x3mRouting_AMAZONAWS dst -j MARK --set-mark "$FWMARK_WAN"
}

whitelist_ipinfo
Chk_Entware 30 jq
check_netflix_ipset_list_exist
check_netflix_ipset_list_values
check_amazonaws_ipset_list_exist
check_amazonaws_ipset_list_values
set_fwmark_parms
create_fwmarks
create_routing_rules
}

main
logger -t "($(basename "$0"))" $$ Completed Script Execution
