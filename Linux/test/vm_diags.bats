#!/bin/usr/env bats
# Tests for VM metadata (IMDS) collection

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR"
}

function teardown {
    rm -rf "$DIAG_DIR"
}

@test "Check that metadata is sucessfully scrubbed" {
    with_pipe() {
        cat "$BATS_TEST_DIRNAME/samples/metadata.json" | scrub_metadata
    }

    run with_pipe
    assert_output

    refute_output --partial 'hpcvm'
    refute_output --partial '"admin"'
    refute_output --partial 'ssh-rsa 0'
    refute_output --partial 'ssh-rsa 1'
    refute_output --partial 'hpcuser'
    refute_output --partial 'hpcdiag-samples'
    refute_output --partial 'mytag:true'
    refute_output --partial '"0.0.0.0"'
}
