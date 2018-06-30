# netflix-vpn-bypass
Bypass OpenVPN tunnel and selectively route Netflix traffic to the WAN inferface on AsusWRT-Merlin firmware

Since 2016, Netflix blocks known VPN servers. The purpose of this script is to bypass the OpenVPN tunnel and route Netflix traffic to the WAN interface, bypassing the OpenVPN tunnel.  However, Netflix also hosts on Amazon AWS servers.  As a result, this script will also route Amazon AWS traffic, including Amazon and Amazon Prime, to the WAN interface.  

Using Autonomous System Numbers (ASNs) are assigned to entities such as Internet Service Providers and other large organizations that control blocks of IP addresses.  

This script will

    Obtain the IPv4 addresses used by Netflix and Amazon AWS using their ASN from ipinfo.io.
    IPv6 addresses are excluded in this version.
    Create the IPSET list NETFLIX and AMAZONAWS
    Add the Netflix IPv4 address to the IPSET list NETFLIX
    Add the Amazon IPv4 address to the IPSET list AMAZONAWS
    Route IPv4 addresses in IPSET list NETFLIX and AMAZONAWS to WAN interface


