#!/bin/usr/env bats
# Tests for infiniband diagnostic collection

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR"

    SYSFS_PATH=$(mktemp -d)
    
    IB_DEVICES_PATH="$SYSFS_PATH/class/infiniband"
    mkdir -p "$IB_DEVICES_PATH/mlx5_ib0/ports/1/pkeys"
    echo 0xffff > "$IB_DEVICES_PATH/mlx5_ib0/ports/1/pkeys/0"
    echo 0x0001 > "$IB_DEVICES_PATH/mlx5_ib0/ports/1/pkeys/1"
}

function teardown {
    rm -rf "$DIAG_DIR" "$SYSFS_PATH"
}

@test "Confirm that pkeys get collected" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    run run_infiniband_diags
    assert_success

    run cat "$DIAG_DIR/Infiniband/mlx5_ib0/pkeys/0"
    assert_success
    assert_output 0xffff

    run cat "$DIAG_DIR/Infiniband/mlx5_ib0/pkeys/1"
    assert_success
    assert_output 0x0001
}

@test "Confirm that pkeys get collected even when \$DIAG_DIR needs resolving" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    # introduce some dots to the DIAG_DIR path without changing it
    DOTDOTS_TO_ROOT=$(pwd | sed 's/[^/]\+/../g' | rev)
    DIAG_DIR="$DOTDOTS_TO_ROOT$(realpath $DIAG_DIR)"

    run run_infiniband_diags
    assert_success

    run cat "$DIAG_DIR/Infiniband/mlx5_ib0/pkeys/0"
    assert_success
    assert_output 0xffff

    run cat "$DIAG_DIR/Infiniband/mlx5_ib0/pkeys/1"
    assert_success
    assert_output 0x0001
}

@test "Confirm that ib tools get run" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    run run_infiniband_diags
    assert_success

    run cat "$DIAG_DIR/Infiniband/ibstatus.out"
    assert_success
    assert_output

    run cat "$DIAG_DIR/Infiniband/ibstat.out"
    assert_success
    assert_output

    run cat "$DIAG_DIR/Infiniband/ibv_devinfo.out"
    assert_success
    assert_output "full output"
}

@test "Confirm that lack of ibstatus is noticed" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    hide_command ibstatus

    run run_infiniband_diags
    assert_success

    assert_output --partial "No Infiniband Driver Detected"

    refute [ -f "$DIAG_DIR/Infiniband/ibstatus.out" ]
    refute [ -f "$DIAG_DIR/Infiniband/ibstat.out" ]
    refute [ -f "$DIAG_DIR/Infiniband/ibv_devinfo.out" ]
}

@test "Confirm that lack of ibstat is noticed" {
    . "$BATS_TEST_DIRNAME/mocks.bash"

    hide_command ibstat

    run run_infiniband_diags
    assert_success

    assert_output --partial "ibstat not found"

    assert [ -f "$DIAG_DIR/Infiniband/ibstatus.out" ]
    refute [ -f "$DIAG_DIR/Infiniband/ibstat.out" ]
    assert [ -f "$DIAG_DIR/Infiniband/ibv_devinfo.out" ]
}

@test "Confirm that ib-vmext-status gets collected" {
    local dir_exists
    if [ -d /var/log/azure ]; then
        dir_exists=true
    else
        dir_exists=false
        mkdir -p /var/log/azure
    fi
    local file_exists
    if [ -f /var/log/azure/ib-vmext-status ]; then
        file_exists=true
    else
        file_exists=false
        touch /var/log/azure/ib-vmext-status
    fi

    run run_infiniband_diags
    assert_success

    assert [ -f "$DIAG_DIR/Infiniband/ib-vmext-status" ]

    if [ "$file_exists" == false ]; then
        rm /var/log/azure/ib-vmext-status
    fi
    if [ "$dir_exists" == false ]; then
        rm -r /var/log/azure
    fi
}

@test "Confirm that lack of pkeys is noticed" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    run_infiniband_diags

    run check_pkeys
    refute_output

    rm "$DIAG_DIR/Infiniband/mlx5_ib0/pkeys/0"
    run check_pkeys
    assert_output --partial "Could not find pkey 0 for device mlx5_ib0"
    refute_output --partial "Could not find pkey 1 for device mlx5_ib0"
}

@test "Confirm ENDURE IB files collection" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    mkdir -p "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1"
    cp "$BATS_TEST_DIRNAME/samples/endure/rate" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1"
    cp "$BATS_TEST_DIRNAME/samples/endure/state" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1"
    cp "$BATS_TEST_DIRNAME/samples/endure/phys_state" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1"

    hide_command ibstat
    VM_SIZE='Standard_H16r'
    run run_infiniband_diags
    assert cmp "$BATS_TEST_DIRNAME/samples/endure/rate" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1/rate"
    assert cmp "$BATS_TEST_DIRNAME/samples/endure/state" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1/state"
    assert cmp "$BATS_TEST_DIRNAME/samples/endure/phys_state" "$SYSFS_PATH/class/infiniband/mlx4_0/ports/1/phys_state"

    assert_success

}
