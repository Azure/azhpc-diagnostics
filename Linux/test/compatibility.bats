#!/bin/usr/env bats
# Checks that our assumptions about CLI's like nvidia-smi still hold
# i.e. fail if a tool's output has changed to be incompatible with our parsing

NVIDIA_PCI_ID=10de
SYSLOG_MESSAGE_PATTERN='^[A-Z][a-z]{2} [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [^ ]+ [^:]+:'

function setup() {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
}

@test "Confirm that nvidia-smi dbe query is still compatible" {
    if ! command -v nvidia-smi >/dev/null; then
        skip "nvidia-smi not installed"
    fi
    run nvidia-smi --query-gpu=retired_pages.sbe,retired_pages.dbe --format=csv,noheader

    assert_success

    for i in "${!lines[@]}"; do
        assert_line --index $i --regexp '^[0-9]+, [0-9]+$'
    done
}

@test "Confirm that nvidia-smi pci.domain query is still compatible" {
    if ! command -v nvidia-smi >/dev/null; then
        skip "nvidia-smi not installed"
    fi
    run nvidia-smi --query-gpu=pci.domain --format=csv,noheader

    assert_success

    for i in "${!lines[@]}"; do
        assert_line --index $i --regexp '^0x[0-9A-F]{4,}$'
    done
}

@test "Confirm that nvidia-smi serial query is still compatible" {
    if ! command -v nvidia-smi >/dev/null; then
        skip "nvidia-smi not installed"
    fi
    run nvidia-smi --query-gpu=serial --format=csv,noheader

    assert_success

    for i in "${!lines[@]}"; do
        assert_line --index $i --regexp '^[0-9]{13}$'
    done
}

@test "Confirm that one of the known syslog sources is available" {
    if grep -q WSL /proc/sys/kernel/osrelease; then
        skip "running under wsl"
    fi
    assert [ -f /var/log/syslog ] || 
            [ -f /var/log/messages ] || 
            systemctl is-active systemd-journald >/dev/null 2>/dev/null && command -v journalctl >/dev/null
}

@test "Confirm that /var/log/syslog entries are formatted as expected" {
    if ! [ -s /var/log/syslog ]; then
        skip "No /var/log/syslog"
    fi
    run grep -Eq "$SYSLOG_MESSAGE_PATTERN" /var/log/syslog
    assert_success
}

@test "Confirm that /var/log/messages entries are formatted as expected" {
    if ! [ -s /var/log/messages ]; then
        skip "No /var/log/messages"
    fi
    run grep -Eq "$SYSLOG_MESSAGE_PATTERN" /var/log/messages
    assert_success
}

@test "Confirm that journald entries are formatted as expected" {
    if ! systemctl is-active systemd-journald >/dev/null 2>/dev/null || ! command -v journalctl >/dev/null; then
        skip "No journald"
    fi
    local tmp=$(mktemp)
    journalctl > "$tmp"
    run grep -Eq "$SYSLOG_MESSAGE_PATTERN" "$tmp"
    assert_success
}

@test "Confirm that lspci prints one non-indented line per device" {
    if [ $(lspci | wc -l) -eq 0 ]; then
        skip "no pci devices present"
    fi
    run lspci -mD
    assert_success
    assert_output --regexp '^[0-9a-f]{4}:.*'
    refute_output --regexp '^[A-Z]'
}

@test "Confirm that lspci GPU query matches expected count for VM size" {
    METADATA_URL='http://169.254.169.254/metadata/instance?api-version=2020-06-01'
    if ! METADATA=$(curl --connect-timeout 1 -s -H Metadata:true "$METADATA_URL"); then
        skip "Not on an azure vm"
    fi
    VM_SIZE=$(echo "$METADATA" | grep -o '"vmSize":"[^"]*"' | cut -d: -f2 | tr -d '"')
    core_count=$(echo $VM_SIZE | cut -d_ -f2 | grep -o '[[:digit:]]\+')
    case "$VM_SIZE" in
        Standard_NC6|Standard_NC12|Standard_NC24|Standard_NC24r) GPU_COUNT=$(( core_count / 6 ));;
        Standard_NC*v2) GPU_COUNT=$(( core_count / 6 ));;
        Standard_NC*T4_v3) GPU_COUNT=$(( (core_count + 15) / 16 ));; # round up
        Standard_NC*v3) GPU_COUNT=$(( core_count / 6 ));;
        Standard_ND6s|Standard_ND12s|Standard_ND24s|Standard_ND24rs) GPU_COUNT=$(( core_count / 6 ));;
        Standard_ND40rs_v2|Standard_ND96asr_v4) GPU_COUNT=8;;
        Standard_N*) skip "unknown gpu size $VM_SIZE";;
        *) GPU_COUNT=0;;
    esac
    assert_equal $(lspci -d "$NVIDIA_PCI_ID:" | wc -l) $GPU_COUNT
}