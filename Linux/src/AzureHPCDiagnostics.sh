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
# - CPU
#   - lscpu.txt
# - Memory
#   - stream.txt
# - Infiniband
#   - ibstat.txt
#   - ibdev_info.txt
# - Nvidia GPU
#   - nvidia-smi.txt (human-readable)
#   - nvidia-smi-debug.dbg (only Nvidia can read)
#   - dcgm-diag-2.log
#   - dcgm-diag-3.log
# - AMD GPU
#
# Outputs:
# - name of tarball to stdout
# - tarball of all logs



####################################################################################################
# Begin Constants
####################################################################################################

METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'
LSVMBUS_URL='https://raw.githubusercontent.com/torvalds/linux/master/tools/hv/lsvmbus'
SCRIPT_PATH="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
PKG_ROOT="$(dirname $SCRIPT_PATH)"

# Mapping for stream benchmark(AMD only)
declare -A CPU_LIST
CPU_LIST=(["Standard_HB120rs_v2"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69,73,77,81,85,89,93,97,101,105,109,113,117"
          ["Standard_HB60rs"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57")

####################################################################################################
# End Constants
####################################################################################################

####################################################################################################
# Begin Utility Functions
####################################################################################################
print_info() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$@"
    fi
}

failwith() {
    echo "$@" 'Exiting'
    exit 1
}

get_python_command() {
    compgen -c | grep -m 1 '^python[23]$'
}

is_infiniband_sku() {
    echo "$1" | grep -q '_[HN][^_]*r'
}

is_nvidia_sku() {
    echo "$1" | grep 'Standard_N' | grep -q -v 'Standard_NV.*_v4'
}

is_amd_gpu_sku() {
    echo "$1" | grep -q 'Standard_NV.*_v4'
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
        print_info "no lsvmbus installed. pulling script from github"
        LSVMBUS_PATH=$(mktemp)
        curl -s "$LSVMBUS_URL" >"$LSVMBUS_PATH"
        $PYTHON "$LSVMBUS_PATH" -vv
        rm -f "$LSVMBUS_PATH"
    else
        print_info 'neither lsvmbus nor python detected'
    fi
}

run_vm_diags() {
    mkdir -p "$DIAG_DIR/VM"

    echo "$METADATA" >"$DIAG_DIR/VM/metadata.json"
    dmesg -T > "$DIAG_DIR/VM/dmesg.log"
    cp /var/log/waagent.log "$DIAG_DIR/VM/waagent.log"
    lspci -vv >"$DIAG_DIR/VM/lspci.txt"
    run_lsvmbus_resilient >"$DIAG_DIR/VM/lsvmbus.log"
}

run_cpu_diags() {
    mkdir -p "$DIAG_DIR/CPU"
    # numa_domains="$(numactl -H |grep available|cut -d' ' -f2)"
    lscpu >"$DIAG_DIR/CPU/lscpu.txt"
}

run_memory_diags() {
    # Stream Memory tests
    mkdir -p "$DIAG_DIR/Memory"
    # Download precompiled stream library
    wget --quite "https://azhpcscus.blob.core.windows.net/apps/Stream/stream.tgz" -P "$DIAG_DIR/Memory"
    local stream_download="$DIAG_DIR/Memory/stream.tgz"
    if [ -f "$stream_download" ]; then
        tar xzf $stream_download -C "$DIAG_DIR/Memory/"
        # run stream tests
        local stream_bin="$DIAG_DIR/Memory/Stream/stream_zen_double"
        if [ -f "$stream_bin" ]; then
            # run stream stuff
            $stream_bin 400000000 "${CPU_LIST[$VM_SIZE]}" > "$DIAG_DIR/Memory/stream.txt"
        else
            print_info "$stream_bin does not exist, unable to run stream memory tests."
        fi
    else
        print_info "Unable to download stream"
    fi

    # Clean up
    rm -r "$DIAG_DIR/Memory/Stream"
    rm "$DIAG_DIR/Memory/stream.tgz"
}

run_infiniband_diags() {
    mkdir -p "$DIAG_DIR/Infiniband"
    print_info "Infiniband VM Detected"
    if command -v ibstat >/dev/null; then
        ibstat > "$DIAG_DIR/Infiniband/ibstat.txt"
        ibv_devinfo > "$DIAG_DIR/Infiniband/ibv_devinfo.txt"
    else
        print_info "No Infiniband Driver Detected"
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
    
    if ! nv_hostengine_out=$(nv-hostengine); then
        # e.g. 'Host engine already running with pid 5555'
        if echo "$nv_hostengine_out" | grep -q 'already running'; then
            print_info 'nv_hostengine already running, piggybacking'
            nv_hostengine_already_running=true
        else
            return 1
        fi
    fi

    enable_persistence_mode

    print_info "Running 2min diagnostic"
    dcgmi diag -r 2 >"$DIAG_DIR/Nvidia/dcgm-diag-2.log"
    print_info "Running 12min diagnostic"
    dcgmi diag -r 3 >"$DIAG_DIR/Nvidia/dcgm-diag-3.log"

    # reset state to before script ran
    if [ ! "$nv_hostengine_already_running" = true ]; then
        nv-hostengine --term >/dev/null
    fi
}

run_nvidia_diags() {
    mkdir -p "$DIAG_DIR/Nvidia"
    print_info "Nvidia VM Detected"
    if command -v nvidia-smi >/dev/null; then
        nvidia-smi -q \
            --filename="$DIAG_DIR/Nvidia/nvidia-smi.txt" \
            --debug="$DIAG_DIR/Nvidia/nvidia-smi-debug.dbg"
        if is_dcgm_installed; then
            run_dcgm
        fi
    else
        print_info "No Nvidia Driver Detected"
    fi
}

####################################################################################################
# End Helper Functions
####################################################################################################

####################################################################################################
# Begin Option Parsing
####################################################################################################

optstring=':v'

VERBOSE=0

while getopts ${optstring} arg; do
    case "${arg}" in
        v) VERBOSE=1 ;;
        *) echo "$0: error: no such option: -${OPTARG}"; exit 1 ;;
    esac
done

####################################################################################################
# End Option Parsing
####################################################################################################

####################################################################################################
# Begin Main Script
####################################################################################################

if [ $(whoami) != 'root' ]; then
    failwith 'This script requires root privileges to run. Please run again with sudo'
fi

METADATA=$(curl -s -H Metadata:true "$METADATA_URL") || 
    failwith "Couldn't connect to Azure IMDS."

VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')
TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")

DIAG_DIR="$VM_ID.$TIMESTAMP"
rm -r "$DIAG_DIR" 2>/dev/null
mkdir -p "$DIAG_DIR"


run_vm_diags
run_cpu_diags
run_memory_diags

if is_infiniband_sku "$VM_SIZE"; then
    run_infiniband_diags
fi

if is_nvidia_sku "$VM_SIZE"; then
    run_nvidia_diags
fi

if is_amd_gpu_sku "$VM_SIZE"; then
    run_amd_gpu_diags
fi

tar czf "$DIAG_DIR.tar.gz" "$DIAG_DIR" && rm -r "$DIAG_DIR"
echo "$DIAG_DIR.tar.gz"

####################################################################################################
# End Main Script
####################################################################################################