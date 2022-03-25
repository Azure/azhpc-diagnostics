#!/bin/bash
# Azure HPC Diagnostics Tool
# Gathers Diagnostic info from guest VM
#
# tarball directory structure:
# - VM Information
#   - dmesg.log
#   - waagent.log
#   - lspci.txt
#   - lsvmbus.log
#   - ifconfig.txt
#   - sysctl.txt
#   - uname.txt
#   - dmidecode.txt
#   - journald.log|syslog|messages
#   - services
#   - selinux
#   - hyperv/kvp_pool*.txt
# - CPU
#   - lscpu.txt
# - Memory
#   - stream.txt
#   - ulimit
#   - zone_reclaim_mode
# - Infiniband
#   - ib-vmext-status
#   - ibstat.out
#   - ibstatus.out
#   - ibv_devinfo.out
#   - pkeys
#   - ethtool.out (ENDURE)
#   - rate (ENDURE)
#   - state (ENDURE)
#   - phys_state (ENDURE)
# - Nvidia GPU
#   - nvidia-bug-report.log.gz
#   - nvidia-installer.log
#   - nvidia-vmext-status
#   - nvidia-smi.out
#   - nvidia-smi-q.out
#   - nvidia-smi-nvlink.out
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

STREAM_URL='https://azhpcstor.blob.core.windows.net/diagtool-binaries/stream.tgz'
LSVMBUS_URL='https://raw.githubusercontent.com/torvalds/linux/master/tools/hv/lsvmbus'
HPC_DIAG_URL='https://raw.githubusercontent.com/Azure/azhpc-diagnostics/main/Linux/src/gather_azhpc_vm_diagnostics.sh'
SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
SYSFS_PATH=/sys # store as a variable so it is mockable
ETC_PATH=/etc
PROC_PATH=/proc
VAR_PATH=/var

NVIDIA_PCI_ID=10de
GPU_PCI_CLASS_ID=0302

