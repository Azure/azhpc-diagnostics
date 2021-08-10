#!/bin/usr/env bats
# testing analysis of nvidia-smi outputs

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR/Nvidia"
    cp "$BATS_TEST_DIRNAME/samples/nvidia-smi-q.out" "$DIAG_DIR/Nvidia/nvidia-smi-q.out"
    grep -v 'infoROM is corrupted' "$BATS_TEST_DIRNAME/samples/nvidia-smi-inforom.out" >"$DIAG_DIR/Nvidia/nvidia-smi.out"
    
    SYSFS_PATH=$(mktemp -d)
    local DEVICES_PATH="$SYSFS_PATH/bus/vmbus/devices"
    for i in 1 2 a d; do
        mkdir -p "$DEVICES_PATH/00000000-0000-0000-0000-00000000000$i/pci000$i:00"
    done
}

function teardown {
    rm -rf "$DIAG_DIR" "$SYSFS_PATH"
}

@test "no dbe violations" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    run check_page_retirement

    assert_success
    assert_output --partial "Checking for GPUs over the page retirement threshold"
    refute_output --partial "BAD GPU"
}

@test "no missing gpus" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    
    run check_missing_gpus

    assert_success
    assert_output --partial "Checking for GPUs that don't appear in nvidia-smi"
    refute_output --partial "BAD GPU"
}

@test "no inforom corruption" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    
    run check_inforom

    assert_success
    assert_output --partial "Checking for GPUs with corrupted infoROM"
    refute_output --partial "BAD GPU"
}

@test "report bad gpu" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    run report_bad_gpu --index=2 --reason=reason

    assert_success
    assert_equal "${#lines[@]}" 1

    assert_line --index 0 --partial 'reason'
    assert_line --index 0 --partial '00000000-0000-0000-0000-00000000000a'
    assert_line --index 0 --partial '0000000000003'

    assert grep -q "$output" "$DIAG_DIR/transcript.log"
}

@test "page retirement - fail gracefully without nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command nvidia-smi

    run check_page_retirement
    assert_failure
    refute_output --partial "BAD GPU"
}

@test "missing gpus - fail gracefully without nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command nvidia-smi

    run check_missing_gpus
    assert_failure
    refute_output --partial "BAD GPU"
}

@test "inforom - fail gracefully without nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command nvidia-smi

    run check_inforom
    assert_failure
    refute_output --partial "BAD GPU"
}

@test "report_bad_gpu - fail gracefully without nvidia-smi" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command nvidia-smi

    run report_bad_gpu --index=2 --reason=reason
    assert_failure
    refute_output --partial "BAD GPU"
}

@test "detect dbe over threshold" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    sed -i 's/0,0000000000001,0x0001,0,0/0,0000000000001,0x0001,29,30/g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's/1,0000000000002,0x0002,0,0/1,0000000000002,0x0002,60,0/g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's/2,0000000000003,0x000A,0,0/2,0000000000003,0x000A,0,60/g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's/3,0000000000004,0x000D,0,0/3,0000000000004,0x000D,31,31/g' "$NVIDIA_SMI_QUERY_GPU_DATA"

    run check_page_retirement

    assert_success

    assert_line --index 1 --partial 'DBE(60)'
    assert_line --index 1 --partial '00000000-0000-0000-0000-000000000002'
    assert_line --index 1 --partial '0000000000002'

    assert_line --index 2 --partial 'DBE(60)'
    assert_line --index 2 --partial '00000000-0000-0000-0000-00000000000a'
    assert_line --index 2 --partial '0000000000003'

    assert_line --index 3 --partial 'DBE(62)'
    assert_line --index 3 --partial '00000000-0000-0000-0000-00000000000d'
    assert_line --index 3 --partial '0000000000004'

    assert_equal "${#lines[@]}" 4
}

@test "detect row remap failure" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    sed -i 's|\[N/A\],00000001:00:00.0|0,00000001:00:00.0|g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's|\[N/A\],00000002:00:00.0|1,00000002:00:00.0|g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's|\[N/A\],0000000A:00:00.0|0,0000000A:00:00.0|g' "$NVIDIA_SMI_QUERY_GPU_DATA"
    sed -i 's|\[N/A\],0000000D:00:00.0|1,0000000D:00:00.0|g' "$NVIDIA_SMI_QUERY_GPU_DATA"

    run check_page_retirement

    assert_success

    assert_line --index 1 --partial 'Row Remap Failure'
    assert_line --index 1 --partial '00000000-0000-0000-0000-000000000002'
    assert_line --index 1 --partial '0000000000002'

    assert_line --index 2 --partial 'Row Remap Failure'
    assert_line --index 2 --partial '00000000-0000-0000-0000-00000000000d'
    assert_line --index 2 --partial '0000000000004'

    assert_equal "${#lines[@]}" 3
}

@test 'detect inforom warnings' {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    echo "WARNING: infoROM is corrupted at gpu 0001:00:00.0" >>"$DIAG_DIR/Nvidia/nvidia-smi.out"
    echo "WARNING: infoROM is corrupted at gpu 000A:00:00.0" >>"$DIAG_DIR/Nvidia/nvidia-smi.out"

    run check_inforom

    assert_success

    assert_line --index 1 --partial 'infoROM Corrupted'
    assert_line --index 1 --partial '00000000-0000-0000-0000-000000000001'
    assert_line --index 1 --partial '0000000000001'

    assert_line --index 2 --partial 'infoROM Corrupted'
    assert_line --index 2 --partial '00000000-0000-0000-0000-00000000000a'
    assert_line --index 2 --partial '0000000000003'

    assert_equal "${#lines[@]}" 3
}

@test 'detect missing gpu' {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    mkdir -p "$DIAG_DIR/VM"

    sed -i '/2,0000000000003,0x000A,0,0/d' "$NVIDIA_SMI_QUERY_GPU_DATA"

    run check_missing_gpus
    assert_output --partial 'GPU not coming up in nvidia-smi'
    assert_output --partial 'BAD GPU'
    assert_output --partial '00000000-0000-0000-0000-00000000000a'
    assert_output --partial 'UNKNOWN'
}
