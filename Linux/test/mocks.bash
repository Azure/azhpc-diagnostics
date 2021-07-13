#!/bin/bash
# mocks of 3rd party tools

declare -a MOCK_GPU_SBE_DBE_COUNTS
MOCK_GPU_SBE_DBE_COUNTS=( "0, 0" "0, 0" "0, 0" "0, 0" )

declare -a MOCK_GPU_PCI_DOMAINS
MOCK_GPU_PCI_DOMAINS=( 0x0001 0x0002 0x000A 0x000D )

declare -a MOCK_GPU_PCI_SERIALS
MOCK_GPU_PCI_SERIALS=( 0000000000001 0000000000002 0000000000003 0000000000004 )

function nvidia-smi {
    if ! PARSED_OPTIONS=$(getopt -n "$0" -o i: --long 'query-gpu:,format:' -- "$@"); then
        echo "Invalid combination of input arguments. Please run 'nvidia-smi -h' for help."
        return 1
    fi
    eval set -- "$PARSED_OPTIONS"
    local query i format
    while [ "$1" != "--" ]; do
        case "$1" in
            --query-gpu)
                shift
                query="$1"
            ;;
            -i)
                shift
                i="$1"
            ;;
            --format)
                shift
                format="$1"
            ;;
        esac
        shift
    done
    if [ "$format" != "csv,noheader" ]; then
        echo '"--format=" switch is missing. Please run 'nvidia-smi -h' for help.'
        return 1
    fi
    local data
    declare -a data
    case "$query" in
        retired_pages.sbe,retired_pages.dbe) data=("${MOCK_GPU_SBE_DBE_COUNTS[@]}");;
        pci.domain) data=("${MOCK_GPU_PCI_DOMAINS[@]}");;
        serial) data=("${MOCK_GPU_PCI_SERIALS[@]}");;
        
        *) echo "Field \"$query\" is not a valid field to query."; return 1;;
    esac
    if [ -z "$i" ]; then
        for line in "${data[@]}"; do echo "$line"; done
    else
        echo "${data[$i]}"
    fi
    return 0
}

function journalctl {
    cat "$BATS_TEST_DIRNAME/samples/journald.log"
}

declare -a MOCK_PCI_DEVICES
MOCK_PCI_DEVICES=( 
    '0001:00:00.0 "0302" "10de" "1db5" -ra1 "10de" "1249"'
    '0002:00:00.0 "0302" "10de" "1db5" -ra1 "10de" "1249"'
    '000a:00:00.0 "0302" "10de" "1db5" -ra1 "10de" "1249"'
    '000d:00:00.0 "0302" "10de" "1db5" -ra1 "10de" "1249"'
    '1421:00:02.0 "0207" "15b3" "1018" "15b3" "0003"'
)
function lspci {
    if ! PARSED_OPTIONS=$(getopt -n "$0" -o d:mns:vD -- "$@"); then
        return 1
    fi
    eval set -- "$PARSED_OPTIONS"
    local vendor='[0-9a-f]{4}' # default to wildcard
    local bus_id='[0-9a-f]{4}:[0-9a-f]{2}:[01][0-9a-f].[0-7]' # default to wildcard

    while [ "$1" != "--" ]; do
        case "$1" in
            -d) shift; vendor="$1";;
            # -m) machine_readable=true;;
            # -D) show_domain=true;;
        esac
        shift
    done
    for i in "${!MOCK_PCI_DEVICES[@]}"; do
        local device=${MOCK_PCI_DEVICES[$i]}
        if [[ "$device" =~ ^${bus_id}\ \"[0-9a-f]{4}\"\ \"${vendor}\" ]]; then
            echo "$device"
        fi
    done
}

function lsvmbus {
    echo "Hyper-V VMBus information goes here"
}

function ibstat {
    echo "infiniband results"
}

function ibv_devinfo {
    if [ "$1" == "-v" ]; then
        echo "full output"
    else
        echo "less output"
    fi
}

function hide_command {
    local command="$1"
    local command_path command_dir tmpdir command_type
    while command_type=$(type -t "$command"); do
        case "$command_type" in
            alias) unalias "$command";;
            function) unset -f "$command";;
            file)
                command_path=$(command -v "$command")
                command_dir=$(dirname "$command_path")
                tmpdir=$(mktemp -d)
                cp -r "$command_dir"/* "$tmpdir"
                rm "$tmpdir/$command"

                PATH="$(echo "$PATH" | sed "s:\(^\|\:\)$command_dir\(\:\|$\):\1$tmpdir\2:g")"
                ;;
            *) echo "cannot remove command of type $command_type"; return 1;;
        esac
    done
}
