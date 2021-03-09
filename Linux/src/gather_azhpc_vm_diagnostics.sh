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
#   - ifconfig.txt
#   - sysctl.txt
#   - uname.txt
#   - dmidecode.txt
#   - journald.txt|syslog|messages
# - CPU
#   - lscpu.txt
# - Memory
#   - stream.txt
# - Infiniband
#   - ib-vmext-status
#   - ibstat.txt
#   - ibv_devinfo.out
#   - ibv_devinfo.err
#   - pkeys
# - Nvidia GPU
#   - nvidia-bug-report.log.gz
#   - nvidia-vmext-status
#   - nvidia-smi.txt (human-readable)
#   - nvidia-debugdump.zip (only Nvidia can read)
#   - dcgm-diag-2.log
#   - dcgm-diag-3.log
#   - nvvs.log
#   - stats_*.json
#
# Outputs:
# - transcript of run
# - name of tarball to stdout
# - tarball of all logs
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.



####################################################################################################
# Begin Constants
####################################################################################################

METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'
IMAGE_METADATA_URL='http://169.254.169.254/metadata/instance/compute/storageProfile/imageReference?api-version=2020-06-01'
STREAM_URL='https://azhpcstor.blob.core.windows.net/diagtool-binaries/stream.tgz'
LSVMBUS_URL='https://raw.githubusercontent.com/torvalds/linux/master/tools/hv/lsvmbus'
HPC_DIAG_URL='https://raw.githubusercontent.com/Azure/azhpc-diagnostics/main/Linux/src/gather_azhpc_vm_diagnostics.sh'
SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"

