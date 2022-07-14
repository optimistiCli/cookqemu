#!/bin/bash

if [ -n "$1" ]; then
    MON_SOC="$1"
else
    SOCKETS="$(ls -1 /tmp/qemu_*_??????.socket 2>/dev/null)"
    if [ -z "$SOCKETS" ]; then
            echo 'No sockets'
            exit 1
    fi
    NUM=$(( $(echo -n "$SOCKETS" | wc -l) + 1 ))
    case "$NUM" in
        1)
            MON_SOC="$SOCKETS"
            ;;
        *)
            echo 'Too many sockets:'
            echo "$SOCKETS"
            exit 2
            ;;
    esac
fi

socat -,echo=0,icanon=0 unix-connect:${MON_SOC}
