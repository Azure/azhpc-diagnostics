#!/bin/bash
# Azure HPC Diagnostics Tool
# Gathers Diagnostic info from guest VM
#
# tarball directory structure:
# - VM Information
#   - dmesg.log
#   - metadata.json
#   - waagent.log
#   - lspci.txt
#   - lsvmbus.log
#   - ipconfig.txt
#   - sysctl.txt
#   - uname.txt
#   - dmidecode.txt
#   - syslog
# - CPU
#   - lscpu.txt
# - Memory
#   - stream.txt
# - Infiniband
#   - ibstat.txt
#   - ibv_devinfo.txt
#   - pkey0.txt
#   - pkey1.txt
# - Nvidia GPU
#   - nvidia-smi.txt (human-readable)
#   - dump.zip (only Nvidia can read)
#   - dcgm-diag-2.log
#   - dcgm-diag-3.log
#   - nvvs.log
#   - stats_*.json
#
# Outputs:
# - name of tarball to stdout
# - tarball of all logs
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.



####################################################################################################
# Begin Constants
####################################################################################################

METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'
STREAM_URL='https://azhpcstor.blob.core.windows.net/diagtool-binaries/stream.tgz'
LSVMBUS_URL='https://raw.githubusercontent.com/torvalds/linux/master/tools/hv/lsvmbus'
SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
PKG_ROOT="$(dirname $SCRIPT_DIR)"