# Mapping for stream benchmark(AMD only)
declare -A CPU_LIST
CPU_LIST=(["Standard_HB120rs_v2"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69,73,77,81,85,89,93,97,101,105,109,113,117"
          ["Standard_HB60rs"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57")
RELEASE_DATE=20210223 # update upon each release
COMMIT_HASH=$( 
    (
        cd "$SCRIPT_DIR" &&
        git config --get remote.origin.url | grep -q 'Azure/azhpc-diagnostics.git$' &&
        git rev-parse HEAD 2>/dev/null
    ) || 
    echo 'Unknown')
VERSION_INFO="$RELEASE_DATE-$COMMIT_HASH"

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
 --gpu-level=GPU_LEVEL dcgmi run level (default is 1)
 --mem-level=MEM_LEVEL set to 1 to run stream test (default is 0)
 --no-update           do not prompt for auto-update
 --offline             skips steps that require Internet access

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
    echo "$@" >> "$DIAG_DIR/transcript.log"
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

prompt() {
    local message="$1"
    local response
    local counter=2
    while (( counter-- > 0 )); do
        read -r -p "$message [y/N]" response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0;;
            [nN][oO]|[nN]) return 1;;
        esac
    done
    return 1
}

is_infiniband_sku() {
    echo "$1"| grep -Eiq '[[:digit:]]\+*r'
}

is_nvidia_sku() {
    echo "$1" | grep -i '^Standard_N' | grep -iqv '^Standard_NV.*_v4'
}

is_vis_sku() {
    echo "$1" | grep -iq '^Standard_NV'
}

is_amd_gpu_sku() {
    echo "$1" | grep -iq '^Standard_NV.*_v4'
}

get_cpu_list() {
    echo "${CPU_LIST[$1]}"
}

if tput cols >/dev/null 2>/dev/null && (( $(tput cols) < 80 )); then
    COLUMNS=$(tput cols)
else
    COLUMNS=80
fi

print_enclosed() {
    local line
    while (( "$#" )); do
        line='#'
        while
            line="$line $1"
            shift
            (( "$#" && ${#line} + 1 + ${#1} <  "$COLUMNS" - 2 ))
        do true; done
        while (( ${#line} < "$COLUMNS" - 2 )); do
            line="$line "
        done
        echo "$line #"
    done
}

print_divider() {
    for _ in $(seq "$COLUMNS"); do echo -n '#'; done
    echo ''
}

check_for_updates() {
    local message="You are not running the latest release of this tool. Switch to latest version?"

    local tmpfile
    tmpfile=$(mktemp)
    curl -s "$HPC_DIAG_URL" >"$tmpfile" || return 1
    if ! cmp --silent "$0" "$tmpfile"; then
        if prompt "$message"; then
            mv "$tmpfile" "$0"
            bash "$0" "$RUNTIME_OPTIONS"
            exit $?
        else
            return 0
        fi
    fi
    rm "$tmpfile"
}

####################################################################################################
# End Utility Functions
####################################################################################################

####################################################################################################
# Begin Helper Functions
####################################################################################################

validate_options() {
    if [ "$OFFLINE" = true ] && [ "$MEM_LEVEL" -gt 0 ]; then
        echo 'Cannot run stream test in offline mode.'
        return 1
    else
        return 0
    fi
}

run_lsvmbus_resilient() {
    local LSVMBUS_PATH
    local PYTHON

    if command -v lsvmbus; then
        print_log -e "\tWriting Hyper-V VMBus device list to {output}/VM/lsvmbus.log"
        lsvmbus -vv >"$DIAG_DIR/VM/lsvmbus.log"
    else
        if ! PYTHON="$(get_python_command)"; then
            print_log -e '\tNeither lsvmbus nor python detected; skipping'
            return 1
        elif [ "$OFFLINE" = true ]; then
            print_log -e '\tlsvmbus not installed and offline mode enabled; skipping'
            return 1
        else 
            print_log -e "\tNo lsvmbus installed; pulling a copy from Github"
            LSVMBUS_PATH=$(mktemp)
            if curl -s "$LSVMBUS_URL" > "$LSVMBUS_PATH"; then
                print_log -e "\tWriting Hyper-V VMBus device list to {output}/VM/lsvmbus.log"
                $PYTHON "$LSVMBUS_PATH" -vv >"$DIAG_DIR/VM/lsvmbus.log"
                rm -f "$LSVMBUS_PATH"
            else
                print_log -e '\tFailed to download lsvmbus; skipping'
            fi
        fi
    fi
}

run_vm_diags() {
    mkdir -p "$DIAG_DIR/VM"

    print_log -e "\tWriting Azure VM Metadata to {output}/VM/metadata.json"
    echo "$METADATA" >"$DIAG_DIR/VM/metadata.json"

    if [ -f /var/log/waagent.log ]; then
        print_log -e "\tCopying Azure VM Agent logs to {output}/VM/waagent.log"
        cp /var/log/waagent.log "$DIAG_DIR/VM/waagent.log"
    else
        print_log -e "\tCould not locate Azure VM Agent logs at /var/log/waagent.log"
    fi

    print_log -e "\tWriting PCI Device List to {output}/VM/lspci.txt"
    lspci -vv >"$DIAG_DIR/VM/lspci.txt"

    run_lsvmbus_resilient

    print_log -e "\tWriting network interface list to {output}/VM/ifconfig.txt"
    ip -stats -human-readable address >"$DIAG_DIR/VM/ifconfig.txt"

    print_log -e "\tWriting kernel parameters to {output}/VM/sysctl.txt"
    sysctl --all --ignore 2>/dev/null >"$DIAG_DIR/VM/sysctl.txt"

    print_log -e "\tWriting system information to {output}/VM/uname.txt"
    uname -a >"$DIAG_DIR/VM/uname.txt"

    print_log -e "\tDumping System Management BIOS table to {output}/VM/dmidecode.txt"
    dmidecode >"$DIAG_DIR/VM/dmidecode.txt"

    print_log -e "\tWriting kernel message buffer to {output}/VM/dmesg.log"
    dmesg -T >"$DIAG_DIR/VM/dmesg.log"

    if command -v journalctl >/dev/null; then
        print_log -e "\tDumping system logs from journald to {output}/VM/journald.txt"
        journalctl > "$DIAG_DIR/VM/journald.txt"
    elif [ -f /var/log/syslog ]; then
        print_log -e "\tCopying sytem logs from /var/log/syslog to {output}/VM/syslog"
        cp /var/log/syslog "$DIAG_DIR/VM"
    elif [ -f /var/log/messages ]; then
        print_log -e "\tCopying sytem logs from /var/log/messages to {output}/VM/messages"
        cp /var/log/messages "$DIAG_DIR/VM"
    else
        print_log -e "\tNo system logs found. Checked journald and /var/log/syslog|messages"
    fi
}

run_cpu_diags() {
    mkdir -p "$DIAG_DIR/CPU"

    print_log -e "\tWriting CPU architecture details to {output}/CPU/lscpu.txt"
    lscpu >"$DIAG_DIR/CPU/lscpu.txt"
}

run_memory_diags() {
    local STREAM_PATH="$DIAG_DIR/Memory/stream.tgz"
    local cpu_list
    cpu_list=$(get_cpu_list "$VM_SIZE")
    if [ -z "$cpu_list" ]; then
        print_log -e "\tCurrent VM Size is not supported for stream tests. Skipping"
        return 1
    fi

    # Stream Memory tests
    mkdir -p "$DIAG_DIR/Memory"

    # Download precompiled stream library
    print_log -e "\tDownloading precompiled Stream binary from Azure HPC Storage"
    if curl -s "$STREAM_URL" > "$STREAM_PATH"; then
        tar xzf "$STREAM_PATH" -C "$DIAG_DIR/Memory/"

        # run stream tests
        local stream_bin="$DIAG_DIR/Memory/Stream/stream_zen_double"
        if [ -f "$stream_bin" ]; then
            print_log -e "\tRunning Stream Benchmark and writing results to {output}/Memory/stream.txt"
            "$stream_bin" 400000000 "$cpu_list" > "$DIAG_DIR/Memory/stream.txt"
        else
            print_log -e "\tFailed to unpack stream binary to $stream_bin; unable to run stream memory tests."
        fi

        # Clean up
        rm -r "$DIAG_DIR/Memory/Stream"
        rm "$DIAG_DIR/Memory/._Stream"
        rm "$DIAG_DIR/Memory/stream.tgz"
    else
        print_log -e "\tUnable to download stream memory benchmark"
    fi
}

run_infiniband_diags() {
    if [ -f /var/log/azure/ib-vmext-status ]; then
        mkdir -p "$DIAG_DIR/Infiniband"
        print_log -e "\tCopying Infiniband Driver Extension logs to {output}/Infiniband/ib-vmext-status"
        cp /var/log/azure/ib-vmext-status "$DIAG_DIR/Infiniband"
    fi

    if command -v ibstat >/dev/null; then
        mkdir -p "$DIAG_DIR/Infiniband"

        print_log -e "\tQuerying Infiniband device status, writing to {output}/Infiniband/ibstat.txt"
        ibstat > "$DIAG_DIR/Infiniband/ibstat.txt"

        print_log -e "\tWriting Infiniband device info to {output}/Infiniband/ibv_devinfo.txt"
        ibv_devinfo > "$DIAG_DIR/Infiniband/ibv_devinfo.txt" 2>&1
    else
        print_log -e "\tNo Infiniband Driver Detected"
    fi

    print_log -e "\tChecking for Infiniband pkeys"
    for dir in /sys/class/infiniband/*; do
        [ -d "$dir" ] || continue

        print_log -e "\tChecking for Infiniband pkeys in $dir"
        device=$(basename "$dir")
        mkdir -p "$DIAG_DIR/Infiniband/$device/pkeys"

        local pkey_count
        pkey_count=$(find "$dir/" -path '*pkeys/*' -execdir echo {} \; | wc -l)
        print_log -e "\tFound $pkey_count pkeys in $dir; copying them to {output}/Infiniband/$device/pkeys/"

        find "$dir/" -path '*pkeys/*' \
            -execdir cp {} "$DIAG_DIR/Infiniband/$device/pkeys" \;
    done
}

is_dcgm_installed() {
    command -v nv-hostengine >/dev/null && command -v dcgmi >/dev/null
}

reset_gpu_state() {
    for id in $gpus_wout_persistence; do
        print_log -e "\tDisabling Persistence Mode for GPU $id"
        nvidia-smi -i "$id" -pm 0 >/dev/null
    done
    if [ "$nv_hostengine_already_running" = false ]; then
        print_log -e "\tTerminating nv-hostengine"
        nv-hostengine --term >/dev/null
    fi
}

run_dcgm() {
    # because dcgmi makes files in working dir
    pushd "$DIAG_DIR/Nvidia" >/dev/null || return 1
    
    # start hostengine, remember if it was already running
    local discovery_output
    discovery_output=$(dcgmi discovery -l)
    if [ "$?" -eq 255 ] || echo "$discovery_output" | grep -iq 'Unable to connect to host engine'; then
        nv_hostengine_already_running=true
    else
        nv_hostengine_already_running=false
    fi

    if [ "$nv_hostengine_already_running" = false ]; then
        print_log -e "\tTemporarily tarting nv-hostengine"
        nv-hostengine >/dev/null
    fi

    # enable_persistence_mode for all gpus
    gpus_wout_persistence=$(dcgmi diag -r 1 | 
        grep -A1 'Persistence Mode.*Fail' | 
        grep -o 'GPU [[:digit:]]\+' | 
        awk '{print $2}'
    )
    for id in $gpus_wout_persistence; do
        print_log -e "\tTemporarily enabling Persistence Mode for GPU $id"
        nvidia-smi -i "$id" -pm 1 >/dev/null
    done

    case "$GPU_LEVEL" in
    1)
        print_log -e "\tRunning DCGM diagnostics Level 1 (~ < 1 min)"
        timeout 1m dcgmi diag -r 1 >dcgm-diag.log
        ;;
    2)
        print_log -e "\tRunning DCGM diagnostics Level 2 (~ 2 min)"
        timeout 5m dcgmi diag -r 2 >dcgm-diag.log
        ;;
    3)
        print_log -e "\tRunning DCGM diagnostics Level 3 (~ 12 min)"
        timeout 20m dcgmi diag -r 3 >dcgm-diag.log
        ;;
    *)
        print_log -e "\tInvalid run-level for dcgm: $GPU_LEVEL"
        ;;
    esac
    if [ $? -eq 124 ]; then
        print_log -e "\tDCGM timed out"
    fi

    # reset state to before script ran
    reset_gpu_state

    popd >/dev/null || failwith "Failed to popd back to working directory"
}

run_nvidia_diags() {
    mkdir -p "$DIAG_DIR/Nvidia"

    if [ -f /var/log/azure/nvidia-vmext-status ]; then
        print_log -e "\tCopying Nvidia GPU Driver Extension logs to {output}/Nvidia/nvidia-vmext-status"
        cp /var/log/azure/nvidia-vmext-status "$DIAG_DIR/Nvidia"
    fi

    if command -v nvidia-smi >/dev/null; then
        print_log -e "\tQuerying Nvidia GPU Info, writing to {output}/Nvidia/nvidia-smi.txt"
        nvidia-smi -q --filename="$DIAG_DIR/Nvidia/nvidia-smi.txt"

        print_log -e "\tDumping Nvidia GPU internal state to {output}/Nvidia/nvidia-debugdump.zip"
        nvidia-debugdump --dumpall --file "$DIAG_DIR/Nvidia/nvidia-debugdump.zip"
        if is_dcgm_installed; then
            run_dcgm
        fi
    else
        print_log -e "\tNo Nvidia Driver Detected"
    fi

    if command -v nvidia-bug-report.sh >/dev/null; then
        print_log -e "\tRunning nvidia-bug-report.sh and outputting to {output}/Nvidia/nvidia-bug-report.log.gz"
        print_log -e "\tIn the event of hardware failure, this log may be shared with Nvidia:"
        print_log -e "$(nvidia-bug-report.sh --output-file "$DIAG_DIR/Nvidia/nvidia-bug-report.log" | sed 's/^/\t/')"
    fi
}

is_extension_running() {
    sudo ps aux | grep -v grep | grep -m1 'nvidia-vmext.sh enable'
}

run_amd_gpu_diags() {
    print_log -e "\tNo AMD GPU diagnostics supported at this time."
}

check_for_known_firmware_issue() {
    local diag_dir="$1"
    local system_logfile

    print_log -e '\tChecking for firmware issue affecting ConnectX-5 cards.'
    system_logfile=$(find "$diag_dir/VM/" -regex "$diag_dir/VM/\(journald.txt\|syslog\|messages\)")
    if [ ! -s "$system_logfile" ]; then
        print_log -e '\tCannot access system logs. Aborting check.'
        return 1
    fi
    local keypattern='INFO Daemon RDMA: waiting for any Infiniband device.*timeout'
    if grep -q 'No IB devices found' "$diag_dir/Infiniband/ibv_devinfo.txt" &&
       grep -q "$keypattern" "$system_logfile"; then

       print_log -e '\tDetected an Infiniband failure likely caused by a known firmware issue affecting VMs w/ConnectX-5 adapters'
       print_log -e '\tMicrosoft received a patch for this issue in January 2021. Please consult with support engineers'
    else
        print_log -e '\tNo ConnectX-5 firmware issue detected.'
    fi
}
is_CX5() {
    local vmsize="$1"
    echo "$vmsize" | grep -iq 'Standard_HB60rs' ||
    echo "$vmsize" | grep -iq 'Standard_HC44rs' ||
    echo "$vmsize" | grep -iq 'Standard_ND40rs_v2'
}

####################################################################################################
# End Helper Functions
####################################################################################################

####################################################################################################
# Begin Traps
####################################################################################################


function ctrl_c() {
        echo "** Aborting Diagnostics"
        echo "** Resetting system state"
        reset_gpu_state
        echo "** Done!"
        
        exit
}
trap ctrl_c INT

####################################################################################################
# End Traps
####################################################################################################

####################################################################################################
# Begin Option Parsing
####################################################################################################

GPU_LEVEL=1
MEM_LEVEL=0
DISPLAY_HELP=false
# should be /opt/azurehpc/diagnostics
DIAG_DIR_LOC="$SCRIPT_DIR"

# save options
RUNTIME_OPTIONS=$*

# Read in options
OPTIONS_LIST='dir:,help,gpu-level:,mem-level:,no-update,offline,version'
if ! PARSED_OPTIONS=$(getopt -n "$0"  -o d:hV --long "$OPTIONS_LIST"  -- "$@"); then
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
    --no-update) DISABLE_UPDATE=true;;
    --offline) OFFLINE=true;;
    -V|--version) DISPLAY_VERSION=true;;
  esac
  shift
done
shift

if ! validate_options; then
    echo "Exiting due to invalid configuration"
    exit 1
fi

####################################################################################################
# End Option Parsing
####################################################################################################

####################################################################################################
# Begin Main Script
####################################################################################################

if [ "$OFFLINE" != true ] && [ "$DISABLE_UPDATE" != true ]; then
    check_for_updates
fi

if [ "$DISPLAY_VERSION" = true ]; then
    echo "$VERSION_INFO"
    exit 0
fi

if [ "$DISPLAY_HELP" = true ]; then
    echo "$HELP_MESSAGE"
    exit 0
fi

if [ "$(whoami)" != 'root' ]; then
    failwith 'This script requires root privileges to run. Please run again with sudo'
fi



# check for running extension
if ext_process=$(is_extension_running); then
    echo 'Detected a VM Extension installation script running in the background'
    echo 'Please wait for it to finish and retry'
    echo "Extension pid: $(echo "$ext_process" | awk '{print $2}')"
    exit 1
fi

print_divider
print_enclosed Azure HPC Diagnostics Tool
print_divider
print_enclosed "NOTICES:" 
print_divider
print_enclosed This tool generates and bundles together various logs and diagnostic information. It, however, DOES NOT TRANSMIT any of said data. It is left to the user to choose to transmit this data to Microsoft.
print_divider
print_enclosed Some of this info, such as IP addresses, may be Personally Identifiable Information. It is up to the user to redact any sensitive info from the output 'if' necessary before sending it to Microsoft.
print_divider
print_enclosed This tool invokes various 3rd party tools 'if' they are present on the system Please review them and their EULAs at:
print_enclosed "https://github.com/Azure/azhpc-diagnostics"
print_divider
print_enclosed WARNING: THINK BEFORE YOU RUN THIS
print_divider
print_enclosed This tool runs benchmarks against system resource such as Memory and GPU. Expect it to DEGRADE PERFORMANCE 'for' or otherwise INTERFERE WITH any other processes running on this system that use such resources. It is advised that you DO NOT RUN THIS TOOL ALONGSIDE ANY OTHER JOBS on the system.
print_divider
print_enclosed Interrupt this tool at any 'time' to force it to reset system state and terminate.
print_divider
if ! prompt "Please confirm that you understand"; then
    echo "No confirmation received"
    echo "Exiting"
    exit
fi

METADATA=$(curl -s -H Metadata:true "$METADATA_URL") || 
    failwith "Couldn't connect to Azure IMDS."

VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')

IMAGE_METADATA=$(curl -s -H Metadata:true "$IMAGE_METADATA_URL")
IMAGE_PUBLISHER=$(echo "$IMAGE_METADATA" | grep -o '"publisher":"[^"]*"' | cut -d: -f2 | tr -d '"')
IMAGE_OFFER=$(echo "$IMAGE_METADATA" | grep -o '"offer":"[^"]*"' | cut -d: -f2 | tr -d '"')
IMAGE_SKU=$(echo "$IMAGE_METADATA" | grep -o '"sku":"[^"]*"' | cut -d: -f2 | tr -d '"')
IMAGE_VERSION=$(echo "$IMAGE_METADATA" | grep -o '"version":"[^"]*"' | cut -d: -f2 | tr -d '"')
TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")



echo ''
print_log "Virtual Machine Details:"
print_log -e "\tID: $VM_ID"
print_log -e "\tSize: $VM_SIZE"
if [ -z "$IMAGE_PUBLISHER" ] ||
    [ -z "$IMAGE_OFFER" ] ||
    [ -z "$IMAGE_SKU" ] ||
    [ -z "$IMAGE_VERSION" ]; then
    print_log -e "\tUnrecognized (Likely Custom) OS Image"
else
    print_log -e "\tOS Image: $IMAGE_PUBLISHER:$IMAGE_OFFER:$IMAGE_SKU:$IMAGE_VERSION"
fi
print_log ''

print_log 'Azure HPC Diagnostics Tool Run Details'
print_log -e "\tTool Version: $VERSION_INFO"
print_log -e "\tStart Time: $TIMESTAMP"
print_log -e "\tRuntime Options:"
for option in $RUNTIME_OPTIONS; do
    print_log -e "\t\t$option"
done
print_log -e "\tSelected Diagnostic Scenarios:"
print_log -e "\t- General VM"
print_log -e "\t- CPU"

if [ "$MEM_LEVEL" -gt 0 ]; then
    print_log -e "\t- Stream Memory Benchmark"
fi

if is_infiniband_sku "$VM_SIZE"; then
    print_log -e "\t- Infiniband"
fi

if is_nvidia_sku "$VM_SIZE"; then
    print_log -e "\t- Nvidia GPU"
fi

if is_amd_gpu_sku "$VM_SIZE"; then
    print_log -e "\t- AMD GPU"
fi
print_log ''


DIAG_DIR="$DIAG_DIR_LOC/$VM_ID.$TIMESTAMP"

rm -r "$DIAG_DIR" 2>/dev/null
mkdir -p "$DIAG_DIR"

# keep a trace of this execution
exec 2> "$DIAG_DIR/hpcdiag.err"
set -x

print_log "Collecting Linux VM Diagnostics"
run_vm_diags

print_log ''
print_log "Collecting CPU Info"
run_cpu_diags

if [ "$MEM_LEVEL" -gt 0 ]; then
    print_log ''
    print_log "Running Memory Performance Test"
    run_memory_diags
fi

if is_infiniband_sku "$VM_SIZE"; then
    print_log ''
    print_log "Collecting Infiniband Info"
    run_infiniband_diags
fi

if is_nvidia_sku "$VM_SIZE"; then
    print_log ''
    print_log "Running Nvidia GPU Diagnostics"
    run_nvidia_diags
fi

if is_amd_gpu_sku "$VM_SIZE"; then
    print_log ''
    print_log "Collecting AMD GPU Info"
    run_amd_gpu_diags
fi

print_log ''
print_log "End of Diagnostic Collection"
print_log ''
print_log "Checking for common issues"

if is_infiniband_sku "$VM_SIZE"; then
    for pkeyNum in {0..1}; do
        if ! [ -s "$DIAG_DIR/Infiniband/$device/pkeys/$pkeyNum" ]; then
            print_log -e "\tCould not find pkey $pkeyNum"
        fi
    done
fi

if is_CX5 "$VM_SIZE"; then
    check_for_known_firmware_issue "$DIAG_DIR"
fi
            
print_log ''

set +x

print_divider
print_enclosed 'Placing diagnostic files in the following location:'
print_enclosed "$DIAG_DIR.tar.gz"
print_divider
print_enclosed If you have already opened a support request, you can take the tarball and follow this link to upload it:
print_enclosed 'https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/managesupportrequest'
print_divider
tar czf "$DIAG_DIR.tar.gz" -C "$DIAG_DIR_LOC" "$VM_ID.$TIMESTAMP"  2>/dev/null && rm -r "$DIAG_DIR"
####################################################################################################
# End Main Script
####################################################################################################