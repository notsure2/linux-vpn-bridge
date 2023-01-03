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

eval "$custom_pre_down"
ip route del default dev $dev table $route_table_id

for route_over_vpn_network in $route_over_vpn_networks; do
    ip rule del from $route_over_vpn_network table $route_table_id
    ip rule del to $route_over_vpn_network lookup main
    iptables -D FORWARD -s $route_over_vpn_network -j ACCEPT
    iptables -D FORWARD -d $route_over_vpn_network -j ACCEPT

    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -D PREROUTING \
        -s $route_over_vpn_network -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN
done

iptables -t filter -D OUTPUT -o $dev -j ACCEPT
iptables -t nat -D POSTROUTING -o $dev -j MASQUERADE

for route_over_vpn_group in $route_over_vpn_groups; do
    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -D OUTPUT -m owner \
        --gid-owner $route_over_vpn_group -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN

    iptables -t mangle -D OUTPUT -m owner --gid-owner $route_over_vpn_group -m conntrack --ctstate NEW -j CONNMARK --set-mark $fwmark;
    iptables -t mangle -D OUTPUT -m connmark --mark $fwmark -j MARK --set-mark $fwmark;
done

iptables -t filter -D OUTPUT -m mark --mark $fwmark -j ACCEPT
ip rule del from all fwmark $fwmark lookup $route_table_id prio 11

if [ ! -z "$TPROXY_MARK" ]; then
    iptables -t mangle -F $TPROXY_CHAIN
    iptables -t mangle -X $TPROXY_CHAIN
    ip route del local default dev lo table $tproxy_route_table_id
    ip rule del fwmark $TPROXY_MARK table $tproxy_route_table_id prio 8

    [ ! -z "$tcp_tproxy_port" ] && iptables -t mangle -D PREROUTING -p tcp -m mark \
        --mark $TPROXY_MARK -j TPROXY --on-ip 127.0.0.1 --on-port $tcp_tproxy_port \
        --tproxy-mark $TPROXY_MARK
    [ ! -z "$udp_tproxy_port" ] && iptables -t mangle -D PREROUTING -p udp -m mark \
        --mark $TPROXY_MARK -j TPROXY --on-ip 127.0.0.1 --on-port $udp_tproxy_port \
        --tproxy-mark $TPROXY_MARK
fi

ip route flush cache
