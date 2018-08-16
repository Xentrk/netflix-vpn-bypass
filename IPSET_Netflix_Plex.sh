#!/bin/sh
####################################################################################################
# Script: IPSET_Netflix_Plex.sh
# Author: Xentrk
# 16-Aug-2018 Version 1.0.0
#
# Thank you to @Martineau on snbforums.com for educating myself and others on Selective
# Routing techniques using Asuswrt-Merlin firmware.
#
# Support Thread: https://www.snbforums.com/threads/selective-routing-for-netflix.42661/
#
#####################################################################################################
# Script Description:
#
# Bypass the OpenVPN Client and selectively route Netflix traffic to the WAN interface on 
# AsusWRT-Merlin firmware
#
# Since January 2016, Netflix blocks known VPN servers. The purpose of the IPSET_Netflix.sh
# script is to bypass the OpenVPN Client for Netflix traffic and route it to the WAN interface. 
# Netflix also hosts on Amazon AWS servers. Because of this, the script will also route Amazon AWS 
# traffic, including Amazon and Amazon Prime traffic, to the WAN interface.
#
# Autonomous System Numbers (ASNs) are assigned to entities such as Internet Service Providers and 
# other large organizations that control blocks of IP addresses. The ASN for Netflix is AS2906. 
# Amazon AWS supplies the list of IPv4 addresses in the json file available at 
# https://ip-ranges.amazonaws.com/ip-ranges.json
#
# This script will
#
# 1) Create the IPSET lists NETFLIX and AMAZONAWS
# 2) Obtain the IPv4 addresses used by Netflix using AS2906 from ipinfo.io.
# 3) Add the Netflix IPv4 address to the IPSET list NETFLIX
# 4) Parse the Amazon AWS json file using the jq entware package for IPv4 addresses used by Amazon
# 5) Add the Amazon IPv4 address to the IPSET list AMAZONAWS
# 6) Route IPv4 addresses in IPSET list NETFLIX and AMAZONAWS to WAN interface
#
# IPv6 addresses are excluded in this version.
#
# Requirements
#
#  1) Installation of entware package jq. jq is a json file parser. To install, enter the command "opkg install jq" on the command line. 
#  2) ipset version 6. Support for ipset version 4.5 is planned for a future release
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
# You can use these sites for AS validation and troubleshooting to lookup ASNs:
#  https://bgp.he.net/AS16509 - This is the ASN for Amazon USA (Click on the prefixes tab to view IP addresses)
#  https://ipinfo.io/AS2906 - Netflix ASN
# 
# Note 4: Required OpenVPN Client Settings
#
#  - Redirect Internet Traffic = Policy Rules or Policy Rules (Strict)
#  
#######################################################################
logger -t "($(basename $0))" $$ Starting Script Execution

# Uncomment the line below for debugging
set -x

# Define Interface/bitmask for interfaces 
# 0x7000/0x7000- WAN
# 0x1000/0x1000 - VPN Client 1
# 0x2000/0x2000 - VPN Client 2
# 0x3000/0x3000 - VPN Client 3
# 0x4000/0x4000 - VPN Client 4
# 0x5000/0x5000 - VPN Client 5
FWMARK_WAN="0x7000/0x7000"
FWMARK_OVPNC1="0x1000/0x1000"


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

whitelist_ipinfo () {
if [ ! -s "/jffs/shared-SelectiveRouting-whitelist" ];then
  echo "ipinfo.io" > /jffs/shared-SelectiveRouting-whitelist
fi
}

 


# Create fwmark for WAN and OVPNC Interface
create_fwmarks () {
# WAN
    ip rule del fwmark 0x7000/0x7000 > /dev/null 2>&1
    ip rule add fwmark 0x7000/0x7000 table 254 prio 9990
    
#VPN Client 1
    ip rule del fwmark 0x1000/0x1000 > /dev/null 2>&1
    ip rule add fwmark 0x1000/0x1000 table 111 prio 9991

#VPN Client 2
    ip rule del fwmark 0x2000/0x2000 > /dev/null 2>&1
    ip rule add fwmark 0x2000/0x2000 table 112 prio 5020

#VPN Client 3
    ip rule del fwmark 0x3000/0x3000 > /dev/null 2>&1
    ip rule add fwmark 0x3000/0x3000 table 113 prio 5005

#VPN Client 4
    ip rule del fwmark 0x4000/0x4000 > /dev/null 2>&1
    ip rule add fwmark 0x4000/0x4000 table 114 prio 5040

#VPN Client 5
    ip rule del fwmark 0x5000/0x5000 > /dev/null 2>&1
    ip rule add fwmark 0x5000/0x5000 table 115 prio 5050
    
    ip route flush cache
}    
    
#Download Netflix AS2906 IPv4 addresses

download_AS2906 () {
    curl https://ipinfo.io/AS2906 2>/dev/null | grep -E "a href.*2906\/" | grep -v ":" | sed 's/^.*<a href="\/AS2906\///; s/" >//' > "$FILE_DIR/x3mRouting_NETFLIX"
    if [ "$?" = "1" ]; then  # file download failed
        logger -t "($(basename "$0"))" $$ Script execution failed because Netflix AS2906 file could not be downloaded
        exit 1
    fi
}