# Mapping for stream benchmark(AMD only)
declare -A CPU_LIST
CPU_LIST=(["Standard_HB120rs_v2"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69,73,77,81,85,89,93,97,101,105,109,113,117"
          ["Standard_HB60rs"]="0 1,5,9,13,17,21,25,29,33,37,41,45,49,53,57")
RELEASE_DATE=20220328 # update upon each release
COMMIT_HASH=$( 
    (
        command -v git >/dev/null &&
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

read_binary_record() {
    od --skip-bytes="$1" --read-bytes="$2" --format=c --width=1 |
    awk '{
        if ($2 != "\\0") {
            printf("%s",$2)
        } else {
            printf("\n"); exit
        }
    }
    END {
        printf("\n")
        }'
}

is_infiniband_sku() {
    echo "$1" | cut -d_ -f2 | grep -q r
}

is_endure_sku() {
    echo "$1" | grep -Eiq '^Standard_(H16m?r|NC24rs?)$'
}

is_nvidia_sku() {
    local clean
    clean=$(echo "$1" | sed s/_Promo//g | tr '[:upper:]' '[:lower:]')

    [[ "$clean" =~ ^standard_nc(6|12|24r?)$ ]] ||
    [[ "$clean" =~ ^standard_nc(6|12|24r?)s_v2$ ]] ||
    [[ "$clean" =~ ^standard_nc(6|12|24r?)s_v3$ ]] ||
    \
    [[ "$clean" =~ ^standard_nc(4|8|16|64)as_t4_v3$ ]] ||
    \
    [[ "$clean" =~ ^standard_nd(6|12|24r?)s$ ]] ||
    [[ "$clean" =~ ^standard_nd40r?s_v2$ ]] ||
    [[ "$clean" =~ ^standard_nd96am?sr(_a100)?_v4$ ]] ||
    \
    [[ "$clean" =~ ^standard_nv(6|12|24)$ ]] ||
    [[ "$clean" =~ ^standard_nv(6|12|24)s_v2$ ]] ||
    [[ "$clean" =~ ^standard_nv(12|24|48)s_v3$ ]]
}

is_gpu_compute_sku() {
    echo "$1" | cut -d_ -f1 --complement | grep -Eiq '^N(C|D)'
}

is_vis_sku() {
    echo "$1" | cut -d_ -f1 --complement | grep -Eiq '^NV'
}

is_amd_gpu_sku() {
    local clean
    clean=$(echo "$1" | sed s/_Promo//g | tr '[:upper:]' '[:lower:]')
    
    [[ "$clean" =~ ^standard_nv(4|8|16|32)as_v4$ ]]
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

get_metadata() {
    local path="$1"
    curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/$path?api-version=2021-03-01&format=text"
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

    if command -v lsvmbus >/dev/null; then
        print_log -e "\tWriting Hyper-V VMBus device list to {output}/VM/lsvmbus.log"
        mkdir -p "$DIAG_DIR/VM"
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
                mkdir -p "$DIAG_DIR/VM"
                $PYTHON "$LSVMBUS_PATH" -vv >"$DIAG_DIR/VM/lsvmbus.log"
                rm -f "$LSVMBUS_PATH"
            else
                print_log -e '\tFailed to download lsvmbus; skipping'
            fi
        fi
    fi
}

filter_syslog() {
    # To avoid overcollecting, filter out messages like this
    # Dec 31 23:59:59 hostname audit: CWD cwd="/"
    awk '!index($5,"audit")'
}

fetch_syslog() {
    if systemctl is-active systemd-journald >/dev/null 2>/dev/null && command -v journalctl >/dev/null; then
        print_log -e "\tDumping system logs from journald to {output}/VM/journald.log"
        journalctl | filter_syslog > "$DIAG_DIR/VM/journald.log"
    elif [ -f /var/log/syslog ]; then
        print_log -e "\tCopying sytem logs from /var/log/syslog to {output}/VM/syslog"
        filter_syslog </var/log/syslog >"$DIAG_DIR/VM/syslog"
    elif [ -f /var/log/messages ]; then
        print_log -e "\tCopying sytem logs from /var/log/messages to {output}/VM/messages"
        filter_syslog </var/log/messages >"$DIAG_DIR/VM/messages"
    else
        print_log -e "\tNo system logs found. Checked journald and /var/log/syslog|messages"
    fi
}

read_kvp() {
    local filename="$1"
    local KEY_BYTELEN=512
    local VALUE_BYTELEN=2048
    local RECORD_BYTELEN=$(( KEY_BYTELEN + VALUE_BYTELEN ))
    local file_len
    file_len=$(wc --bytes "$filename" | cut -d' ' -f1)
    local record_count=$(( file_len / RECORD_BYTELEN ))
    local key value
    for i in $(seq 0 $(( record_count - 1 ))); do
        key=$(read_binary_record $(( RECORD_BYTELEN * i )) $KEY_BYTELEN <"$filename")
        value=$(read_binary_record $(( RECORD_BYTELEN * i + KEY_BYTELEN )) $VALUE_BYTELEN <"$filename")
        printf "Key: %s; Value: %s\n" "$key" "$value"
    done
}

run_vm_diags() {
    mkdir -p "$DIAG_DIR/VM"

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

    print_log -e "\tWriting list of active kernel modules to {output}/VM/lsmod.txt"
    lsmod >"$DIAG_DIR/VM/lsmod.txt"

    fetch_syslog

    mkdir -p "$DIAG_DIR/VM/hyperv"
    for file in "$VAR_PATH"/lib/hyperv/.kvp_pool*; do
        local filename
        filename=$(basename "$file" | sed 's/^\.//g')
        print_log -e "\tDumping Hyper-V KVP data from $file to {output}/VM/kvp/$filename.txt"
        read_kvp "$file" >"$DIAG_DIR/VM/hyperv/$filename.txt"
    done
    
    local services=(iptables firewalld cpupower waagent walinuxagent)
    if systemctl >/dev/null; then
        for service in "${services[@]}"; do
            print_log -e "\tWriting status of service $service {output}/VM/services"
            echo "$service $(systemctl is-active "$service")" >> "$DIAG_DIR/VM/services"
        done
    fi

    if [ -f $ETC_PATH/sysconfig/selinux ]; then
        print_log -e "\tWriting status of selinux {output}/VM/selinux"
        grep -V '^[[:space]]#' $ETC_PATH/sysconfig/selinux |
        grep 'SELINUX=\(enforcing\|permissive\|disabled\)' $ETC_PATH/sysconfig/selinux |
        head -1 >"$DIAG_DIR/VM/selinux"
        [ -s "$DIAG_DIR/VM/selinux" ] || rm "$DIAG_DIR/VM/selinux"
    fi
}

run_cpu_diags() {
    mkdir -p "$DIAG_DIR/CPU"

    print_log -e "\tWriting CPU architecture details to {output}/CPU/lscpu.txt"
    lscpu >"$DIAG_DIR/CPU/lscpu.txt"
}

run_stream() {
    local STREAM_PATH="$DIAG_DIR/Memory/stream.tgz"
    local cpu_list
    cpu_list=$(get_cpu_list "$VM_SIZE")
    if [ -z "$cpu_list" ]; then
        print_log -e "\tCurrent VM Size is not supported for stream tests. Skipping"
        return 1
    fi

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

run_memory_diags() {
    mkdir -p "$DIAG_DIR/Memory"
    cp $ETC_PATH/security/limits.conf "$DIAG_DIR/Memory"
    cp $PROC_PATH/sys/vm/zone_reclaim_mode "$DIAG_DIR/Memory"
    if [ "$MEM_LEVEL" -gt 0 ]; then
        print_log ''
        print_log "Running Memory Performance Test"
        run_stream
    fi 
}

run_infiniband_diags() {
    if [ -f /var/log/azure/ib-vmext-status ]; then
        mkdir -p "$DIAG_DIR/Infiniband"
        print_log -e "\tCopying Infiniband Driver Extension logs to {output}/Infiniband/ib-vmext-status"
        cp /var/log/azure/ib-vmext-status "$DIAG_DIR/Infiniband"
    fi

    local ib_interfaces
    if command -v ibstatus >/dev/null; then
        mkdir -p "$DIAG_DIR/Infiniband"

        print_log -e "\tQuerying Infiniband device status, writing to {output}/Infiniband/ibstatus.out"
        ibstatus > "$DIAG_DIR/Infiniband/ibstatus.out"

        ib_interfaces=$(
            awk '
            /Infiniband device/ { device_name=$3 }
            /link_layer:\s+InfiniBand/ { print device_name }' "$DIAG_DIR/Infiniband/ibstatus.out" | tr -d "'"
        )
        if command -v ibstat >/dev/null; then
            print_log -e "\tWriting ibstat info for device(s) $(echo "$ib_interfaces" | xargs) to {output}/Infiniband/ibstat.out"
            for ib_interface in $ib_interfaces; do
                ibstat "$ib_interface"
            done >"$DIAG_DIR/Infiniband/ibstat.out"
        else
            print_log -e "\tibstat not found."
        fi

        print_log -e "\tWriting Infiniband device info to {output}/Infiniband/ibv_devinfo.out"
        ibv_devinfo -v > "$DIAG_DIR/Infiniband/ibv_devinfo.out" 2>&1
    elif is_endure_sku "$VM_SIZE"; then
        print_log -e "\tNon-SR-IOV VM size detected."
        local device_paths=("$SYSFS_PATH"/class/infiniband/*/ports/1)
        if ip address show eth1 >/dev/null && [ ${#device_paths[@]} -eq 1 ] && [ -d "${device_paths[0]}" ]; then
            local device_path=${device_paths[0]}
            mkdir -p "$DIAG_DIR/Infiniband"
            print_log -e "\tCopying $device_path/state to {output}/Infiniband/state"
            cp "$device_path/state" "$DIAG_DIR/Infiniband"
            print_log -e "\tCopying $device_path/rate to {output}/Infiniband/rate"
            cp "$device_path/rate" "$DIAG_DIR/Infiniband"
            print_log -e "\tCopying $device_path/phys_state to {output}/Infiniband/phys_state"
            cp "$device_path/phys_state" "$DIAG_DIR/Infiniband"
            ethtool eth1 >"$DIAG_DIR/Infiniband/ethtool.out"
        else
            print_log "ENDURE : No IB devices found"
        fi
        ib_interfaces=$(basename "$SYSFS_PATH"/class/infiniband/*)
    else
        print_log -e "\tNo Infiniband Driver Detected"
    fi

    print_log -e "\tChecking for Infiniband pkeys"
    for device in $ib_interfaces; do
        local dir="$SYSFS_PATH/class/infiniband/$device"
        if ! [ -d "$dir" ]; then
            print_log "\tDevice $device not showing up in $SYSFS_PATH/class/infiniband/"
        else
            print_log -e "\tChecking for Infiniband pkeys in $dir"
        fi
        mkdir -p "$DIAG_DIR/Infiniband/$device/pkeys"

        local pkey_count
        local pkey_dir="$SYSFS_PATH/class/infiniband/$device/ports/1/pkeys"
        pkey_count=$(find "$pkey_dir/" -maxdepth 1 -name '[0-9]*' | wc -l)
        if [ "$pkey_count" -gt 0 ]; then
            mkdir -p "$(realpath "$DIAG_DIR")/Infiniband/$device/pkeys"
            print_log -e "\tFound $pkey_count pkeys in $pkey_dir; copying them to {output}/Infiniband/$device/pkeys/"
            cp "$SYSFS_PATH/class/infiniband/$device/ports/1/pkeys/"* "$(realpath "$DIAG_DIR")/Infiniband/$device/pkeys"
        else
            print_log -e "\tFound no pkeys in $dir"
        fi
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
        print_log -e "\tTemporarily starting nv-hostengine"
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

is_nvidia_driver_installed() (
    lsmod | awk '{print $1}' | grep -Eiq '^nvidia$'
)

investigate_nvidia_driver_installation() (
    if [ -f /var/log/nvidia-installer.log ]; then
        mkdir -p "$DIAG_DIR/Nvidia"
        print_log -e "\tCopying Nvidia GPU Driver Installer logs to {output}/Nvidia/nvidia-installer.log"
        cp /var/log/nvidia-installer.log "$DIAG_DIR/Nvidia"
    else
        print_log -e "\tNo Nvidia GPU Driver Installer logs found."
    fi
)

run_nvidia_diags() {

    if [ -f /var/log/azure/nvidia-vmext-status ]; then
        mkdir -p "$DIAG_DIR/Nvidia"
        print_log -e "\tCopying Nvidia GPU Driver Extension logs to {output}/Nvidia/nvidia-vmext-status"
        cp /var/log/azure/nvidia-vmext-status "$DIAG_DIR/Nvidia"
    fi

    if ! is_nvidia_driver_installed; then
        print_log -e "No NVIDIA driver found. Checking for installation logs"
        investigate_nvidia_driver_installation
    elif ! command -v nvidia-smi >/dev/null; then
        print_log -e "NVIDIA driver is installed, but can't find nvidia-smi. Please check that it's on the PATH."
    else
        mkdir -p "$DIAG_DIR/Nvidia"
        print_log -e "\tQuerying Nvidia GPU Info, writing to {output}/Nvidia/nvidia-smi-q.out"
        timeout 5m nvidia-smi -q >"$DIAG_DIR/Nvidia/nvidia-smi-q.out"
        if [ $? -eq 124 ]; then
            print_log -e "\tnvidia-smi -q timed out"
        else
            print_log -e "\tRunning plain nvidia-smi, writing to {output}/Nvidia/nvidia-smi.out"
            timeout 5m nvidia-smi >"$DIAG_DIR/Nvidia/nvidia-smi.out"
        fi
        print_log -e "\tDumping Nvidia GPU internal state to {output}/Nvidia/nvidia-debugdump.zip"
        nvidia-debugdump --dumpall --file "$DIAG_DIR/Nvidia/nvidia-debugdump.zip"
        if is_dcgm_installed; then
            run_dcgm
        fi
        print_log -e "\tChecking nvlinks"
        nvidia-smi nvlink -s >"$DIAG_DIR/Nvidia/nvlink.out"
    fi

    if command -v nvidia-bug-report.sh >/dev/null; then
        mkdir -p "$DIAG_DIR/Nvidia"
        print_log -e "\tRunning nvidia-bug-report.sh and outputting to {output}/Nvidia/nvidia-bug-report.log.gz"
        print_log -e "\tIn the event of hardware failure, this log may be shared with Nvidia:"
        print_log -e "$(timeout 5m nvidia-bug-report.sh --safe-mode --extra-system-data --output-file "$DIAG_DIR/Nvidia/nvidia-bug-report.log" | sed 's/^/\t/')"
    fi
}

is_extension_running() {
    sudo ps aux | grep -v grep | grep -m1 'nvidia-vmext.sh enable'
}

run_amd_gpu_diags() {
    print_log -e "\tNo AMD GPU diagnostics supported at this time."
}

function report_bad_gpu {
    if ! PARSED_OPTIONS=$(getopt -n "$0" -o "i" --long "index:,reason:,pci-domain:"  -- "$@"); then
        echo "Illegal arguments"
        return 1
    fi
    
    eval set -- "$PARSED_OPTIONS"
    local index reason pci_domain
    while [ "$1" != "--" ]; do
        case "$1" in
            -i|--index) index=$2;;
            --reason) reason=$2;;
            --pci-domain) pci_domain=$2;;
        esac
        shift 2
    done
    shift

    if [ -n "$index" ] && [ -n "$pci_domain" ]; then
        if [ "$pci_domain" != "$(nvidia-smi --query-gpu=pci.domain -i "$index" --format=csv,noheader)" ]; then
            print_log -e "\tmismatched gpu index and pci domain passed in"
            return 1
        fi
    elif [ -n "$index" ]; then
        pci_domain=$(nvidia-smi --query-gpu=pci.domain -i "$index" --format=csv,noheader) || {
            print_log -e "nvidia-smi failed during bad gpu reporting"
            return 1
        }
    elif [ -n "$pci_domain" ]; then
        index=$(nvidia-smi --query-gpu=pci.domain,index --format=csv,noheader 2>/dev/null | grep -i "^0x$pci_domain" | cut -d' ' -f 2)
    fi

    local serial
    [ -n "$index" ] &&
        serial=$(nvidia-smi --query-gpu=serial -i "$index" --format=csv,noheader) || 
        serial=UNKNOWN

    local device
    local DEVICES_PATH="$SYSFS_PATH/bus/vmbus/devices"
    device=$(find -L "$DEVICES_PATH" -maxdepth 2 -mindepth 2 -iname "*${pci_domain#0x}*")
    local bus_id
    bus_id=$(basename "$(dirname "$device")")
    print_log -e "\tBAD GPU ($reason) with bus Id $bus_id and serial number $serial"
}

function check_page_retirement {
    local remapped_rows sbe_dbe pci_domain
    remapped_rows=$(nvidia-smi --query-remapped-rows=remapped_rows.failure,gpu_bus_id --format=csv,noheader) || {
        print_log -e "\tcheck_page_retirement called, but nvidia-smi is failing"
        return 1
    }
    sbe_dbe=$(nvidia-smi --query-gpu=retired_pages.sbe,retired_pages.dbe, --format=csv,noheader) || {
        print_log -e "\tcheck_page_retirement called, but nvidia-smi is failing"
        return 1
    }
    if echo "$remapped_rows" | grep -Eiq '\[N/A\]'; then
        print_log -e "\tChecking for GPUs over the page retirement threshold"
        local i=0
        echo "$sbe_dbe" | sed 's/, /\t/g' |
        while read -r sbe dbe; do 
            local retired_page_count=$(( sbe + dbe ))
            if (( retired_page_count >= 60 )); then
                report_bad_gpu --index="$i" --reason="DBE($retired_page_count)"
            fi
            ((i++))
        done
    else
        print_log -e "\tChecking for GPUs with row remapping failures"
        echo "$remapped_rows" | sed 's/, /\t/g' |
        while read -r row_remap_failure pci_bus_id; do
            if (( row_remap_failure == 1 )); then
                pci_domain=$(echo "$pci_bus_id" | cut -d: -f1 | sed -E 's/^.{4}//g')
                report_bad_gpu --pci-domain="$pci_domain" --reason="Row Remap Failure"
            fi
        done
    fi
}

function check_inforom {
    # e.g. WARNING: infoROM is corrupted at gpu 15B5:00:00.0
    local keywords='WARNING: infoROM is corrupted at gpu'
    local nvsmi_domains
    nvsmi_domains=$(nvidia-smi --query-gpu=pci.domain --format=csv,noheader) || {
        print_log -e "\tcheck_inforom called, but nvidia-smi is failing"
        return 1
    }
    print_log -e "\tChecking for GPUs with corrupted infoROM"

    grep "$keywords" "$DIAG_DIR/Nvidia/nvidia-smi.out" | while IFS= read -r warning; do
        local pci_domain
        pci_domain=$(echo "$warning" | awk '{print $NF}' | awk -F: '{print $1}')
        local i
        i=$(echo "$nvsmi_domains" | awk "/$pci_domain/{print FNR}")
        ((i--)) # convert to 0-index
        report_bad_gpu --index="$i" --reason="infoROM Corrupted"
    done
}

function check_missing_gpus {
    local pci_domains nvsmi_domains
    nvsmi_domains=$(mktemp)
    nvidia-smi --query-gpu=pci.domain --format=csv,noheader >"$nvsmi_domains" || {
        print_log -e "\tcheck_missing_gpus called, but nvidia-smi is failing"
        return 1
    }
    pci_domains=$(lspci -d "$NVIDIA_PCI_ID:" -mnD | grep -E "\S+\s\"$GPU_PCI_CLASS_ID\"" | cut -d: -f1)
    print_log -e "\tChecking for GPUs that don't appear in nvidia-smi"
    for pci_domain in $pci_domains; do
        if ! grep -iq "^0x$pci_domain$" "$nvsmi_domains"; then
            report_bad_gpu --pci-domain="$pci_domain" --reason="GPU not coming up in nvidia-smi"
        fi
    done
    rm "$nvsmi_domains"
}

function check_nvlinks {
    awk '/GPU/{i=$2} /inactive/{print i}' "$DIAG_DIR/Nvidia/nvidia-smi-nvlink.out" | tr -d : | uniq |
    while read -r bad_gpu; do
        report_bad_gpu --index $bad_gpu --reason "NVLINK(s) inactive"
    done
}

function check_nouveau {
    if grep -q nouveau "$DIAG_DIR/VM/lsmod.txt"; then
        print_log -e '\tNouveau driver detected. This driver is unsupported.'
    fi
}

function check_pci_bandwidth {
    print_log -e "\tChecking PCIe speed training for GPUs"
    
    for pci_id in $(lspci -d "$NVIDIA_PCI_ID:" -mnD | awk '$2 == "\"'"$GPU_PCI_CLASS_ID"'\"" {print $1}'); do
        local speed_cap width_cap speed_sta width_sta
        speed_cap=$(lspci -vv -s "$pci_id" | grep 'LnkCap:' | grep -o 'Speed [0-9.]\+GT/s' | grep -o '[0-9.]\+')
        speed_sta=$(lspci -vv -s "$pci_id" | grep 'LnkSta:' | grep -o 'Speed [0-9.]\+GT/s' | grep -o '[0-9.]\+')
        width_cap=$(lspci -vv -s "$pci_id" | grep 'LnkCap:' | grep -o 'Width x[0-9]\+' | grep -o '[0-9]\+')
        width_sta=$(lspci -vv -s "$pci_id" | grep 'LnkSta:' | grep -o 'Width x[0-9]\+' | grep -o '[0-9]\+')
        if [ "$speed_sta" -ne "$speed_cap" ] || [ "$width_sta" -ne "$width_cap" ]; then
            local reason="PCIe link not showing expected performance: OBSERVED Speed ${speed_sta}GT/s, Width x${width_sta}; EXPECTED ${speed_cap}GT/s, Width x${width_cap}"
            report_bad_gpu --pci-domain="$(echo "$pci_id" | cut -d: -f1)" --reason="$reason"
        fi
    done
}

function check_pkeys {
    local device
    for device_path in "$DIAG_DIR"/Infiniband/*; do
        [ -d "$device_path" ] || continue
        device=$(basename "$device_path")
        for pkeyNum in {0..1}; do
            if ! [ -s "$DIAG_DIR/Infiniband/$device/pkeys/$pkeyNum" ]; then
                print_log -e "\tCould not find pkey $pkeyNum for device $device"
            fi
        done
    done
}

function check_tuning() {
    print_log -e "\tChecking VM configuration against recommended settings."
    if [ "$(cat "$DIAG_DIR/Memory/zone_reclaim_mode")" -ne 1 ]; then
        print_log 'Set zone_reclaim_mode to 1'
    fi

    awk '/^\*/{
        switch ($3) {
            case "memlock":
                desired="unlimited"
                break
            case "nofile":
                desired=65535
                break
            case "stack":
                desired="unlimited"
            default:
                next
        }
        if ($4 != desired) {
            printf("Consider setting ulimit %s to %s\n", $3, desired)
        }
    }' "$DIAG_DIR/Memory/limits.conf" | sort | uniq | while read -r warning; do
        print_log -e "\t$warning"
    done

    if [ -s "$DIAG_DIR/VM/selinux" ] && [ "$(cut -d= -f2 "$DIAG_DIR/VM/selinux")" = 'enforcing' ]; then
        print_log -e "\tConsider disabling selinux to avoid interfering with MPI"
    fi
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

function main {
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

    VM_SIZE=$(get_metadata compute/vmSize)
    VM_ID=$(get_metadata compute/vmId)

    IMAGE_PUBLISHER=$(get_metadata compute/storageProfile/imageReference/publisher)
    IMAGE_OFFER=$(get_metadata compute/storageProfile/imageReference/offer)
    IMAGE_SKU=$(get_metadata compute/storageProfile/imageReference/sku)
    IMAGE_VERSION=$(get_metadata compute/storageProfile/imageReference/version)
    TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")

    echo ''

    DIAG_DIR="$DIAG_DIR_LOC/$VM_ID.$TIMESTAMP"

    rm -r "$DIAG_DIR" 2>/dev/null
    mkdir -p "$DIAG_DIR"

    # keep a trace of this execution
    exec 2> "$DIAG_DIR/hpcdiag.err"
    set -x

    print_log "Virtual Machine Details:"
    print_log -e "\tID: $VM_ID"
    print_log -e "\tSize: $VM_SIZE"
    if [ "$IMAGE_PUBLISHER" == 'Not found' ] ||
        [ "$IMAGE_OFFER" == 'Not found' ] ||
        [ "$IMAGE_SKU" == 'Not found' ] ||
        [ "$IMAGE_VERSION" == 'Not found' ]; then
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

    print_log "Collecting Linux VM Diagnostics"
    run_vm_diags

    print_log ''
    print_log "Collecting CPU Info"
    run_cpu_diags

    print_log ''
    print_log "Collecting Memory Info"
    run_memory_diags

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

    if is_nvidia_sku "$VM_SIZE" && [ -s "$DIAG_DIR/Nvidia/nvidia-smi.out" ]; then
        check_inforom
        check_page_retirement
        check_missing_gpus
        check_pci_bandwidth
        check_nvlinks
        if is_gpu_compute_sku "$VM_SIZE"; then
            check_nouveau
        fi
    fi

    if is_infiniband_sku "$VM_SIZE" && ! is_endure_sku "$VM_SIZE"; then
        check_pkeys
    fi

    if [ "$TUNING" = true ]; then
        print_log ''
        print_log 'Checking for opportunities for performance tuning'
        check_tuning
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
}

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
OPTIONS_LIST='dir:,help,gpu-level:,mem-level:,no-update,offline,tuning,version'
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
        DIAG_DIR_LOC=$(realpath "$1")
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
    --tuning) TUNING=true;;
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

if [ "$OFFLINE" != true ] && [ "$DISABLE_UPDATE" != true ] && ! [[ $- =~ 's' ]]; then
    check_for_updates
fi

if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    # This lets us load all functions for unit testing.
    # We wouldn't want people sourcing this script anyway.
    echo "Script is being sourced. Skipping main execution."
elif [ "$DISPLAY_VERSION" = true ]; then
    echo "$VERSION_INFO"
elif [ "$DISPLAY_HELP" = true ]; then
    echo "$HELP_MESSAGE"
elif [ "$(whoami)" != 'root' ]; then
    failwith 'This script requires root privileges to run. Please run again with sudo'
elif ext_process=$(is_extension_running); then
    echo 'Detected a VM Extension installation script running in the background'
    echo 'Please wait for it to finish and retry'
    echo "Extension pid: $(echo "$ext_process" | awk '{print $2}')"
    exit 1
else
    main
fi
