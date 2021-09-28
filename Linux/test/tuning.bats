#!/bin/usr/env bats
# Tests for VM metadata (IMDS) collection

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR/Memory"
    echo '1' > "$DIAG_DIR/Memory/zone_reclaim_mode"
    cp "$BATS_TEST_DIRNAME/samples/limits.good.conf" "$DIAG_DIR/Memory/limits.conf"
    mkdir -p "$DIAG_DIR/VM"
    grep '^SELINUX=' "$BATS_TEST_DIRNAME/samples/selinux.good" > "$DIAG_DIR/VM/selinux"
}

function teardown {
    rm -rf "$DIAG_DIR"
}

@test "flag bad zone reclaim mode" {
    echo '0' >"$DIAG_DIR/Memory/zone_reclaim_mode"
    run check_tuning
    assert_output --partial 'Set zone_reclaim_mode to 1'
}

@test "don't flag good zone reclaim mode" {
    echo '1' > "$DIAG_DIR/Memory/zone_reclaim_mode"
    run check_tuning
    refute_output --partial 'Set zone_reclaim_mode to 1'
}

@test "flag bad ulimit" {
    cp "$BATS_TEST_DIRNAME/samples/limits.bad.conf" "$DIAG_DIR/Memory/limits.conf"
    run check_tuning
    assert_output --partial 'Consider setting ulimit'

}

@test "don't flag good ulimit" {
    run check_tuning
    refute_output --partial 'Consider setting ulimit'
}

@test "flag active selinux" {
    grep '^SELINUX=' "$BATS_TEST_DIRNAME/samples/selinux.bad" > "$DIAG_DIR/VM/selinux"
    run check_tuning
    assert_output --partial 'Consider disabling selinux to avoid interfering with MPI'
}

@test "don't flag inactive selinux" {
    run check_tuning
    refute_output --partial 'Consider disabling selinux to avoid interfering with MPI'
}