# Mapping for stream benchmark(AMD only)
declare -A CPU_LIST
CPU_LIST=(["HB120rs_v2"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69,73,77,81,85,89,93,97,101,105,109,113,117"
          ["HB60rs"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57")
VERSION_INFO="0.0.1"

HELP_MESSAGE="
Usage: $0 [OPTION]
Gather diagnostic info for the current Azure HPC VM.
Has multiple run levels
Exports data into a tarball in the script directory.

Output control:
 -d, --dir=DIR         specify custom output location

Miscellaneous:
 -V, --version         display version information and exit
 -h, --help            display this help text and exit

Execution Mode:
 --gpu-level=GPU_LEVEL dcgmi run level (default is 2)
 --mem-level=MEM_LEVEL set to 1 to run stream test (default is 0)

For more information on this script and the data it gathers, visit its Github:

https://github.com/Azure/azhpc-diagnostics
"

####################################################################################################
# End Constants
####################################################################################################

####################################################################################################
# Begin Utility Functions
####################################################################################################


print_log() {
    echo "$@"
    echo "$@" >> "$DIAG_DIR/general.log"
}

print_info() {
    if [ "$VERBOSE" -ge 1 ]; then
        echo "$@"
    fi
}

validate_run_level() {
    # test if arg is integer
    if ! test "$1" -eq "$1" 2>/dev/null; then
        failwith "Invalid run level: $1. Should be integer."
    fi
}

validate_out_dir() {
    mkdir -p "$1" ||
    failwith "Invalid output directory: $1." 
}

failwith() {
    echo "$@" 'Exiting'
    exit 1
}

get_python_command() {
    compgen -c | grep -m 1 '^python[23]$'
}


is_infiniband_sku() {
    echo "$1"| grep -iq '[[:digit:]]\+*r'
}

is_nvidia_sku() {
    echo "$1" | grep -i '^Standard_N' | grep -iqv '^Standard_NV.*_v4'
}

is_amd_gpu_sku() {
    echo "$1" | grep -iq '^Standard_NV.*_v4'
}

get_cpu_list() {
    ${CPU_LIST[$1]}
}


####################################################################################################
# End Utility Functions
####################################################################################################

####################################################################################################
# Begin Helper Functions
####################################################################################################

run_lsvmbus_resilient() {
    local LSVMBUS_PATH
    local PYTHON

    if command -v lsvmbus; then
        lsvmbus -vv
    elif PYTHON=$(get_python_command); then
        print_log "no lsvmbus installed. pulling script from github"
        LSVMBUS_PATH=$(mktemp)
        if curl -s "$LSVMBUS_URL" > "$LSVMBUS_PATH"; then
            $PYTHON "$LSVMBUS_PATH" -vv
            rm -f "$LSVMBUS_PATH"
        else
            print_log 'could neither find nor download lsvmbus'
        fi
    else
        print_log 'neither lsvmbus nor python detected'
    fi
}

run_vm_diags() {
    mkdir -p "$DIAG_DIR/VM"

    echo "$METADATA" >"$DIAG_DIR/VM/metadata.json"
    dmesg -T >"$DIAG_DIR/VM/dmesg.log"
    if [ -f /var/log/waagent.log ]; then
        cp /var/log/waagent.log "$DIAG_DIR/VM/waagent.log"
    else
        echo 'No waagent logs found' >"$DIAG_DIR/VM/waagent.log" 
    fi
    lspci -vv >"$DIAG_DIR/VM/lspci.txt"
    run_lsvmbus_resilient >"$DIAG_DIR/VM/lsvmbus.log"
    ip -s -h a >"$DIAG_DIR/VM/ifconfig.txt"
    # supressing sysctl's o/p
    sysctl -a --ignore 2>/dev/null >"$DIAG_DIR/VM/sysctl.txt"
    uname -a >"$DIAG_DIR/VM/uname.txt"
    dmidecode >"$DIAG_DIR/VM/dmidecode.txt"
    if [ -f /var/log/syslog ]; then
        cp /var/log/syslog "$DIAG_DIR/VM/syslog"
    else
        echo 'No syslogs found' >"$DIAG_DIR/VM/syslog"
    fi
}

run_cpu_diags() {
    mkdir -p "$DIAG_DIR/CPU"
    lscpu >"$DIAG_DIR/CPU/lscpu.txt"
}

run_memory_diags() {
    local STREAM_PATH="$DIAG_DIR/Memory/stream.tgz"

    # Stream Memory tests
    mkdir -p "$DIAG_DIR/Memory"

    # Download precompiled stream library
    if curl -s "$STREAM_URL" > "$STREAM_PATH"; then
        tar xzf $STREAM_PATH -C "$DIAG_DIR/Memory/"

        # run stream tests
        local stream_bin="$DIAG_DIR/Memory/Stream/stream_zen_double"
        if [ -f "$stream_bin" ]; then
            local cpu_list=$(get_cpu_list "$VM_SIZE")
            if [ ! -z "$cpu_list" ]; then
                # run stream stuff
                "$stream_bin" 400000000 "$cpu_list" > "$DIAG_DIR/Memory/stream.txt"
            else
                print_log "Current VM Size is not supported for stream tests. skiping"
                echo "Current VM Size is not supported for stream tests" > "$DIAG_DIR/Memory/stream.txt" 
            fi
        else
            print_log "failed to unpack stream binary to $stream_bin, unable to run stream memory tests."
        fi

        # Clean up
        rm -r "$DIAG_DIR/Memory/Stream"
        rm "$DIAG_DIR/Memory/._Stream"
        rm "$DIAG_DIR/Memory/stream.tgz"
    else
        print_log "Unable to download stream memory benchmark"
    fi

    
}

run_infiniband_diags() {
    print_log "Infiniband VM Detected"
    if command -v ibstat >/dev/null; then
        mkdir -p "$DIAG_DIR/Infiniband"
        ibstat > "$DIAG_DIR/Infiniband/ibstat.txt"
        ibv_devinfo > "$DIAG_DIR/Infiniband/ibv_devinfo.txt"
        if [ -f /sys/class/infiniband/mlx5_0/ports/pkeys/0 ]; then
            cp /sys/class/infiniband/mlx5_0/ports/pkeys/0 "$DIAG_DIR/Infiniband/pkey0.txt"
        else
            echo 'No pkey found' >"$DIAG_DIR/Infiniband/pkeys0.txt"
        fi
        if [ -f /sys/class/infiniband/mlx5_0/ports/pkeys/1 ]; then
            cp /sys/class/infiniband/mlx5_0/ports/pkeys/1 "$DIAG_DIR/Infiniband/pkey1.txt"
        else
            echo 'No pkey found' >"$DIAG_DIR/Infiniband/pkeys1.txt"
        fi
    else
        print_log "No Infiniband Driver Detected"
    fi
}

is_dcgm_installed() {
    command -v nv-hostengine >/dev/null
}

enable_persistence_mode() {
    local gpu_ids=$(nvidia-smi --list-gpus | awk '{print $2}' | tr -d :)
    for gpu_id in "$gpu_ids"; do
        nvidia-smi -i "$gpu_id" -pm 1 >/dev/null
    done
}

run_dcgm() {
    local nv_hostengine_out
    local nv_hostengine_already_running=false

    # because dcgmi makes files in working dir
    pushd "$DIAG_DIR/Nvidia" >/dev/null
    
    # start hostengine, remember if it was already running
    if ! nv_hostengine_out=$(nv-hostengine); then
        # e.g. 'Host engine already running with pid 5555'
        if echo "$nv_hostengine_out" | grep -q 'already running'; then
            print_log 'nv_hostengine already running, piggybacking'
            nv_hostengine_already_running=true
        else
            return 1
        fi
    fi

    # enable_persistence_mode for all gpus
    local gpus_wout_persistence=$(dcgmi diag -r 1 | 
        grep -A1 'Persistence Mode.*Fail' | 
        grep -o 'GPU [[:digit:]]\+' | 
        awk '{print $2}'
    )
    for id in "$gpus_wout_persistence"; do
        nvidia-smi -i "$id" -pm 1 >/dev/null
    done

    print_log "Running 2min diagnostic"
    dcgmi diag -r 2 >dcgm-diag-2.log

    if [ "$GPU_LEVEL" -gt 2 ]; then
        print_log "Running 12min diagnostic"
        dcgmi diag -r 3 >dcgm-diag-3.log
    fi


    # reset state to before script ran
    for id in "$gpus_wout_persistence"; do
        nvidia-smi -i "$id" -pm 0 >/dev/null
    done
    if [ ! "$nv_hostengine_already_running" = true ]; then
        nv-hostengine --term >/dev/null
    fi

    popd >/dev/null
}

run_nvidia_diags() {
    mkdir -p "$DIAG_DIR/Nvidia"
    print_log "Nvidia VM Detected"
    if command -v nvidia-smi >/dev/null; then
        nvidia-smi -q --filename="$DIAG_DIR/Nvidia/nvidia-smi.txt"
        nvidia-debugdump --dumpall --file "$DIAG_DIR/Nvidia/dump.zip"
        if is_dcgm_installed; then
            run_dcgm
        fi
    else
        print_log "No Nvidia Driver Detected"
    fi
}

####################################################################################################
# End Helper Functions
####################################################################################################

####################################################################################################
# Begin Option Parsing
####################################################################################################

VERBOSE=0
GPU_LEVEL=1
MEM_LEVEL=0
DISPLAY_HELP=false
# should be /opt/azurehpc/diagnostics
DIAG_DIR_LOC="$SCRIPT_DIR"

# Read in options
PARSED_OPTIONS=$(getopt -n "$0"  -o d:hvV --long "dir:,help,gpu-level:,mem-level:,verbose,version"  -- "$@")
if [ "$?" -ne 0 ]; then
        echo "$HELP_MESSAGE"
        exit 1
fi
eval set -- "$PARSED_OPTIONS"
 
while [ "$1" != "--" ]; do
  case "$1" in
    -d|--dir)
        shift
        validate_out_dir "$1"
        DIAG_DIR_LOC="$1"
        ;;
    --gpu-level) 
        shift
        validate_run_level "$1"
        GPU_LEVEL="$1"
        ;;
    -h|--help) DISPLAY_HELP=true;;
    --mem-level) 
        shift
        validate_run_level "$1"
        MEM_LEVEL="$1"
        ;;
    -v|--verbose) VERBOSE=$((i+1));;
    -V|--version) DISPLAY_VERSION=true;;
  esac
  shift
