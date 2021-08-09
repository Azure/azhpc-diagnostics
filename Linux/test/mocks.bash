#!/bin/bash
# mocks of 3rd party tools

NVIDIA_SMI_QUERY_GPU_DATA=$(mktemp)
cp "$BATS_TEST_DIRNAME/mock_data/nvidia-smi-query-gpu.csv" "$NVIDIA_SMI_QUERY_GPU_DATA"

function nvidia-smi {
    if ! PARSED_OPTIONS=$(getopt -n "$0" -o i: --long 'query-gpu:,query-remapped-rows:,format:' -- "$@"); then
        echo "Invalid combination of input arguments. Please run 'nvidia-smi -h' for help."
        return 1
    fi
    eval set -- "$PARSED_OPTIONS"
    local query i format data_file
    while [ "$1" != "--" ]; do
        case "$1" in
            --query-*)
                if [ -n "$query" ]; then
                    echo 'Only one --query-* switch can be used at a time.'
                    return 1
                fi
                shift
                query="$1"
                data_file="$NVIDIA_SMI_QUERY_GPU_DATA"
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

    local header header_to_colnum requested_fields
    declare -a header
    declare -A header_to_colnum
    declare -a requested_fields

    IFS=',' read -r -a header <<< "$(head -1 "$data_file")"

    local colnum=0
    for column in "${header[@]}"; do
        header_to_colnum[$column]=$((colnum++))
    done

    IFS=',' read -r -a requested_fields <<< "$query"

    tail -n +2 "$data_file" |
    (if [ -z "$i" ]; then cat; else awk -F, "\$$((header_to_colnum[index] + 1))==$i" ; fi) |
    while IFS=',' read -r -a data; do
        for field in "${requested_fields[@]}"; do
            echo -n "${data[${header_to_colnum[$field]}]}, "
        done
        echo ""
    done | sed 's/, $//g'
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
MOCK_LNKCAP=( "\tLnkCap: Port #1, Speed 16GT/s, Width x16" "\tLnkCap: Port #2, Speed 16GT/s, Width x16" "\tLnkCap: Port #3, Speed 16GT/s, Width x16" "\tLnkCap: Port #4, Speed 16GT/s, Width x16" "\tLnkCap: Port #5, Speed 8GT/s, Width x16" )
MOCK_LNKSTA=( "\tLnkSta: Port #1, Speed 16GT/s, Width x16" "\tLnkSta: Port #2, Speed 16GT/s, Width x16" "\tLnkSta: Port #3, Speed 16GT/s, Width x16" "\tLnkSta: Port #4, Speed 16GT/s, Width x16" "\tLnkSta: Port #5, Speed 8GT/s, Width x16" )
function lspci {
    if ! PARSED_OPTIONS=$(getopt -n "$0" -o d:mns:vD -- "$@"); then
        return 1
    fi
    eval set -- "$PARSED_OPTIONS"
    local vendor='[0-9a-f]{4}' # default to wildcard
    local bus_id='[0-9a-f]{4}:[0-9a-f]{2}:[01][0-9a-f].[0-7]' # default to wildcard
    local verbosity=0

    while [ "$1" != "--" ]; do
        case "$1" in
            -d) shift; vendor="${1%:}";;
            # -m) machine_readable=true;;
            -s) shift; bus_id="$1";;
            -v) (( verbosity++ ));;
            # -D) show_domain=true;;
        esac
        shift
    done
    for i in "${!MOCK_PCI_DEVICES[@]}"; do
        local device=${MOCK_PCI_DEVICES[$i]}
        local link_capacity=${MOCK_LNKCAP[$i]}
        local link_status=${MOCK_LNKSTA[$i]}
        if [[ "$device" =~ ^${bus_id}\ \"[0-9a-f]{4}\"\ \"${vendor}\" ]]; then
            echo "$device"
            if (( verbosity >= 2 )); then
                echo -e "$link_capacity"
                echo -e "$link_status"
            fi
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
