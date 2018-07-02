#!/bin/sh
####################################################################################################
# Script: IPSET_Netflix.sh
# Author: Xentrk
# 2-July-2018 Version 3.5
# Collaborators: @Martineau, @thelonelycoder, @Adamm
#
# Thank you to @Martineau on snbforums.com for educating myself and others on Selective
# Routing using Asuswrt-Merlin firmware.
#
#####################################################################################################
# Script Description:
#
# The purpose of this script is for selective routing of Netflix traffic using
# Autonomous System Numbers (ASNs). ASNs are assigned to entities such as Internet
# Service Providers and other large organizations that control blocks of IP addresses.
#
# Netflix and other services that use Amazon AWS servers are blocking VPN's.
#
# This script will
#   1. Create shared whitelist entry for ipinfo.io in /jffs/shared-SelectiveRouting-whitelist for use by AB-Solution and Skynet.
#      Otherwise, ipinfo.io may be blocked and the script will not work.
#    2. Obtain the IPv4 addresses used by Netflix and Amazon AWS USA from ipinfo.io.
#      IPv6 addresses are excluded in this version.
#   3. Create the IPSET list NETFLIX
#   4. Add the IPv4 address to the IPSET list NETFLIX
#   5. Route IPv4 addresses in IPSET list NETFLIX to WAN interface.
#
# Note 1: IPSET syntax differs between version 6 and 4.5
#             Syntax for ipset v6
#                ipset create WAN0 list:set
#                ipset add WAN0 ipv4addr
#                --match-set
#             for routers running ipset v4.5 (ipset -V)
#                create ipset list: ipset -N WAN0 nethash
#                add ipv4 addresses to ipset list: ipset -A WAN0 ipv4addr
#               --set
#
# Note 2: In the event one needs to use IPv6 in the future, the syntax is: ipset -N NETFLIX-v6 hash:net family ipv6
#
# Note 3: Troubleshooting
#
#            You can use these sites for AS validation and troubleshooting to lookup ASNs:
#
#               https://bgp.he.net/AS16509 (Click on the prefixes tab to view IP addresses)
#               https://ipinfo.io/AS2906
# 
# Note 4: Required OpenVPN Client Settings
#
#         - Redirect Internet Traffic = Policy Rules or Policy Rules (Strict)
#         - Others?
#
#######################################################################
logger -t "($(basename $0))" $$ Starting IPSET_Netflix.sh..." $0${*:+ $*}."

# Uncomment for debugging
#set -x

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

eexit() {
    local error_str="$@"
    echo $error_str
    exit 1
}

main() {
    lock $PROGNAME \
        || eexit "Only one instance of $PROGNAME can run at one time."

# Create shared-SelectiveRouting-whitelist file if one does not exist
# to prevent ipinfo.io from being blocked by AB-Solution and Skynet

if [ ! -s "/jffs/shared-SelectiveRouting-whitelist" ];then
# create shared white list for ABS and Skynet"
  echo "ipinfo.io" > /jffs/shared-SelectiveRouting-whitelist
fi

# Create NETFLIX ipset list

list=`ipset list -n NETFLIX` >/dev/null 2>&1
if [ "$list" != "NETFLIX" ]; then
ipset create NETFLIX hash:net family inet hashsize 1024 maxelem 65536
fi

#Pull all IPv4s listed for Netflix USA - AS2906
curl https://ipinfo.io/AS2906 2>/dev/null | grep -E "a href.*2906\/" | grep -v ":" | sed 's/^.*<a href="\/AS2906\///; s/" >//' > /opt/tmp/AS2906
ipset flush NETFLIX 
awk '{print "add NETFLIX " $1}' /opt/tmp/AS2906 | ipset restore -!

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

Chk_Entware 'jq' || { echo -e "\a***ERROR*** Entware" $ENTWARE_UTILITY  "not available";exit 99; }

# Download Amazon AWS json file
wget https://ip-ranges.amazonaws.com/ip-ranges.json -O /opt/tmp/ip-ranges.json


# Create AMAZONAWS ipset list

list=`ipset list -n AMAZONAWS` >/dev/null 2>&1
if [ "$list" != "AMAZONAWS" ]; then
# ipset AMAZONAWS does not exist
ipset create AMAZONAWS hash:net family inet hashsize 1024 maxelem 65536
fi

#Pull all IPv4s listed for Amazon AWS

jq -r '.prefixes | .[].ip_prefix' < /opt/tmp/ip-ranges.json > /opt/tmp/AmazonAWS
ipset flush AMAZONAWS  
awk '{print "add AMAZONAWS " $1}' /opt/tmp/AmazonAWS | ipset restore -!

###########################################################
#Create table to contain items added automatically by wan #
###########################################################
ip rule del prio 9990 > /dev/null 2>&1
ip rule add from 0/0 fwmark 0x7000/0x7000 table main prio 9990

iptables -t mangle -D PREROUTING -i br0 -p tcp -m set --match-set NETFLIX dst,dst -j MARK --set-mark 0x7000/0x7000 > /dev/null 2>&1
iptables -t mangle -A PREROUTING -i br0 -p tcp -m set --match-set NETFLIX dst,dst -j MARK --set-mark 0x7000/0x7000

iptables -t mangle -D PREROUTING -i br0 -p tcp -m set --match-set AMAZONAWS dst,dst -j MARK --set-mark 0x7000/0x7000 > /dev/null 2>&1
iptables -t mangle -A PREROUTING -i br0 -p tcp -m set --match-set AMAZONAWS dst,dst -j MARK --set-mark 0x7000/0x7000

logger -t "($(basename $0))" $$ Ending IPSET_Netflix.sh..." $0${*:+ $*}."
}
main