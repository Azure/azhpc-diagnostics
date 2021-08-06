#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

SCRIPT_DIR="$( cd "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
PKG_ROOT="$(dirname "$SCRIPT_DIR")"
HPC_DIAG="$PKG_ROOT/src/gather_azhpc_vm_diagnostics.sh"

# BATS tests: this section should eventually absorb all tests
git submodule update --init # just in case, ensure BATS installation
"$SCRIPT_DIR/bats/bin/bats" "$SCRIPT_DIR" || exit 1

# these make sense as an associative array
# but hesitant to start using bash4 features
BASE_FILENAMES="
CPU/
CPU/lscpu.txt
VM/
VM/waagent.log
VM/dmesg.log
VM/lspci.txt
VM/lsvmbus.log
VM/ifconfig.txt
VM/sysctl.txt
VM/uname.txt
VM/dmidecode.txt
VM/lsmod.txt
VM/@(syslog|messages|journald.log)
transcript.log
hpcdiag.err"

NVIDIA_FILENAMES="Nvidia/nvidia-bug-report.log.gz
Nvidia/nvidia-smi-q.out
Nvidia/nvidia-smi.out
Nvidia/nvidia-debugdump.zip"

NVIDIA_EXT_FILENAMES="Nvidia/nvidia-vmext-status"

NVIDIA_FOLDER="Nvidia/"

DCGM_FILENAMES="Nvidia/dcgm-diag.log"

MEMORY_FILENAMES="Memory/
Memory/stream.txt"

INFINIBAND_FILENAMES="Infiniband/ibstat.txt
Infiniband/ibv_devinfo.txt"

INFINIBAND_EXT_FILENAMES="Infiniband/ib-vmext-status"

INFINIBAND_FOLDER="Infiniband/"


# Test Functions

nosudo_basic_script_test(){
    local output
    if ! output=$(bash "$HPC_DIAG" --no-update "$1" | tee /dev/stderr); then
        echo 'FAIL 1'
        overall_retcode=1
    elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        if [ "$(echo "$output" | wc -l)" -le 1 ]; then
            echo 'FAIL HELP'
            overall_retcode=1
            return 1
        else
            echo 'PASSED'
            return 0
        fi
    elif [ "$(echo "$output" | wc -l)" -ne 1 ]; then
        echo 'FAIL 2'
        overall_retcode=1
    else
        echo 'PASSED'
    fi
}

sudo_basic_script_test() {
    local script_args="$1"
    local additional_expected="$2"
    local additional_unexpected="$3"

    local retval=0

    local output
    output=$(yes | sudo bash "$HPC_DIAG" --no-update "$script_args") || retval=1
    echo "$output" 1>&2

    local tarball
    tarball=$(echo "$output" | grep -o '[^[:space:]]\+.tar.gz')
    if [ ! -s "$tarball" ]; then
        return 1
    fi

    local filenames
    filenames=$(tar xzvf "$tarball" | sed 's|^[^/]*/||g') || return 1

    local expected_patterns
    expected_patterns=$(cat <(echo "$BASE_FILENAMES") <(echo "$additional_expected") <(echo "$additional_unexpected") | sort | uniq -u)
    
    
    pushd "$(basename "$tarball" .tar.gz)" >/dev/null || return 1
    shopt -s extglob
    local expected_filenames
    for pattern in $expected_patterns; do
        if [ -e "$pattern" ]; then
            expected_filenames=$(printf '%s\n%s\n' "$expected_filenames" "$pattern")
        else
            retval=1
            echo "Could not find unique file for pattern $pattern"
        fi
    done
    shopt -u extglob
    popd >/dev/null || exit 1

    for filename in $filenames; do
        if [[ "$filename" =~ ^Nvidia/stats_.*$ ]] ||
           [[ "$filename" =~ ^Nvidia/nvvs.log$ ]] ||
           [[ "$filename" =~ ^Nvidia/bandwidthTest.*$ ]] ||
           [[ "$filename" =~ ^Infiniband/.* ]] ||
           [[ "$filename" =~ ^VM.* ]]; then
            continue # leave behavior for these undefined
        fi

        if ! echo "$expected_filenames" | grep -q "^$filename\$"; then
            retval=1
            echo "Found extra file: $filename"
        fi
    done

    rm -rf "$tarball" "$(basename "$tarball" .tar.gz)"

    if [ "$retval" -eq 0 ]; then
        echo 'PASSED'
    else
        echo 'FAILED'
    fi
    return "$retval"
}



# Read in options
options_list='infiniband,ib-ext,nvidia,nvidia-ext,dcgm,stream'
if ! PARSED_OPTIONS=$(getopt -n "$0" -o '' --long "$options_list"  -- "$@"); then
        echo "$HELP_MESSAGE"
        exit 1
