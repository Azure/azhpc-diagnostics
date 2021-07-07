#!/bin/usr/env bats
# testing analysis of lspci outputs

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR/Nvidia"
    cp "$BATS_TEST_DIRNAME/samples/nvidia-smi-q.out" "$DIAG_DIR/Nvidia/nvidia-smi-q.out"
    grep -v 'infoROM is corrupted' "$BATS_TEST_DIRNAME/samples/nvidia-smi-inforom.out" >"$DIAG_DIR/Nvidia/nvidia-smi.out"

    SAVED_DEVICES_PATH="$DEVICES_PATH"
    DEVICES_PATH=$(mktemp -d)
    for i in {1..4}; do
        mkdir -p "$DEVICES_PATH/00000000-0000-0000-0000-00000000000$i/pci000$i:00"
    done
}

@test "lspci bandwidth - fail gracefully without nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command nvidia-smi
    MOCK_LNKSTA[0]="\tLnkSta: Port #1, Speed 8GT/s, Width x16"

    run check_pci_bandwidth
    assert_success
    assert_output --partial "BAD GPU"
    assert_output --partial "PCIe link not showing expected performance"
    assert_output --partial "UNKNOWN"
}

@test "check_pci_bandwidth" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    run check_pci_bandwidth
    assert_success
    refute_output
}

@test "lspci bandwidth (low speed) - get serial with nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    MOCK_LNKSTA[0]="\tLnkSta: Port #1, Speed 8GT/s, Width x16"

    run check_pci_bandwidth
    assert_success
    assert_output --partial "BAD GPU"
    assert_output --partial "PCIe link not showing expected performance"
    refute_output --partial "UNKNOWN"
}

@test "lspci bandwidth (low width) - get serial with nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    MOCK_LNKSTA[0]="\tLnkSta: Port #1, Speed 16GT/s, Width x8"

    run check_pci_bandwidth
    assert_success
    assert_output --partial "BAD GPU"
    assert_output --partial "PCIe link not showing expected performance"
    refute_output --partial "UNKNOWN"
}
