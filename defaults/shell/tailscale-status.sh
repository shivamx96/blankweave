#!/usr/bin/env bash

set -u

if ! command -v tailscale >/dev/null 2>&1; then
    printf '%s\n' '{"available":false,"daemonRunning":false,"connected":false,"backend":"Unavailable","error":"Tailscale is not installed","peers":[]}'
    exit 0
fi

if ! status_json=$(tailscale status --json 2>/dev/null); then
    if pgrep -x tailscaled >/dev/null 2>&1; then
        daemon_running=true
    else
        daemon_running=false
    fi
    printf '{"available":true,"daemonRunning":%s,"connected":false,"backend":"Stopped","error":"Could not reach tailscaled","peers":[]}\n' "$daemon_running"
    exit 0
fi

printf '%s' "$status_json" | jq -c '
    def ipv4: map(select(contains(":") | not)) | first // "";
    def ipv6: map(select(contains(":"))) | first // "";
    def clean_dns: rtrimstr(".");

    . as $status
    | [
        (.Peer // {} | to_entries[] | .value) |
        {
            id: (.ID // .PublicKey // ""),
            hostname: (.HostName // "Unknown device"),
            dnsName: ((.DNSName // "") | clean_dns),
            os: (.OS // "unknown"),
            online: (.Online // false),
            active: (.Active // false),
            exitNode: (.ExitNode // false),
            exitNodeOption: (.ExitNodeOption // false),
            ipv4: ((.TailscaleIPs // []) | ipv4),
            ipv6: ((.TailscaleIPs // []) | ipv6),
            relay: (.Relay // ""),
            lastSeen: (.LastSeen // "")
        }
    ]
    | sort_by([if .online then 0 else 1 end, (.hostname | ascii_downcase)]) as $peers
    | {
        available: true,
        daemonRunning: true,
        connected: ($status.BackendState == "Running"),
        backend: ($status.BackendState // "Unknown"),
        needsLogin: ($status.BackendState == "NeedsLogin"),
        authUrl: ($status.AuthURL // ""),
        version: ($status.Version // ""),
        hostname: ($status.Self.HostName // ""),
        dnsName: (($status.Self.DNSName // "") | clean_dns),
        tailnet: ($status.CurrentTailnet.Name // ""),
        magicDnsSuffix: ($status.MagicDNSSuffix // ""),
        ipv4: (($status.TailscaleIPs // $status.Self.TailscaleIPs // []) | ipv4),
        ipv6: (($status.TailscaleIPs // $status.Self.TailscaleIPs // []) | ipv6),
        relay: ($status.Self.Relay // ""),
        exitNode: ($peers | map(select(.exitNode)) | first | .hostname // ""),
        peerCount: ($peers | length),
        onlinePeerCount: ($peers | map(select(.online)) | length),
        peers: ($peers | .[:8]),
        hiddenPeerCount: ([$peers | .[8:][]] | length),
        health: ($status.Health // []),
        error: ""
    }
'
