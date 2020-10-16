#!/bin/bash

BASE_FILENAMES="
CPU/
CPU/lscpu.txt
VM/
VM/waagent.log
VM/dmesg.log
VM/lspci.txt
VM/lsvmbus.log
VM/metadata.json
VM/ifconfig.txt
VM/sysctl.txt
VM/uname.txt
VM/dmidecode.txt
VM/syslog"

NVIDIA_FILENAMES="Nvidia/
Nvidia/nvidia-smi.txt
Nvidia/nvidia-smi-debug.dbg"

DCGM_2_FILENAMES="Nvidia/dcgm-diag-2.log"
DCGM_3_FILENAMES="Nvidia/dcgm-diag-3.log"

MEMORY_FILENAMES="Memory/
Memory/stream.txt"

INFINIBAND_FILENAMES="Infiniband/
Infiniband/ibstat.txt
Infiniband/ibv_devinfo.txt
Infiniband/pkeys0.txt"

sort_and_compare() {
    local a=$(echo "$1" | sort | grep -v 'Nvidia/stats_\|Nvidia/nvvs.log')
    local b=$(echo "$2" | sort | grep -v 'Nvidia/stats_\|Nvidia/nvvs.log')
    diff <(echo "$a") <(echo "$b")
}

SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
PKG_ROOT="$(dirname $SCRIPT_DIR)"
#set -x

# Get the VM_ID to determine the test folders
METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'

METADATA=$(curl -s -H Metadata:true "$METADATA_URL") || 
    failwith "Couldn't connect to Azure IMDS."

VM_ID=$(echo "$METADATA" | grep -o '"vmId":"[^"]*"' | cut -d: -f2 | tr -d '"')

# Test Functions

nosudo_basic_script_test(){
    local output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" $1)
    if [ $? -ne 0 ]; then
        echo 'FAIL 1'
        overall_retcode=1
    elif [ "$1" = "-h" -o "$1" = "--help" ]; then
        if [ $(echo "$output" | wc -l) -le 1 ]; then
            echo 'FAIL HELP'
            overall_retcode=1
            return 1
        else
            echo 'PASSED'
            return 0
        fi
    elif [ $(echo "$output" | wc -l) -ne 1 ]; then
        echo 'FAIL 2'
        overall_retcode=1
    else
        echo 'PASSED'
    fi
}

sudo_basic_script_test(){
    if [ "$#" -ne 1 ]; then
        output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh")
    else
        output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" $1)
    fi

    if [ $? -eq 0 ]; then
        tarball=$(find . -type f -iname "$VM_ID.*.tar.gz" | sort -r | head -n 1)
        filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

        EXPECTED_FILENAMES="$BASE_FILENAMES"
        # If second argument is given then add those files
        if [ "$#" -eq 2 ]; then
            EXPECTED_FILENAMES=$(cat <(echo "$2"))
        fi
        
        # Check the output line count for verbose and quiet arguments
        if [ "$1" = "-v"  -o "$1" = "--verbose" ]; then
            if [ $(echo "$output" | wc -l) -le 2 ]; then
                echo 'FAIL'
                overall_retcode=1
            fi
        elif [ "$1" = "-q" -o "$1" = "--quiet" ]; then
            if [ $(echo "$output" | wc -l) -gt 1 ]; then
                echo 'FAIL'
                overall_retcode=1
                return 1
            fi
        fi
        if ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
            echo 'FAIL'
            overall_retcode=1
        else
            echo 'PASSED'
        fi
        rm -r $(basename "$tarball" .tar.gz)
    else
        echo 'FAIL'
        overall_retcode=1
    fi

    rm -f "$tarball"
}



# Read in options
PARSED_OPTIONS=$(getopt -n "$0" -o '' --long "infiniband,nvidia,no-lsvmbus,dcgm"  -- "$@")
if [ "$?" -ne 0 ]; then
        echo "$HELP_MESSAGE"
        exit 1
fi
eval set -- "$PARSED_OPTIONS"
 
while [ "$1" != "--" ]; do
  case "$1" in
    --infiniband) INFINIBAND_PRESENT=true;;
    --nvidia) NVIDIA_PRESENT=true;;
    --dcgm) DCGM_INSTALLED=true;;
    --no-lsvmbus) NO_LSVMBUS=true;;
  esac
  shift
done
shift

if [ "$NO_LSVMBUS" = true ]; then
    BASE_FILENAMES=$(echo "$BASE_FILENAMES" | grep -v lsvmbus)
fi
BASE_FILENAMES="$BASE_FILENAMES"

if [ "$INFINIBAND_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$INFINIBAND_FILENAMES"))
fi

if [ "$NVIDIA_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$NVIDIA_FILENAMES"))
    if [ "$DCGM_INSTALLED" = true ];then
        BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$DCGM_2_FILENAMES"))
    fi
fi

overall_retcode=0



# zero-output runs
echo 'Testing without sudo'
output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh")
if [ $? -ne 1 ]; then
    echo 'FAIL'
    overall_retcode=1
fi

echo 'Testing with -V'
nosudo_basic_script_test -V

echo 'Testing with --version'
nosudo_basic_script_test --version

echo 'Testing with -h'
nosudo_basic_script_test -h

echo 'Testing with --help'
nosudo_basic_script_test --help

# base version
echo 'Testing with sudo'
echo 'Testing with no options'
sudo_basic_script_test

# verbose version
echo 'Testing with -v'
sudo_basic_script_test -v

echo 'Testing with --verbose'
sudo_basic_script_test --verbose

# suppressed output
echo 'Testing with -q'
sudo_basic_script_test -q

echo 'Testing with --quiet'
sudo_basic_script_test --quiet

# raised mem level
echo 'Testing with --mem-level=1'
sudo_basic_script_test --mem-level=1 $MEMORY_FILENAMES

# raised gpu-level
echo 'Testing with --gpu-level=2'
sudo_basic_script_test --gpu-level=2 $DCGM_3_FILENAMES

# output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --gpu-level=2)
# if [ $? -eq 0 ]; then
#     tarball=$(echo "$output" | tail -1)
#     filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

#     if [ "$DCGM_INSTALLED" = true ]; then
#         EXPECTED_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$DCGM_3_FILENAMES"))
#     else
#         EXPECTED_FILENAMES="$BASE_FILENAMES"
#     fi
#     if ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
#         echo 'FAIL'
#         overall_retcode=1
#     fi
#     rm -r $(basename "$tarball" .tar.gz)
# else
#     echo 'FAIL'
#     overall_retcode=1
# fi
# rm -f "$tarball"

exit $overall_retcode