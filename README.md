# netflix-vpn-bypass
Selectively route Netflix traffic to the WAN interface, or one of the five OpenVPN clients, on **Asuswrt-Merlin** firmware.  

Since January 2016, Netflix blocks known VPN servers. This project was originally developed to bypass the OpenVPN client for Netflix traffic and route it to the WAN interface. The scripts now provide the ability to route Netflix traffic to an OpenVPN Client if desired. This can be accomplished by editing the $FWMARK parameter in the iptables commands inside the **create_routing_rules** function. If you want a VPN provider who can circumvent the Netflix VPN ban, see my blog post [Why I use Torguard as my VPN Provider](https://x3mtek.com/why-i-use-torguard-as-my-vpn-provider) to learn more. 

Netflix hosts on Amazon AWS servers. As a result, Amazon AWS domains in the US are also included.

There are two selective routing scripts used in this project. Each one uses a different method to collect the IPv4 addresses required for selective routing. Both scripts use the features of [IPSET](http://ipset.netfilter.org/) to collect IPv4 addresses in IPSET lists and match against the IPSET lists.

**IPSET_Netflix.sh** collects the IPv4 addresses used by Netflix from https://ipinfo.io using the Autonomous System Number (ASN) assigned to Netflix. Amazon AWS supplies the list of IPv4 addresses in the json file at https://ip-ranges.amazonaws.com/ip-ranges.json

Only the Amazon AWS US Regions are extracted from ip-ranges.json. As a result, the script will also route all Amazon AWS traffic bound for the US, including Amazon Prime traffic, to the WAN interface.

**IPSET_Netflix_Domains.sh** uses the IPSET feature built into dnsmasq to dynamically generate the IPv4 address used by Netflix and Amazon AWS dynamically.  This approach can be useful when your ISP is using the [Netflix Open Connect Network](https://media.netflix.com/en/company-blog/how-netflix-works-with-isps-around-the-globe-to-deliver-a-great-viewing-experience).

#### Requirements

1. Installation of [entware]( https://github.com/RMerl/asuswrt-merlin/wiki/Entware).  The **/opt/tmp** directory on entware is used to store the files containing the IPv4 addresses for the **IPSET_Netflix.sh** script and the backup IPSET list file for the **IPSET_Netflix_Domains.sh** script.  
2. The entware package **jq** is required by the **IPSET_Netflix.sh** script. **jq** is a json file parser.  To install **jq**, enter the command ```opkg install jq``` on the command line.
3. ipset version 6. To confirm the version you have installed, type ```ipset -v```
4. OpenVPN Client Settings:
    - set **Redirect Internet traffic** to **Policy Rules** or **Policy Rules (Strict)**
    - dnsmasq is bypassed when **Accept DNS Configuration** is set to **Exclusive**.  I recommend setting **Accept DNS Configuration**  to **Strict** as a solution. In the **Custom Config** section, specify a DNS server of your choice using the command ```dhcp-option DNS xxx.xxx.xxx.xxx``` where the xxx's are a DNS server of your choice. For example:
    ```dhcp-option DNS 1.1.1.1```

### IPSET_Netflix.sh
Autonomous System Numbers (ASNs) are assigned to entities such as Internet Service Providers and other large organizations that control blocks of IP addresses. The ASN for Netflix is AS2906.  

This script will:
1. Create the IPSET lists x3mRouting_NETFLIX and x3mRouting_AMAZONAWS
2. Obtain the IPv4 addresses used by Netflix using AS2906 from ipinfo.io.
3. Add the Netflix IPv4 address to the IPSET list x3mRouting_NETFLIX
4. Parse the Amazon AWS json file using the jq entware package for IPv4 addresses used by Amazon in the US Region
5. Add the Amazon IPv4 address to the IPSET list x3mRouting_AMAZONAWS
6. Route IPv4 addresses in IPSET lists x3mRouting_NETFLIX and x3mRouting_AMAZONAWS to the WAN interface

#### Installation

    /usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/Xentrk/netflix-vpn-bypass/master/IPSET_Netflix.sh" -o /jffs/scripts/IPSET_Netflix.sh

If the script runs successfully, you can have the script execute at system start-up by calling it from **/jffs/scripts/nat-start** by including the line ```sh /jffs/scripts/IPSET_Netflix.sh``` in the file.  Make sure **nat-start** has a she-bang as the first line in the file ```#!/bin/sh``` and is executable e.g. ```chmod 755 /jffs/scripts/nat-start```.  

### IPSET_Netflix_Domains.sh
**IPSET_Netflix_Domains.sh** uses the feature of ipset in dnsmasq to dynamically generate the IPv4 address used by Netflix and Amazon AWS dynamically.  The script will create a cron job that will backup the IPSET list at 2:00 am.  The backup will be used to restore the IPSET list upon system startup.  

This approach can be useful when your ISP is using the [Netflix Open Connect Network](https://media.netflix.com/en/company-blog/how-netflix-works-with-isps-around-the-globe-to-deliver-a-great-viewing-experience).  The domain names used may vary by region. As a result, you will have to do some analysis to determine the domain names Netflix is using if the domains included in the script do not work for you. Below are the list of domain names used included in the script. 

    ipset=/amazonaws.com/netflix.com/nflxext.com/nflximg.net/nflxso.net/nflxvideo.net/x3mRouting_NETFLIX_DNSMASQ

The **x3mRouting_NETFLIX_DNSMASQ** entry is the name of the IPSET list. The script will place the line in **/jffs/configs/dnsmasq.conf.add** if it does not exist.

To determine the domain names, follow the install instructions to download the script **getdomainnames.sh** to **/jffs/scripts/getdomainnames.sh**. Navigate to the dnsmasq log file directory. My dnsmasq.log file location is **/opt/var/log**.   

Turn off the OpenVPN Client so all of your network traffic will traverse thru the WAN. Navigate to the dnsmasq log file directory **/opt/var/log**. Type the command to start capturing domains used by Netflix:

    tail -f dnsmasq.log > Netflix

Now, go to the device you are watching Netflix from. If you are streaming from your PC or laptop, close out other applications to minimize collecting domain names for non-Netflix traffic. Navigate around the Netflix menu options and watch several videos for a few minutes each to generate traffic and log entries to dnsmasq.log.  

When done generating Netflix traffic, press **ctrl-C** to stop logging to the **/opt/var/log/Netflix** file.  Run the **getdomainnames.sh** script, passing the **file name** and **IP address** of the device you were watching Netflix from. For example:

    . /jffs/scripts/getdomainnames.sh Netflix 192.168.1.20

This will create a file called **Netflix_domains** in the **/opt/var/log** directory.  Open the file in an editor to view the domains names collected when watching Netflix. The next step is to desk check the file for domains not related to Netflix.  These are domains generated by other applications on the LAN client you streamed Netflix from. Once you have narrowed down the domains, the next step is to update the **ipset=** references in the **IPSET_Netflix_Domains.sh** script using the domain names you captured. However, do not use the fully qualified domain name. For example, the domain **occ-0-1077-1062.1.nflxso.net** would be entered as **nflxso.net**; Likewise, www.netflix.com would be entered as **netflix.com**. **IPSET_Netflix_Domains.sh** will copy the **ipset=/** line to **/jffs/configs/dnsmasq.conf.add**

The ```nslookup <domain_name>``` command is useful in looking up IPv4 addresses associated with a domain.  Once you have the IPv4 address, you can use the ```whob <IPv4 address>``` command to display more information about the domain to confirm if it is associated with Netflix, Amazon AWS or a CDN provider, such as Akamai.  **whob** is an entware package.  Install using the command ```opkg install whob```   

    # nslookup occ-0-1077-1062.1.nflxso.net

    Server:    127.0.0.1
    Address 1: 127.0.0.1 localhost.localdomain

    Name:      occ-0-1077-1062.1.nflxso.net
    Address 1: 2a00:86c0:600:96::138 ipv6_1.lagg0.c009.lax004.ix.nflxvideo.net
    Address 3: 198.38.96.132 ipv4_1.lagg0.c003.lax004.ix.nflxvideo.net

    # whob 198.38.96.147

    IP: 198.38.96.147
    Origin-AS: 2906
    Prefix: 198.38.96.0/24
    AS-Path: 18106 4657 6762 2906
    AS-Org-Name: Netflix Streaming Services Inc.
    Org-Name: Netflix Streaming Services Inc.
    Net-Name: SSI-CDN-2
    Cache-Date: 1536245423
    Latitude: 39.738008
    Longitude: -75.550353
    City: Wilmington
    Region: Delaware
    Country: United States
    Country-Code: US

#### Installation
    /usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/Xentrk/netflix-vpn-bypass/master/getdomainnames.sh" -o /jffs/scripts/getdomainnames.sh && chmod 755 /jffs/scripts/getdomainnames.sh

    /usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/Xentrk/netflix-vpn-bypass/master/IPSET_Netflix_Domains.sh" -o /jffs/scripts/IPSET_Netflix_Domains.sh && chmod 755 /jffs/scripts/IPSET_Netflix_Domains.sh

### Troubleshooting
```ipset -L x3mRouting_NETFLIX``` command will list the contents of the IPSET list x3mRouting_NETFLIX

```iptables -nvL PREROUTING -t mangle --line``` will display the PREROUTING Chain statistics or packet information.  This command is very helpful to validate if traffic is traversing the chain.

```ip rule``` will display the rules and priorities for the LAN clients and the fwmark/bitmask created for the WAN and OpenVPN interfaces.

```service restart_dnsmasq``` will restart dnsmasq. Run this command to restart dnsmasq after making changes to **/jffs/configs/dnsmasq.conf.add**.

### Support
Support for the project is available on [snbforums.com](https://www.snbforums.com/threads/selective-routing-for-netflix.42661/)