done
shift

####################################################################################################
# End Option Parsing
####################################################################################################

####################################################################################################
# Begin Main Script
####################################################################################################

if [ "$DISPLAY_VERSION" = true ]; then
    echo "$VERSION_INFO"
    exit 0
fi

if [ "$DISPLAY_HELP" = true ]; then
    echo "$HELP_MESSAGE"
    exit 0
fi

if [ $(whoami) != 'root' ]; then
    failwith 'This script requires root privileges to run. Please run again with sudo'
fi

echo "Azure HPC Diagnostics Tool"
echo ""
echo "NOTICE: This tool gathers various logs and diagnostic information."
echo "Some of this info, such as IP addresses, may be Personally Identifiable Information."
echo "It is up to the user to redact any sensitive info from the output if necessary"
echo "before sending it to Microsoft."
read -r -p "Please confirm that you understand. [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) echo "Thank you";;
    *)
        echo "No confirmation received"
        echo "Exiting"
        exit
        ;;
esac
echo ""

METADATA=$(curl -s -H Metadata:true "$METADATA_URL") || 
    failwith "Couldn't connect to Azure IMDS."

VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')
TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")

DIAG_DIR="$DIAG_DIR_LOC/$VM_ID.$TIMESTAMP"

rm -r "$DIAG_DIR" 2>/dev/null
mkdir -p "$DIAG_DIR"

print_log "Gathering VM Info"
run_vm_diags
print_log "Gathering CPU Info"
run_cpu_diags

if [ "$MEM_LEVEL" -gt 0 ]; then
    print_log "Running Memory Performance Test"
    run_memory_diags
fi

if is_infiniband_sku "$VM_SIZE"; then
    print_log "Gathering Infiniband Info"
    run_infiniband_diags
fi

if is_nvidia_sku "$VM_SIZE"; then
    print_log "Running Nvidia GPU Diagnostics"
    run_nvidia_diags
fi

if is_amd_gpu_sku "$VM_SIZE"; then
    print_log "Gathering AMD GPU Info"
    run_amd_gpu_diags
fi

tar czf "$DIAG_DIR.tar.gz" -C "$DIAG_DIR_LOC" "$VM_ID.$TIMESTAMP"  2>/dev/null && rm -r "$DIAG_DIR"
echo 'Placing diagnostic files in the following location:'
echo "$DIAG_DIR.tar.gz"

####################################################################################################
# End Main Script
####################################################################################################