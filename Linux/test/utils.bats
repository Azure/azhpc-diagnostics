#!/bin/usr/env bats
# testing various utility functions

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update
}

@test "float_lt" {
    run float_op 16.2 '<' 17.8
    assert_success
    
    run float_op 20 '<' 16
    assert_failure
    
    run float_op 19.3 '<' 19.3
    assert_failure
    
    run float_op -19.3 '<' 18.0
    assert_success
}

@test "float_le" {
    run float_op 16.2 '<=' 17.8
    assert_success
    
    run float_op 20 '<=' 16
    assert_failure
    
    run float_op 19.3 '<=' 19.3
    assert_success
    
    run float_op -19.3 '<=' 18.0
    assert_success
}

@test "float_gt" {
    run float_op 16.2 '>' 17.8
    assert_failure
    
    run float_op 20 '>' 16
    assert_success
    
    run float_op 19.3 '>' 19.3
    assert_failure
    
    run float_op -19.3 '>' 18.0
    assert_failure
}

@test "float_ge" {
    run float_op 16.2 '>=' 17.8
    assert_failure
    
    run float_op 20 '>=' 16
    assert_success
    
    run float_op 19.3 '>=' 19.3
    assert_success
    
    run float_op -19.3 '>=' 18.0
    assert_failure
}

@test "float_eq" {
    run float_op 0 == 0
    assert_success

    run float_op -4 == -4
    assert_success

    run float_op 4 == 2
    assert_failure
    
    run float_op 3.2 == 3
    assert_failure

    run float_op 1.0 == 1
    assert_success
}

@test "float_ne" {
    run float_op 0 != 0
    assert_failure

    run float_op -4 != -4
    assert_failure

    run float_op 4 != 2
    assert_success

    run float_op 3.2 != 3
    assert_success

    run float_op 1.0 != 1
    assert_failure
}

@test "float_add" {
    run float_op 1 + 1
    assert_output 2.000000

    run float_op -1 + 1
    assert_output 0.000000

    run float_op 0.3 + 0.6
    assert_output 0.900000
}

@test "float_sub" {
    run float_op 1 - 1
    assert_output 0.000000

    run float_op 1 - -1
    assert_output 2.000000

    run float_op 0.3 - 0.6
    assert_output -0.300000
}

@test "float_mul" {
    run float_op 1 '*' 1
    assert_output 1.000000

    run float_op 1 '*' -1
    assert_output -1.000000

    run float_op 0.3 '*' 0.6
    assert_output 0.180000
}

@test "float_div" {
    run float_op 1 '/' 1
    assert_output 1.000000

    run float_op 1 '/' -1
    assert_output -1.000000

    run float_op 0.3 '/' 0.6
    assert_output 0.500000
}
