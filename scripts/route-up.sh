#!/bin/bash
DIR=$(dirname "$0")
ENV=${ENV:-$DIR/../bridge.env}
[ ! -f "$ENV" ] && echo "Bridge config file $ENV not found. Aborting." && exit 1;
. $ENV
dev=${dev:=$1}
[ -z "$dev" ] && echo "vpn interface dev not specified. Aborting." && exit 1;

for route_over_vpn_network in $route_over_vpn_networks; do
    ip rule add to $route_over_vpn_network priority 9 lookup main
    ip rule add from $route_over_vpn_network priority 10 lookup $route_table_id
done
ip route add default dev $dev table $route_table_id

# Must be inserted as the first rule
iptables -t filter -I OUTPUT -o $dev -j ACCEPT
iptables -t nat -I POSTROUTING -o $dev -j MASQUERADE

for route_over_vpn_group in $route_over_vpn_groups; do
    iptables -t mangle -A OUTPUT -m owner --gid-owner $route_over_vpn_group -m conntrack --ctstate NEW,RELATED,ESTABLISHED -j MARK --set-mark $fwmark
done

iptables -t filter -I OUTPUT -m mark --mark $fwmark -j ACCEPT
iptables -t nat -A OUTPUT -m mark --mark $fwmark -d 8.8.8.8 -j DNAT --to 127.0.2.1
iptables -t nat -A OUTPUT -m mark --mark $fwmark -d 8.8.4.4 -j DNAT --to 127.0.2.2
iptables -t nat -A POSTROUTING -o lo -d 127.0.2.1 -j SNAT --to-source=127.0.0.1
echo 1 > /proc/sys/net/ipv4/conf/all/route_localnet
ip rule add from all fwmark $fwmark lookup $route_table_id prio 11

ip route flush cache
