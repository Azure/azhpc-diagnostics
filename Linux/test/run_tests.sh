#!/bin/bash

BASE_FILENAMES="
CPU/
CPU/lscpu.txt
VM/
VM/waagent.log
VM/dmesg.log
VM/lspci.txt
VM/lsvmbus.log
VM/metadata.json"

NVIDIA_FILENAMES="Nvidia/
Nvidia/nvidia-smi.txt
Nvidia/nvidia-smi-debug.dbg"

DCGM_2_FILENAMES="Nvidia/dcgm-diag-2.log"
DCGM_3_FILENAMES="Nvidia/dcgm-diag-3.log"

MEMORY_FILENAMES="Memory/
Memory/stream.txt"

INFINIBAND_FILENAMES="Infiniband/
Infiniband/ibstat.txt
Infiniband/ibv_devinfo.txt"

sort_and_compare() {
    local a=$(echo "$1" | sort | grep -v 'Nvidia/stats_\|Nvidia/nvvs.log')
    local b=$(echo "$2" | sort | grep -v 'Nvidia/stats_\|Nvidia/nvvs.log')
    diff <(echo "$a") <(echo "$b")
}

SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
PKG_ROOT="$(dirname $SCRIPT_DIR)"
#set -x



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
output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" -V)
if [ $? -ne 0 ]; then
    echo 'FAIL'
    overall_retcode=1
elif [ $(echo "$output" | wc -l) -ne 1 ]; then
    echo 'FAIL'
    overall_retcode=1
fi

echo 'Testing with --version'
output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --version)
if [ $? -ne 0 ]; then
    echo 'FAIL'
    overall_retcode=1
elif [ $(echo "$output" | wc -l) -ne 1 ]; then
    echo 'FAIL'
    overall_retcode=1
fi

echo 'Testing with -h'
output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" -h)
if [ $? -ne 0 ]; then
    echo 'FAIL'
    overall_retcode=1
elif [ $(echo "$output" | wc -l) -le 1 ]; then
    echo 'FAIL'
    overall_retcode=1
fi

echo 'Testing with --help'
output=$(bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --help)
if [ $? -ne 0 ]; then
    echo 'FAIL'
    overall_retcode=1
elif [ $(echo "$output" | wc -l) -le 1 ]; then
    echo 'FAIL'
    overall_retcode=1
fi


# base version
echo 'Testing with no options'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh")
if [ $? -eq 0 ]; then
    tarball=$(echo "$output" | tail -1)
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES="$BASE_FILENAMES"
    if ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi

rm -f "$tarball"


# verbose version
echo 'Testing with -v'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" -v)
if [ $? -eq 0 ]; then
    tarball=$(echo "$output" | tail -1)
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES="$BASE_FILENAMES"
    if [ $(echo "$output" | wc -l) -le 2 ]; then
        echo 'FAIL'
        overall_retcode=1
    elif ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi

rm -f "$tarball"

echo 'Testing with --verbose'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --verbose)
if [ $? -eq 0 ]; then
    tarball=$(echo "$output" | tail -1)
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES="$BASE_FILENAMES"
    if [ $(echo "$output" | wc -l) -le 2 ]; then
        echo 'FAIL'
        overall_retcode=1
    elif ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi

rm -f "$tarball"

# suppressed output
echo 'Testing with -q'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" -q)
if [ $? -eq 0 ]; then
    vm_id=$(basename $(echo "$tarball" | grep -o '^[^.]*'))
    tarball="$PKG_ROOT/src/$(ls -c "$PKG_ROOT/src" | grep -m1 "$vm_id")"
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES="$BASE_FILENAMES"
    if [ $(echo "$output" | wc -l) -gt 1 ]; then
        echo 'FAIL'
        overall_retcode=1
    elif ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi

rm -f "$tarball"

echo 'Testing with --quiet'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --quiet)
if [ $? -eq 0 ]; then
    vm_id=$(basename $(echo "$tarball" | grep -o '^[^.]*'))
    tarball="$PKG_ROOT/src/$(ls -c "$PKG_ROOT/src" | grep -m1 "$vm_id")"
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES="$BASE_FILENAMES"
    if [ $(echo "$output" | wc -l) -gt 1 ]; then
        echo 'FAIL'
        overall_retcode=1
    elif ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi

rm -f "$tarball"

# raised mem level
echo 'Testing with --mem-level=1'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --mem-level=1)
if [ $? -eq 0 ]; then
    tarball=$(echo "$output" | tail -1)
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    EXPECTED_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$MEMORY_FILENAMES"))
    if ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi
rm -f "$tarball"

# raised gpu-level
echo 'Testing with --gpu-level=2'
output=$(sudo bash "$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh" --gpu-level=2)
if [ $? -eq 0 ]; then
    tarball=$(echo "$output" | tail -1)
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||')

    if [ "$DCGM_INSTALLED" = true ]; then
        EXPECTED_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$DCGM_3_FILENAMES"))
    else
        EXPECTED_FILENAMES="$BASE_FILENAMES"
    fi
    if ! sort_and_compare "$EXPECTED_FILENAMES" "$filenames"; then
        echo 'FAIL'
        overall_retcode=1
    fi
    rm -r $(basename "$tarball" .tar.gz)
else
    echo 'FAIL'
    overall_retcode=1
fi
rm -f "$tarball"

exit $overall_retcode