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

    TPROXY_EXCLUDE_IPSET=tproxy_exclude_$TPROXY_MARK
    ipset create $TPROXY_EXCLUDE_IPSET nethash;
    for tproxy_exclude_destination in $tproxy_exclude; do
        ipset add $TPROXY_EXCLUDE_IPSET $tproxy_exclude_destination;
    done;

    [ ! -z "$tcp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p tcp \
        --syn -m conntrack --ctstate NEW -m set ! --match-set $TPROXY_EXCLUDE_IPSET dst -j CONNMARK --set-mark $TPROXY_MARK;
    [ ! -z "$udp_tproxy_port" ] && iptables -t mangle -A $TPROXY_CHAIN -p udp -m conntrack \
        --ctstate NEW ! --dport 33434:33474 -m set ! --match-set $TPROXY_EXCLUDE_IPSET dst -j CONNMARK --set-mark $TPROXY_MARK;
    iptables -t mangle -A $TPROXY_CHAIN -m connmark --mark $TPROXY_MARK -j MARK --set-mark $TPROXY_MARK;

    ip route add local default dev lo table $tproxy_route_table_id;
    ip rule add fwmark $TPROXY_MARK table $tproxy_route_table_id prio 8;
fi

for route_over_vpn_network in $route_over_vpn_networks; do
    iptables -t mangle -A PREROUTING -s $route_over_vpn_network \
        -m addrtype ! --dst-type LOCAL -m conntrack --ctstate NEW -j CONNMARK --set-mark $fwmark
    iptables -I FORWARD 1 -s $route_over_vpn_network -j ACCEPT
    iptables -I FORWARD 2 -d $route_over_vpn_network -j ACCEPT

    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -A PREROUTING \
        -s $route_over_vpn_network -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN
done

ip route add default dev $dev table $route_table_id
ip route show table main | grep -Ev '^default' | grep -Ev '/1' | grep -Ev '/2' \
    | while read ROUTE ; do
        ip route add table $route_table_id $ROUTE
      done;

# Must be inserted as the first rule
iptables -t filter -I OUTPUT -o $dev -j ACCEPT
iptables -t nat -I POSTROUTING -o $dev -j MASQUERADE

for route_over_vpn_group in $route_over_vpn_groups; do
    [ ! -z "$TPROXY_MARK" ] && iptables -t mangle -A OUTPUT -m owner \
        --gid-owner $route_over_vpn_group -m addrtype ! --dst-type LOCAL -j $TPROXY_CHAIN

    iptables -t mangle -A OUTPUT -m owner --gid-owner $route_over_vpn_group -m connmark \
        --mark 0 -m conntrack --ctstate NEW -j CONNMARK --set-mark $fwmark;
    iptables -t mangle -A OUTPUT -m connmark --mark $fwmark -j MARK --set-mark $fwmark;
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

iptables -t mangle -A POSTROUTING -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu;
