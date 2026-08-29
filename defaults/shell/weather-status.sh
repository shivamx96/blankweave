#!/usr/bin/env bash

set -u
umask 077

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
cache_home=${XDG_CACHE_HOME:-"$HOME/.cache"}
config_dir="$config_home/blankweave"
cache_dir="$cache_home/blankweave"
config_file="$config_dir/weather.json"
cache_file="$cache_dir/weather.json"
forecast_url='https://api.open-meteo.com/v1/forecast'
geocoding_url='https://geocoding-api.open-meteo.com/v1/search'

json_message() {
    local configured=$1
    local message=$2
    jq -cn \
        --argjson configured "$configured" \
        --arg message "$message" \
        '{configured:$configured, available:false, stale:false, error:$message}'
}

dependencies_ready() {
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

read_location() {
    [ -r "$config_file" ] || return 1
    jq -e '
        (.latitude | type == "number")
        and (.longitude | type == "number")
        and (.name | type == "string" and length > 0)
    ' "$config_file" >/dev/null 2>&1
}

status() {
    if ! dependencies_ready; then
        json_message false 'Weather requires curl and jq'
        return
    fi

    if ! read_location; then
        json_message false ''
        return
    fi

    local latitude longitude location response staged now
    latitude=$(jq -r '.latitude' "$config_file")
    longitude=$(jq -r '.longitude' "$config_file")
    location=$(jq -r '[.name, (.admin1 // "")] | map(select(length > 0)) | unique | join(", ")' "$config_file")
    mkdir -p "$cache_dir"
    response=$(mktemp "$cache_dir/.weather-response.XXXXXX")
    staged=$(mktemp "$cache_dir/.weather-cache.XXXXXX")

    if curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 4 \
        --max-time 12 \
        --get "$forecast_url" \
        --data-urlencode "latitude=$latitude" \
        --data-urlencode "longitude=$longitude" \
        --data-urlencode 'current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,precipitation,weather_code,cloud_cover,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m' \
        --data-urlencode 'hourly=temperature_2m,apparent_temperature,precipitation_probability,weather_code,is_day' \
        --data-urlencode 'daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_speed_10m_max' \
        --data-urlencode 'timezone=auto' \
        --data-urlencode 'forecast_hours=8' \
        --data-urlencode 'forecast_days=7' \
        > "$response" 2>/dev/null \
        && jq -e '.current and .hourly and .daily and ((.error // false) == false)' "$response" >/dev/null 2>&1; then
        now=$(date +%s)
        jq -c \
            --arg location "$location" \
            --argjson fetchedAt "$now" \
            '. + {
                configured:true,
                available:true,
                stale:false,
                error:"",
                location:$location,
                fetchedAt:$fetchedAt
            }' "$response" > "$staged"
        mv -f "$staged" "$cache_file"
        cat "$cache_file"
    elif [ -r "$cache_file" ] && jq -e '.available == true' "$cache_file" >/dev/null 2>&1; then
        jq -c '.stale = true | .error = "Using the last downloaded forecast"' "$cache_file"
    else
        json_message true 'Forecast is temporarily unavailable'
    fi

    rm -f "$response" "$staged"
}

search_location() {
    local query=${1:-}
    if ! dependencies_ready; then
        jq -cn '{results:[], error:"Weather requires curl and jq"}'
        return
    fi
    if [ -z "${query//[[:space:]]/}" ]; then
        jq -cn '{results:[], error:"Enter a city or postcode"}'
        return
    fi

    local response
    response=$(mktemp)
    if curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 4 \
        --max-time 10 \
        --get "$geocoding_url" \
        --data-urlencode "name=$query" \
        --data-urlencode 'count=5' \
        --data-urlencode 'language=en' \
        --data-urlencode 'format=json' \
        > "$response" 2>/dev/null; then
        jq -c '{
            results: [(.results // [])[] | {
                id:(.id // 0),
                name:(.name // ""),
                latitude:.latitude,
                longitude:.longitude,
                admin1:(.admin1 // ""),
                country:(.country // ""),
                timezone:(.timezone // "")
            }],
            error:""
        }' "$response" 2>/dev/null \
            || jq -cn '{results:[], error:"Could not read location results"}'
    else
        jq -cn '{results:[], error:"Location search is temporarily unavailable"}'
    fi
    rm -f "$response"
}

save_location() {
    local latitude=${1:-}
    local longitude=${2:-}
    local name=${3:-}
    local admin1=${4:-}
    local country=${5:-}
    local numeric_latitude numeric_longitude staged

    if ! dependencies_ready; then
        jq -cn '{saved:false, error:"Weather requires curl and jq"}'
        return
    fi
    if [ -z "$name" ]; then
        jq -cn '{saved:false, error:"Location name is missing"}'
        return
    fi
    if ! numeric_latitude=$(jq -en --arg value "$latitude" '$value | tonumber') \
        || ! numeric_longitude=$(jq -en --arg value "$longitude" '$value | tonumber'); then
        jq -cn '{saved:false, error:"Location coordinates are invalid"}'
        return
    fi

    mkdir -p "$config_dir"
    staged=$(mktemp "$config_dir/.weather.XXXXXX")
    jq -cn \
        --argjson latitude "$numeric_latitude" \
        --argjson longitude "$numeric_longitude" \
        --arg name "$name" \
        --arg admin1 "$admin1" \
        --arg country "$country" \
        '{latitude:$latitude, longitude:$longitude, name:$name, admin1:$admin1, country:$country}' \
        > "$staged"
    mv -f "$staged" "$config_file"
    rm -f "$cache_file"
    jq -cn '{saved:true, error:""}'
}

case "${1:-status}" in
    status)
        status
        ;;
    search)
        search_location "${2:-}"
        ;;
    save)
        save_location "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        ;;
    *)
        jq -cn '{available:false, configured:false, error:"Unknown weather action"}'
        ;;
esac
