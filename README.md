### General purpose VPN and proxy bridge

This is a series of scripts that bridge a server VPN or proxy (eg: shadowsocks) to 
another VPN connection (eg: your private VPS to a commercial VPN provider). This is 
useful because most VPS providers will block or kick you if you use your VPS VPN for P2P.

1. Clone repo to `/etc/vpn-bridge`
2. Copy bridge.env.example to bridge.env
3. Choose a unique fwmark value.
4. Choose a unique routing table id.
5. Set the CIDRs of the networks of your VPN server (space separated).
6. Set the names of Linux system groups where proxy apps running as that group 
   will have its outgoing traffic tunneled over the VPN bridge.
7. Setup the OpenVPN client configuration (of the bridge).
8. Edit the OpenVPN client configuration to include `/etc/vpn-bridge/bridge-openvpn.conf`.
   (Use the `config` OpenVPN directive).
9. Start the VPN bridge.

For bridging to other kinds of VPNs, just arrange that the VPN bridge calls 
`ENV=custom-env-file.env /etc/vpn-bridge/scripts/route-up.sh tunX` where tunX is the name 
of the created tun interface after it connects, and also arrange that it calls
`ENV=custom-env-file.env /etc/vpn-bridge/scripts/route-pre-down.sh tunX` before or after
it disconnects. If the `ENV` variable is not specified, the scripts will use 
`/etc/vpn-bridge/bridge.env` by default.

**NOTE**: The following commands are required in /etc/rc.local (and don't forget to chmod +x):
```sh
#!/bin/sh
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 1 > /proc/sys/net/ipv4/conf/all/route_localnet
```

The following commands are additionally recommended for good performance:
```sh
#!/bin/sh
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route
echo 0 > /proc/sys/net/ipv4/tcp_syncookies
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/log_martians
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control
echo fq_codel > /proc/sys/net/core/default_qdisc
echo 16384 > /proc/sys/net/ipv4/tcp_notsent_lowat
```

New feature added: Ability to also use TPROXY for TCP and UDP in the bridge. This can be useful
if you want to bridge these protocols over a faster protocol that needs less CPU (eg: shadowsocks)
than the main bridge's VPN connection (probably OpenVPN) especially if on a small VPS with a weak CPU.

Just setup the tunnel app (eg: ss-redir) to use TPROXY for TCP and UDP, then edit the bridge.env file
file and set the following variables. You can omit UDP or TCP proxy port to tunnel only one of them.
The rest of the traffic will go over the main bridge VPN.

```sh
# Needs to be a unique number less than 252
tproxy_route_table_id="201"
tcp_tproxy_port="48000"
udp_tproxy_port="48000"
```

Suggestions and bug reports welcome!
