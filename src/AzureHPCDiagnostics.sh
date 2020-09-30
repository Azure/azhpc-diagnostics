#!/bin/bash
# Azure HPC Diagnostics Tool
# Gathers Diagnostic info from guest VM
# resulting files:
# - dmesg.txt
# - ibstat.txt
# - lspci.txt
# - os-release.txt
# - lsvmbus.txt
# - nvidia-smi.txt (human-readable)
# - nvidia-smi-debug.dbg (only Nvidia can read)
#
# Dependencies:
# - curl
# - lsvmbus.sh
# Outputs:
# - name of tarball

optstring=":v"

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

#TODO what to do if dir already exists
TIMESTAMP=$(date -u +"%F.UTC%H.%M.%S")


# gather metadata
METADATA_URL="http://169.254.169.254/metadata/instance?api-version=2017-12-01"
METADATA=$(curl -s -H Metadata:true "$METADATA_URL" --connect-timeout 5)
if [ "$?" -ne "0" ]; then
    echo "Could not connect to Azure IMDS. Exiting" >&2
    exit 1
fi

VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')


DIAG_DIR="$VM_ID.$TIMESTAMP"
mkdir $DIAG_DIR || { echo "Failed to make diag dir $DIAG_DIR. Exiting" >&2; exit 1; }
echo "$METADATA" >$DIAG_DIR/metadata.json

# Detect VM Size
case $(echo $VM_SIZE | grep -o '_[NH][CBDV]\?' | tr -d _) in
        NC) print_info "GPU Compute VM Size Detected"
                ;;
        ND) print_info "GPU Deep Learning VM Size Detected"
                ;;
        NV) print_info "GPU Visualization VM Size Detected"
                ;;
        HC) print_info "HPC VM Size Detected"
                ;;
        H) print_info "HPC VM Size Detected"
                ;;
        HB) print_info "HPC VM Size Detected"
                ;;
        *) print_info "Non-HPC VM Size Detected"
                ;;
esac


# OS info
cat /etc/os-release > $DIAG_DIR/os-release.txt

# Kernel Logs
dmesg -T > $DIAG_DIR/dmesg.txt

# Device Info
lspci -vv >$DIAG_DIR/lspci.txt
sh $(dirname "$0")/lsvmbus.sh -vv >$DIAG_DIR/lsvmbus.txt


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

# H-Series VM
if lspci | grep -iq MELLANOX; then
    print_info "Infiniband Device Detected"
    if type ibstat >/dev/null; then
        ibstat > $DIAG_DIR/ibstat.txt
    else
        print_info "No Infiniband Driver Detected"
    fi
fi

# print_info "zipping all diagnostic info into file: $DIAG_DIR.tar"
tar czf $DIAG_DIR.tar.gz $DIAG_DIR

# cleanup
rm -r $DIAG_DIR

echo "$DIAG_DIR.tar.gz"