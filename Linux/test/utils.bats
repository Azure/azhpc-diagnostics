#!/bin/usr/env bats
# testing various utility functions

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update
}

@test "float_lt" {
    run float_lt 16.2 17.8
    assert_success
    
    run float_lt 20 16
    assert_failure
    
    run float_lt 19.3 19.3
    assert_failure
    
    run float_lt -19.3 18.0
    assert_success
}