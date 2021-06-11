#!/bin/usr/env bats
# Checks that our assumptions about CLI's like nvidia-smi still hold
# i.e. fail if a tool's output has changed to be incompatible with our parsing

NVIDIA_PCI_ID=10de

function setup() {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    GPU_COUNT=$(lspci -d "$NVIDIA_PCI_ID:" | wc -l)
}

@test "Confirm that nvidia-smi dbe query is still compatible" {
    if ! command -v nvidia-smi >/dev/null; then
        skip "nvidia-smi not installed"
    fi
    run nvidia-smi --query-gpu=retired_pages.sbe,retired_pages.dbe --format=csv,noheader

    assert_success

    assert_equal "${#lines[@]}" "$GPU_COUNT"

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

    assert_equal "${#lines[@]}" "$GPU_COUNT"

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

    assert_equal "${#lines[@]}" "$GPU_COUNT"

    for i in "${!lines[@]}"; do
        assert_line --index $i --regexp '^[0-9]{13}$'
    done
}

@test "Confirm that one of the known syslog sources is available" {
    assert [ -f /var/log/syslog ] || 
            [ -f /var/log/messages ] || 
            systemctl is-active systemd-journald >/dev/null 2>/dev/null && command -v journalctl >/dev/null
}

SYSLOG_MESSAGE_PATTERN='^[A-Z][a-z]{2} [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [^ ]+ [^:]+:'

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
