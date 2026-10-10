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
                jq -cn --arg scenario "$scenario" '
                {name:"eDP-1",description:"Laptop",internal:true,width:2880,height:1800,x:0,y:0,position:"auto",
                    scale:1.5,effectiveScale:1.5,scaleOptions:[1,1.25,1.5,2]} as $internal |
                {name:"DP-3",description:"External",internal:false,width:3840,height:2160,x:1920,y:0,position:"auto",
                    scale:1.5,effectiveScale:1.5,scaleOptions:[1,1.25,1.5,2]} as $external |
                {monitors: (if $scenario == "reordered" then [$external,$internal]
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
