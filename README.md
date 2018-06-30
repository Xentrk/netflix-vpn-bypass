# netflix-vpn-bypass
Bypass the OpenVPN Client and selectively route Netflix traffic to the WAN interface on AsusWRT-Merlin firmware

Since January 2016, Netflix blocks known VPN servers.  The purpose of the IPSET_Netflix.sh script is to bypass the OpenVPN Client and route Netflix traffic to the WAN interface.  Netflix hosts on Amazon AWS servers.  Because of this, the script will also route Amazon AWS traffic, including Amazon and Amazon Prime, to the WAN interface. 

Autonomous System Numbers (ASNs) are assigned to entities such as Internet Service Providers and other large organizations that control blocks of IP addresses. The ASN for Netflix is AS2906.  Amazon AWS supplies the list of IPv4 addresses in the json file at 
https://ip-ranges.amazonaws.com/ip-ranges.json


This script will

    Create the IPSET lists NETFLIX and AMAZONAWS
    Obtain the IPv4 addresses used by Netflix using AS2906 from ipinfo.io.
    Add the Netflix IPv4 address to the IPSET list NETFLIX
    Parse the Amazon AWS json file using the jq entware package for IPv4 addresses used by Amazon
    Add the Amazon IPv4 address to the IPSET list AMAZONAWS
    Route IPv4 addresses in IPSET list NETFLIX and AMAZONAWS to WAN interface

IPv6 addresses are excluded in this version.

Requirements:

Installation of entware package jq.  jq is a json file parser.  To install, enter the command "opkg install jq" on the command line.

Support available on snbforums.com 
https://www.snbforums.com/threads/selective-routing-for-netflix.42661/

Installation:

    /usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/Xentrk/netflix-vpn-bypass/master/IPSET_Netflix.sh" -o /jffs/scripts/IPSET_Netflix.sh

IPv6 addresses are excluded in this version.