fi
eval set -- "$PARSED_OPTIONS"
 
while [ "$1" != "--" ]; do
  case "$1" in
    --infiniband) INFINIBAND_PRESENT=true;;
    --ib-ext) INFINIBAND_EXT_PRESENT=true;;
    --nvidia) NVIDIA_PRESENT=true;;
    --nvidia-ext) NVIDIA_EXT_PRESENT=true;;
    --dcgm) DCGM_INSTALLED=true;;
    --stream) STREAM_ENABLED=true;;
  esac
  shift
done
shift

if [ "$INFINIBAND_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$INFINIBAND_FILENAMES"))
fi

if [ "$INFINIBAND_EXT_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$INFINIBAND_EXT_FILENAMES"))
fi

if [ "$INFINIBAND_EXT_PRESENT" = true ] ||
    [ "$INFINIBAND_PRESENT" = true ] ||
    [ -n "$IB_DEVICE_LIST" ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$INFINIBAND_FOLDER"))
fi

if [ "$NVIDIA_EXT_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$NVIDIA_EXT_FILENAMES"))
fi

if [ "$NVIDIA_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$NVIDIA_FILENAMES"))
    if [ "$DCGM_INSTALLED" = true ];then
        BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$DCGM_FILENAMES"))
    fi
fi

if [ "$NVIDIA_EXT_PRESENT" = true ] || [ "$NVIDIA_PRESENT" = true ];then
    BASE_FILENAMES=$(cat <(echo "$BASE_FILENAMES") <(echo "$NVIDIA_FOLDER"))
fi

overall_retcode=0

# zero-output runs
echo 'Testing without sudo'
if [ "$(whoami)" = root ]; then
    user=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    while compgen -u | grep "$user"; do
        user=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    done
    useradd --system --no-create-home "$user"
    tmp=$(mktemp)
    cp "$HPC_DIAG" "$tmp"
    chmod 777 "$tmp"
    output=$(sudo -u "$user" bash "$tmp" --no-update)
    retcode=$?
    rm "$tmp"
    userdel "$user"
else
    output=$(bash "$HPC_DIAG" --no-update)
    retcode=$?
fi
if [ $retcode -eq 0 ]; then
    echo 'FAILED'
    overall_retcode=1
else
    echo 'PASSED'
fi

HPC_DIAG_URL='https://raw.githubusercontent.com/Azure/azhpc-diagnostics/main/Linux/src/gather_azhpc_vm_diagnostics.sh'
main=$(mktemp)
curl -s "$HPC_DIAG_URL" > "$main"
corrupted=$(mktemp)
sed <"$HPC_DIAG" '/VERSION_INFO=/c VERSION_INFO=dummy' >"$corrupted"
echo 'Testing auto-update'
if [ "$(yes | bash "$corrupted" --version)" != "$(bash "$main" --version)" ]; then
    echo 'FAILED'
    overall_retcode=1
else
    echo 'PASSED'
fi

sed <"$HPC_DIAG" '/VERSION_INFO=/c VERSION_INFO=dummy' >"$tmp"
echo 'Testing auto-update disablement'
if [ "$(yes | bash "$tmp" --version --no-update)" != 'dummy' ]; then
    echo 'FAILED'
    overall_retcode=1
else
    echo 'PASSED'
fi

echo 'Testing with -V'
nosudo_basic_script_test -V

echo 'Testing with --version'
nosudo_basic_script_test --version

echo 'Testing with -h'
nosudo_basic_script_test -h

echo 'Testing with --help'
nosudo_basic_script_test --help

METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'
if ! curl -s -H Metadata:true --connect-timeout 1 "$METADATA_URL"; then 
    echo "Couldn't connect to Azure IMDS. Cutting tests short."
    exit 1
fi

# base version
echo 'Testing with sudo'
echo 'Testing with no options'
sudo_basic_script_test || overall_retcode=1

# raised mem level
echo 'Testing with --mem-level=1'
if [ "$STREAM_ENABLED" = true ];then
    sudo_basic_script_test --mem-level=1 "$MEMORY_FILENAMES" || overall_retcode=1
else
    sudo_basic_script_test --mem-level=1 || overall_retcode=1
fi

echo 'Testing with invalid arguments'
if yes | sudo bash "$HPC_DIAG" --mem-level=1 --offline 1>&2; then
    echo 'FAILED'
    overall_retcode=1
else
    echo 'PASSED'
fi

# raised gpu-level
echo 'Testing with --gpu-level=3'
sudo_basic_script_test --gpu-level=3 || overall_retcode=1

exit $overall_retcode