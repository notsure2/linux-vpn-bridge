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
    iptables -t mangle -A $TPROXY_CHAIN -m mark --mark $TPROXY_MARK -j RETURN
    [ ! -z "$tcp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p tcp -m conntrack \
        --ctstate NEW,RELATED,ESTABLISHED -j MARK --set-mark $TPROXY_MARK
    [ ! -z "$udp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p udp -m conntrack \
        --ctstate NEW,RELATED,ESTABLISHED -j MARK --set-mark $TPROXY_MARK

    ip route add local default dev lo table $tproxy_route_table_id
    ip rule add fwmark $TPROXY_MARK table $tproxy_route_table_id prio 8
fi

for route_over_vpn_network in $route_over_vpn_networks; do
    ip rule add to $route_over_vpn_network priority 9 lookup main
    ip rule add from $route_over_vpn_network priority 10 lookup $route_table_id
    iptables -I FORWARD 1 -s $route_over_vpn_network -j ACCEPT

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

    iptables -t mangle -A OUTPUT -m owner --gid-owner $route_over_vpn_group -m conntrack \
        --ctstate NEW,RELATED,ESTABLISHED -m mark --mark 0 -j MARK --set-mark $fwmark
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
iptables -t nat -A OUTPUT -m mark --mark $fwmark -d 8.8.8.8 -j DNAT --to 127.0.2.1
iptables -t nat -A OUTPUT -m mark --mark $fwmark -d 8.8.4.4 -j DNAT --to 127.0.2.2
iptables -t nat -A POSTROUTING -o lo -d 127.0.2.1 -j SNAT --to-source=127.0.0.1
echo 1 > /proc/sys/net/ipv4/conf/all/route_localnet
ip rule add from all fwmark $fwmark lookup $route_table_id prio 11

ip route flush cache
