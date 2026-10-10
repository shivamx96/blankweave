#!/usr/bin/env bash
set -euo pipefail
state=${SETTINGS_DISPLAYS_STATE:?}
case "$1" in
    scenario)
        printf '%s' "$2" > "$state"
        ;;
    status)
        scenario=$(cat "$state" 2>/dev/null || printf initial)
        case "$scenario" in
            malformed) printf '{"monitors":[{}]}' ;;
            offline) exit 1 ;;
            empty) printf '{"monitors":[]}' ;;
            *)
                jq -cn --argjson presets "$(cat "$state.presets" 2>/dev/null || printf '[]')" --argjson preview "$(cat "$state.preview" 2>/dev/null || printf null)" --arg scenario "$scenario" '
                {name:"eDP-1",description:"Laptop",mirrorConnector:"",internal:true,width:2880,height:1800,x:0,y:0,position:"auto",
                    refreshRate:90,modeOptions:["2880x1800@60.00","2880x1800@90.00"],scale:1.5,effectiveScale:1.5,scaleOptions:[1,1.25,1.5,2]} as $internal |
                {name:"DP-3",description:"External",mirrorConnector:"",internal:false,width:3840,height:2160,x:1920,y:0,position:"auto",
                    scale:1.5,effectiveScale:1.5,scaleOptions:[1,1.25,1.5,2]} as $external |
                {presets:$presets,preview:$preview,monitors: (if $scenario == "reordered" then [$external,$internal]
                    elif $scenario == "mirrored" then [$internal,($external + {mirrorConnector:"eDP-1",x:0})]
                    elif $scenario == "mode60" then [($internal + {refreshRate:60}),$external]
                    elif $scenario == "unplugged" then [$internal]
                    elif $scenario == "auto" then [$internal,($external + {scale:"auto",effectiveScale:2})]
                    elif $scenario == "failed" then [$internal,($external + {scale:1.25})]
                    elif $scenario == "external" then [$internal,($external + {scale:2,effectiveScale:2})]
                    elif $scenario == "left" then [$internal,($external + {position:"left",x:-2560})]
                    elif $scenario == "position-failed" then [$internal,($external + {position:"below",x:-2560})]
                    elif $scenario == "reconnected" then [$internal,($external + {name:"DP-7",position:"left",x:-2560})]
                    elif $scenario == "desktop" then [($internal + {name:"HDMI-A-1",internal:false}),$external]
                    elif $scenario == "external-only" then [$external]
                    else [$internal,$external] end)}'
                ;;
        esac
        ;;
    preset-save)
        printf 'preset-save %s\n' "$2" >> "$state.commands"
        jq -cn --arg name "$2" '[{id:"desk",name:$name,available:true,reason:"",summary:"2 displays"}]' > "$state.presets"
        ;;
    preset-delete)
        printf 'preset-delete %s\n' "$2" >> "$state.commands"
        rm -f "$state.presets"
        ;;
    mirror-preview|preset-preview)
        printf '%s %s%s\n' "$1" "$2" "${3:+ $3}" >> "$state.commands"
        jq -n --argjson deadline "$(( $(date +%s) + 20 ))" \
            '{token:"test-token",kind:"layout",label:"Mirror or restore setup",connector:"",mode:"",deadline:$deadline}' > "$state.preview"
        printf mirrored > "$state"
        ;;
    mode-preview)
        printf 'mode-preview %s %s\n' "$2" "$3" >> "$state.commands"
        jq -n --arg connector "$2" --arg mode "$3" --argjson deadline "$(( $(date +%s) + 20 ))" \
            '{token:"test-token",connector:$connector,mode:$mode,deadline:$deadline}' > "$state.preview"
        if [[ $3 == *@60.00 ]]; then printf mode60 > "$state"; else printf initial > "$state"; fi
        ;;
    mode-confirm|mode-revert)
        printf '%s %s\n' "$1" "$2" >> "$state.commands"
        [[ $2 == test-token ]]
        rm -f "$state.preview"
        if [[ $1 == mode-revert ]]; then printf initial > "$state"; fi
        ;;
    set)
        printf 'set %s %s\n' "$2" "$3" >> "$state.commands"
        case "$3" in
            left) printf left > "$state" ;;
            below) printf position-failed > "$state"; exit 1 ;;
            auto) printf initial > "$state" ;;
            *) exit 2 ;;
        esac
        ;;
    set-scale)
        printf '%s %s\n' "$2" "$3" >> "$state.commands"
        # Leave time to exercise the busy guard while the operation is pending.
        sleep 0.1
        if [[ $3 == auto ]]; then
            printf auto > "$state"
        else
            printf failed > "$state"
            exit 1
        fi
        ;;
    *) exit 2 ;;
esac
