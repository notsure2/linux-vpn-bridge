#!/bin/bash
DIR=$(dirname "$0")
ENV=${ENV:-$DIR/../bridge.env}
[ ! -f "$ENV" ] && echo "Bridge config file $ENV not found. Aborting." && exit 1;
. $ENV
dev=${dev:=$1}
[ -z "$dev" ] && echo "vpn interface dev not specified. Aborting." && exit 1;

TPROXY_MARK=${tcp_tproxy_port:=$udp_tproxy_port}
TPROXY_CHAIN=TPROXY_$TPROXY_MARK
[ ! -z "$TPROXY_MARK" -a -z "$tproxy_route_table_id" ] && \
    echo "tproxy tcp or udp port specified but not tproxy route table id. Aborting." && exit 1;

if [ ! -z "$TPROXY_MARK" ]; then
    iptables -t mangle -N $TPROXY_CHAIN
    iptables -t mangle -A $TPROXY_CHAIN -m mark ! --mark 0 -j RETURN
    iptables -t mangle -A $TPROXY_CHAIN -j CONNMARK --restore-mark
    iptables -t mangle -A $TPROXY_CHAIN -m mark ! --mark 0 -j RETURN
    for tproxy_exclude_destination in $tproxy_exclude; do
        iptables -t mangle -A $TPROXY_CHAIN -d $tproxy_exclude_destination -j RETURN
    done;
    [ ! -z "$tcp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p tcp \
        --syn -j MARK --set-mark $TPROXY_MARK
    [ ! -z "$udp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p udp -m conntrack \
        --ctstate NEW ! --dport 33434:33474 -j MARK --set-mark $TPROXY_MARK
    iptables -t mangle -A $TPROXY_CHAIN -j CONNMARK --save-mark

    ip route add local default dev lo table $tproxy_route_table_id
    ip rule add fwmark $TPROXY_MARK table $tproxy_route_table_id prio 8
fi

for route_over_vpn_network in $route_over_vpn_networks; do
    ip rule add to $route_over_vpn_network priority 9 lookup main
    ip rule add from $route_over_vpn_network priority 10 lookup $route_table_id
    iptables -I FORWARD 1 -s $route_over_vpn_network -j ACCEPT
    iptables -I FORWARD 2 -d $route_over_vpn_network -j ACCEPT

    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -A PREROUTING \
        -s $route_over_vpn_network -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN
done
ip route add default dev $dev table $route_table_id

# Must be inserted as the first rule
iptables -t filter -I OUTPUT -o $dev -j ACCEPT
iptables -t nat -I POSTROUTING -o $dev -j MASQUERADE

for route_over_vpn_group in $route_over_vpn_groups; do
    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -A OUTPUT -m owner \
        --gid-owner $route_over_vpn_group -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN

    VPN_GROUP_CHAIN=GID_$route_over_vpn_group
    iptables -t mangle -N $VPN_GROUP_CHAIN
    iptables -t mangle -A $VPN_GROUP_CHAIN -m mark ! --mark 0 -j RETURN
    iptables -t mangle -A $VPN_GROUP_CHAIN -j CONNMARK --restore-mark
    iptables -t mangle -A $VPN_GROUP_CHAIN -m mark ! --mark 0 -j RETURN
    iptables -t mangle -A $VPN_GROUP_CHAIN -m owner --gid-owner $route_over_vpn_group -m conntrack \
        --ctstate NEW -j MARK --set-mark $fwmark
    iptables -t mangle -A $VPN_GROUP_CHAIN -j CONNMARK --save-mark

    iptables -t mangle -A OUTPUT -m owner \
        --gid-owner $route_over_vpn_group -m addrtype ! --dst-type LOCAL -j $VPN_GROUP_CHAIN
done

if [ ! -z "$TPROXY_MARK" ]; then
    [ ! -z "$tcp_tproxy_port" ] && iptables -t mangle -A PREROUTING -p tcp -m mark \
        --mark $TPROXY_MARK -j TPROXY --on-ip 127.0.0.1 --on-port $tcp_tproxy_port \
        --tproxy-mark $TPROXY_MARK
    [ ! -z "$udp_tproxy_port" ] && iptables -t mangle -A PREROUTING -p udp -m mark \
        --mark $TPROXY_MARK -j TPROXY --on-ip 127.0.0.1 --on-port $udp_tproxy_port \
        --tproxy-mark $TPROXY_MARK
fi

iptables -t filter -I OUTPUT -m mark --mark $fwmark -j ACCEPT
ip rule add from all fwmark $fwmark lookup $route_table_id prio 11
eval "$custom_post_up"
ip route flush cache
