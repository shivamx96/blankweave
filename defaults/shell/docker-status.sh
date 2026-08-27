#!/usr/bin/env bash

set -uo pipefail

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' '{"available":false,"daemonRunning":false,"error":"Docker is not installed","containers":[]}'
    exit 0
fi

if ! info_json=$(docker info --format '{{json .}}' 2>/dev/null); then
    if pgrep -x dockerd >/dev/null 2>&1; then
        daemon_running=true
        error_message='Could not access Docker Engine'
    else
        daemon_running=false
        error_message='Docker Engine is stopped'
    fi
    jq -cn \
        --argjson daemonRunning "$daemon_running" \
        --arg error "$error_message" \
        '{available:true, daemonRunning:$daemonRunning, error:$error, containers:[]}'
    exit 0
fi

mapfile -t running_ids < <(docker ps -q 2>/dev/null)
if ((${#running_ids[@]} > 0)); then
    inspect_json=$(docker inspect "${running_ids[@]}" 2>/dev/null || printf '[]')
else
    inspect_json='[]'
fi

jq -cn \
    --argjson info "$info_json" \
    --argjson inspect "$inspect_json" '
    def endpoint($address; $port):
        if ($address == "" or $address == "0.0.0.0" or $address == "::") then "localhost:" + $port
        elif ($address | contains(":")) then "[" + $address + "]:" + $port
        else $address + ":" + $port
        end;

    [
        $inspect[]
        | . as $container
        | ([
            ($container.NetworkSettings.Ports // {} | to_entries[]) as $mapping
            | ($mapping.value // [])[]
            | {
                containerPort: $mapping.key,
                hostAddress: (.HostIp // ""),
                hostPort: (.HostPort // ""),
                endpoint: endpoint((.HostIp // ""); (.HostPort // ""))
            }
        ] | unique_by(.endpoint)) as $ports
        | {
            id: (($container.Id // "")[:12]),
            name: (($container.Name // "Unnamed container") | ltrimstr("/")),
            image: ($container.Config.Image // ""),
            project: ($container.Config.Labels["com.docker.compose.project"] // ""),
            service: ($container.Config.Labels["com.docker.compose.service"] // ""),
            state: ($container.State.Status // "unknown"),
            health: ($container.State.Health.Status // ""),
            startedAt: ($container.State.StartedAt // ""),
            ports: $ports,
            portsText: ($ports | map(.endpoint) | join(", ")),
            copyPorts: ($ports | map(.endpoint) | join("\n"))
        }
    ]
    | sort_by([(.project == ""), (.project | ascii_downcase), (.service | ascii_downcase), (.name | ascii_downcase)]) as $containers
    | {
        available: true,
        daemonRunning: true,
        error: "",
        name: ($info.Name // "Docker Engine"),
        version: ($info.ServerVersion // ""),
        storageDriver: ($info.Driver // ""),
        totalContainers: ($info.Containers // 0),
        runningContainers: ($info.ContainersRunning // ($containers | length)),
        pausedContainers: ($info.ContainersPaused // 0),
        stoppedContainers: ($info.ContainersStopped // 0),
        images: ($info.Images // 0),
        containers: $containers
    }
'
