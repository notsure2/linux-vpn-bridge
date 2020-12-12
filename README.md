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

Suggestions and bug reports welcome!
