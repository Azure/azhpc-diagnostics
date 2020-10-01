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
# - Memory
# - Infiniband
#   - ibstat.txt
#   - ibdev_info.txt
# - Ethernet
# - Nvidia GPU
#   - nvidia-smi.txt (human-readable)
#   - nvidia-smi-debug.dbg (only Nvidia can read)
# - AMD GPU
#
# Dependencies:
# - lsvmbus.sh
#
# Outputs:
# - name of tarball to stdout
# - tarball of all logs

METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2017-12-01'


optstring=':v'

VERBOSE=0

while getopts ${optstring} arg; do
    case "${arg}" in
        v) VERBOSE=1 ;;
        *) echo "$0: error: no such option: -${OPTARG}"; exit 1 ;;
    esac
done

print_info() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$@"
    fi
}



if ! METADATA=$(curl -s -H Metadata:true "$METADATA_URL"); then
    echo "Could not connect to Azure IMDS. Exiting" >&2
    exit 1
fi

VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')
TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")

DIAG_DIR="$VM_ID.$TIMESTAMP"
rm -r "$DIAG_DIR" 2>/dev/null
mkdir $DIAG_DIR


####################################################################################################
# VM
####################################################################################################

mkdir "$DIAG_DIR/VM"

echo "$METADATA" >$DIAG_DIR/VM/metadata.json
dmesg -T > $DIAG_DIR/VM/dmesg.log
cp /var/log/waagent.log $DIAG_DIR/VM/waagent.log
lspci -vv >$DIAG_DIR/VM/lspci.txt
sh $(dirname "$0")/lsvmbus.sh -vv >$DIAG_DIR/VM/lsvmbus.log

####################################################################################################
# CPU
####################################################################################################
mkdir "$DIAG_DIR/CPU"
# numa_domains="$(numactl -H |grep available|cut -d' ' -f2)"
lscpu >"$DIAG_DIR/CPU/lscpu.txt"

####################################################################################################
# Memory
####################################################################################################


####################################################################################################
# Infiniband
####################################################################################################

mkdir "$DIAG_DIR/Infiniband"

if lspci | grep -iq MELLANOX; then
    print_info "Infiniband Device Detected"
    if type ibstat >/dev/null; then
        ibstat > $DIAG_DIR/Infiniband/ibstat.txt
        ibdev_info > $DIAG_DIR/Infiniband/ibdev_info.txt
    else
        print_info "No Infiniband Driver Detected"
    fi
fi

####################################################################################################
# Ethernet
####################################################################################################

####################################################################################################
# Nvidia GPU
####################################################################################################

mkdir "$DIAG_DIR/Nvidia"

# GPU-Specific
if lspci | grep -iq NVIDIA; then
    print_info "Nvidia Device Detected"
    if type nvidia-smi >/dev/null; then
        nvidia-smi -q --filename=$DIAG_DIR/nvidia-smi.txt --debug=$DIAG_DIR/nvidia-smi-debug.dbg
    else
        print_info "No Nvidia Driver Detected"
    fi
elif echo "$VM_SIZE" | grep -q '.*_N'; then
    print_info "Missing Nvidia Device"
fi

####################################################################################################
# AMD GPU
####################################################################################################


####################################################################################################
# Packaging Up
####################################################################################################

tar czf $DIAG_DIR.tar.gz $DIAG_DIR
echo "$DIAG_DIR.tar.gz"

####################################################################################################
# Clean Up
####################################################################################################
rm -r $DIAG_DIR

