#!/bin/bash
set -e

cidr2mask()
{
    local cidr=${1#*/}
    local full_octets=$(($cidr/8))
    local partial_octet=$(($cidr%8))

    local i=0
    while [ "$i" -lt 4 ]; do
        if [ $i -lt $full_octets ]; then
            echo -n 255
        elif [ $i -eq $full_octets ]; then
            echo -n $((256 - 2**(8-$partial_octet)))
        else
            echo -n 0
        fi
        [ $i -lt 3 ] && echo -n .
        i=`expr $i + 1`
    done
    echo
}

getroute() {
    echo ${1%/*} $(cidr2mask $1)
}

if [ -z "$OVPN_CLIENTS" ]; then
    echo "Client network not specified"
    exit 1
fi

cat > /run/openvpn-server.conf <<EOF
server $(getroute $OVPN_CLIENTS)

key ${OVPN_SERVER_KEY:-/etc/openvpn/server.key}
cert ${OVPN_SERVER_CERT:-/etc/openvpn/server.crt}
dh ${OVPN_SERVER_DH:-/etc/openvpn/dh.pem}
ca ${OVPN_CLIENT_CA:-/etc/openvpn/client-ca.crt}

dev tun
topology subnet
proto tcp
keepalive 10 120
cipher AES-256-CBC
auth sha512
comp-lzo
user nobody
group nogroup
ifconfig-pool-persist /var/openvpn-ipp.txt
persist-key
persist-tun
status /var/openvpn-status.log
verb 6
EOF

[ -n "$K8S_NODES" ] && echo "push \"route $(getroute $K8S_NODES)\"" >> /run/openvpn-server.conf
[ -n "$K8S_PODS" ] && echo "push \"route $(getroute $K8S_PODS)\"" >> /run/openvpn-server.conf
[ -n "$K8S_SERVICES" ] && echo "push \"route $(getroute $K8S_SERVICES)\"" >> /run/openvpn-server.conf

if [ -n "$K8S_DNS" ]
then
    echo "push \"dhcp-option DNS $K8S_DNS\"" >> /run/openvpn-server.conf
    echo "push \"dhcp-option DOMAIN cluster.local\"" >> /run/openvpn-server.conf
fi

iptables -t nat -A POSTROUTING -s $OVPN_CLIENTS -o eth0 -j MASQUERADE

mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

echo ========== Server configuration ==========
cat /run/openvpn-server.conf
echo ==========================================

exec openvpn --config /run/openvpn-server.conf
