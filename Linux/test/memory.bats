#!/bin/usr/env bats
# Tests for VM metadata (IMDS) collection

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    ETC_PATH=$(mktemp -d)
    mkdir -p "$ETC_PATH/security"
    echo 'dummy limits' > "$ETC_PATH/security/limits.conf"
    PROC_PATH=$(mktemp -d)
    mkdir -p $PROC_PATH/sys/vm
    echo 'dummy zone reclaim' > $PROC_PATH/sys/vm/zone_reclaim_mode
}

function teardown {
    rm -rf "$DIAG_DIR"
}

@test "Confirm limits.conf collection" {
    function run_stream {
        true
    }

    run run_memory_diags
    assert_success
    run cat "$DIAG_DIR/Memory/limits.conf"
    assert_output 'dummy limits'
}

@test "Confirm zone reclaim mode collection" {
    function run_stream {
        true
    }

    run run_memory_diags
    assert_success
    run cat "$DIAG_DIR/Memory/zone_reclaim_mode"
    assert_output 'dummy zone reclaim'

}

@test "Confirm run_stream getting called" {
    function run_stream {
        true
    }
    MEM_LEVEL=1

    run run_memory_diags
    assert_success
    assert_output --partial 'Running Memory Performance Test'
}

@test "Confirm run_stream getting skipped" {
    function run_stream {
        true
    }
    MEM_LEVEL=0

    run run_memory_diags
    assert_success
    refute_output --partial 'Running Memory Performance Test'
}