#!/usr/bin/env bash

set -u

requested=${1:-status}
interface=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $5 }')

emit_error() {
    jq -cn \
        --arg provider "" \
        --arg interface "${interface:-}" \
        --arg connection "" \
        --arg servers "" \
        --arg ipv4_servers "" \
        --arg ipv6_servers "" \
        --arg error "$1" \
        '{provider:$provider, interface:$interface, connection:$connection, servers:$servers, ipv4Servers:$ipv4_servers, ipv6Servers:$ipv6_servers, error:$error}'
}

if [[ -z $interface ]]; then
    emit_error 'No active default connection'
    exit 1
fi

uuid=$(nmcli -g GENERAL.CON-UUID device show "$interface" 2>/dev/null | head -n 1)
connection=$(nmcli -g GENERAL.CONNECTION device show "$interface" 2>/dev/null | head -n 1)

if [[ -z $uuid || $uuid == -- ]]; then
    emit_error 'Active connection is not managed by NetworkManager'
    exit 1
fi

apply_provider() {
    local provider=$1
    local ipv4_dns=$2
    local ipv6_dns=$3

    if [[ $provider == 'ISP Default' ]]; then
        nmcli connection modify uuid "$uuid" \
            ipv4.ignore-auto-dns no ipv4.dns '' \
            ipv6.ignore-auto-dns no ipv6.dns ''
    elif ip -6 route show default dev "$interface" 2>/dev/null | grep -q .; then
        nmcli connection modify uuid "$uuid" \
            ipv4.ignore-auto-dns yes ipv4.dns "$ipv4_dns" \
            ipv6.ignore-auto-dns yes ipv6.dns "$ipv6_dns"
    else
        nmcli connection modify uuid "$uuid" \
            ipv4.ignore-auto-dns yes ipv4.dns "$ipv4_dns" \
            ipv6.ignore-auto-dns no ipv6.dns ''
    fi

    nmcli device reapply "$interface"
}

if [[ $requested != status ]]; then
    case $requested in
        'ISP Default')
            dns4=''
            dns6=''
            ;;
        Cloudflare)
            dns4='1.1.1.1,1.0.0.1'
            dns6='2606:4700:4700::1111,2606:4700:4700::1001'
            ;;
        Google)
            dns4='8.8.8.8,8.8.4.4'
            dns6='2001:4860:4860::8888,2001:4860:4860::8844'
            ;;
        Quad9)
            dns4='9.9.9.9,149.112.112.112'
            dns6='2620:fe::fe,2620:fe::9'
            ;;
        OpenDNS)
            dns4='208.67.222.222,208.67.220.220'
            dns6='2620:119:35::35,2620:119:53::53'
            ;;
        *)
            emit_error "Unknown DNS provider: $requested"
            exit 2
            ;;
    esac

    if ! apply_provider "$requested" "$dns4" "$dns6" >/dev/null 2>&1; then
        emit_error 'Could not update the active connection'
        exit 1
    fi
fi

ignore4=$(nmcli --escape no -g ipv4.ignore-auto-dns connection show uuid "$uuid" 2>/dev/null | head -n 1)
dns4=$(nmcli --escape no -g ipv4.dns connection show uuid "$uuid" 2>/dev/null | paste -sd, -)
dns6=$(nmcli --escape no -g ipv6.dns connection show uuid "$uuid" 2>/dev/null | paste -sd, -)
servers=${dns4}${dns4:+${dns6:+,}}${dns6}

if [[ $ignore4 != yes || -z $dns4 ]]; then
    provider='ISP Default'
    dns4=$(nmcli --escape no -g IP4.DNS device show "$interface" 2>/dev/null | sed 's/ | /,/g; /^$/d' | paste -sd, -)
    dns6=$(nmcli --escape no -g IP6.DNS device show "$interface" 2>/dev/null | sed 's/ | /,/g; /^$/d' | paste -sd, -)
    servers=${dns4}${dns4:+${dns6:+,}}${dns6}
elif [[ $dns4 == *1.1.1.1* && $dns4 == *1.0.0.1* ]]; then
    provider='Cloudflare'
elif [[ $dns4 == *8.8.8.8* && $dns4 == *8.8.4.4* ]]; then
    provider='Google'
elif [[ $dns4 == *9.9.9.9* && $dns4 == *149.112.112.112* ]]; then
    provider='Quad9'
elif [[ $dns4 == *208.67.222.222* && $dns4 == *208.67.220.220* ]]; then
    provider='OpenDNS'
else
    provider='Custom'
fi

jq -cn \
    --arg provider "$provider" \
    --arg interface "$interface" \
    --arg connection "$connection" \
    --arg servers "$servers" \
    --arg ipv4_servers "$dns4" \
    --arg ipv6_servers "$dns6" \
    '{provider:$provider, interface:$interface, connection:$connection, servers:$servers, ipv4Servers:$ipv4_servers, ipv6Servers:$ipv6_servers, error:""}'