# if ipset list NETFLIX does not exist, create it
check_ipset_list_exist_x3mRouting_NETFLIX () {
    if [ "$(ipset list -n x3mRouting_NETFLIX 2>/dev/null)" != "x3mRouting_NETFLIX" ]; then
        ipset create x3mRouting_NETFLIX hash:net family inet hashsize 1024 maxelem 65536
    fi
}

# if ipset list NETFLIX is empty or source file is older than 24 hours, download source file; load ipset list  

check_ipset_list_values_x3mRouting_NETFLIX () {
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

# Download Amazon AWS json file
download_AMAZONAWS_US () {
    wget https://ip-ranges.amazonaws.com/ip-ranges.json -O "$FILE_DIR/ip-ranges.json" 
    if [ "$?" = "1" ]; then  # file download failed
        logger -t "($(basename "$0"))" $$ Script execution failed because https://ip-ranges.amazonaws.com/ip-ranges.json file could not be downloaded
        exit 1
    fi
    true > "$FILE_DIR/x3mRouting_AMAZONAWS_US"
    for REGION in us-east-1 us-east-2 us-west-1 us-west-2
        do
            jq '.prefixes[] | select(.region=='\"$REGION\"') | .ip_prefix' < "$FILE_DIR/ip-ranges.json" | sed 's/"//g' | sort -u >> "$FILE_DIR/x3mRouting_AMAZONAWS_US"
        done
}

# if ipset x3mRouting_AMAZONAWS does not exist, create it

check_ipset_list_exist_x3mRouting_AMAZONAWS_US () {
    if [ "$(ipset list -n x3mRouting_AMAZONAWS_US 2>/dev/null)" != "x3mRouting_AMAZONAWS_US" ]; then
        ipset create x3mRouting_AMAZONAWS_US hash:net family inet hashsize 1024 maxelem 65536
    fi
}

# if ipset list AMAZONAWS_US is empty or source file is older than 7 days, download source file; load ipset list

check_ipset_list_values_x3mRouting_AMAZONAWS_US () {
    if [ "$(ipset -L x3mRouting_AMAZONAWS_US 2>/dev/null | awk '{ if (FNR == 7) print $0 }' | awk '{print $4 }')" -eq "0" ]; then
        if [ ! -s "$FILE_DIR/x3mRouting_AMAZONAWS_US" ] || [ "$(find "$FILE_DIR" -name x3mRouting_AMAZONAWS_US -mtime +7 -print)" = "$FILE_DIR/x3mRouting_AMAZONAWS_US" ]; then 
            download_AMAZONAWS_US
        fi
        awk '{print "add x3mRouting_AMAZONAWS_US " $1}' "$FILE_DIR/x3mRouting_AMAZONAWS_US" | ipset restore -!  
    else 
        if [ ! -s "$FILE_DIR/x3mRouting_AMAZONAWS_US" ]; then 
            download_AMAZONAWS_US
        fi
    fi
}

# route NETFLIX and AMAZONAWS_US traffic to VPN Client

create_routing_rules () {
# route plex.tv domains to OPVNC1
    iptables -t mangle -A PREROUTING -i br0 -p tcp -d 184.72.0.0/16 -j MARK --set-mark "$FWMARK_OVPNC1"
    iptables -t mangle -A PREROUTING -i br0 -p tcp -d 50.18.0.0/16 -j MARK --set-mark "$FWMARK_OVPNC1"
    iptables -t mangle -A PREROUTING -i br0 -p tcp -d 184.169.0.0/16 -j MARK --set-mark "$FWMARK_OVPNC1"
    iptables -t mangle -A PREROUTING -i br0 -p tcp -d 54.241.0.0/16 -j MARK --set-mark "$FWMARK_OVPNC1"
    iptables -t mangle -A PREROUTING -i br0 -p tcp -d 54.176.0.0/16 -j MARK --set-mark "$FWMARK_OVPNC1"

    iptables -t mangle -D PREROUTING -i br0 -p tcp -m set --match-set x3mRouting_NETFLIX dst,dst -j MARK --set-mark "$FWMARK_WAN" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -p tcp -m set --match-set x3mRouting_NETFLIX dst,dst -j MARK --set-mark "$FWMARK_WAN"

    iptables -t mangle -D PREROUTING -i br0 -p tcp -m set --match-set x3mRouting_AMAZONAWS_US dst,dst -j MARK --set-mark "$FWMARK_WAN" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -p tcp -m set --match-set x3mRouting_AMAZONAWS_US dst,dst -j MARK --set-mark "$FWMARK_WAN"
}

Chk_Entware 'jq' || { echo -e "\a***ERROR*** Entware" $ENTWARE_UTILITY  "not available";exit 99; }

whitelist_ipinfo

create_fwmarks

check_ipset_list_exist_x3mRouting_NETFLIX
check_ipset_list_values_x3mRouting_NETFLIX 

check_ipset_list_exist_x3mRouting_AMAZONAWS_US
check_ipset_list_values_x3mRouting_AMAZONAWS_US 

create_routing_rules

}
main

logger -t "($(basename "$0"))" $$ Completed Script Execution
