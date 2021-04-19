#!/bin/usr/env bats
# Checks that our assumptions about CLI's like nvidia-smi still holde
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