#!/bin/usr/env bats
# Tests for utilities used for VM sizes

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update
}

@test "is_infiniband_sku" {
    run is_infiniband_sku Standard_NC24rs
    assert_success
    refute_output

    run is_infiniband_sku Standard_NC6
    assert_failure
    refute_output

    run is_infiniband_sku Standard_ND96asr_v4
    assert_success
    refute_output

    run is_infiniband_sku Standard_NV32as_v4
    assert_failure
    refute_output

    run is_infiniband_sku Standard_NV48s_v3
    assert_failure
    refute_output

    run is_infiniband_sku Standard_HB60rs
    assert_success
    refute_output

    run is_infiniband_sku Standard_NP40s
    assert_failure
    refute_output

    run is_infiniband_sku Standard_A2
    assert_failure
    refute_output
}

@test "is_nvidia_sku" {
    run is_nvidia_sku Standard_NC24rs
    assert_success
    refute_output

    run is_nvidia_sku Standard_NC6
    assert_success
    refute_output

    run is_nvidia_sku Standard_ND96asr_v4
    assert_success
    refute_output

    run is_nvidia_sku Standard_NV32as_v4
    assert_failure
    refute_output

    run is_nvidia_sku Standard_NV48s_v3
    assert_success
    refute_output

    run is_nvidia_sku Standard_HB60rs
    assert_failure
    refute_output

    run is_nvidia_sku Standard_NP40s
    assert_failure
    refute_output

    run is_nvidia_sku Standard_A2
    assert_failure
    refute_output
}

@test "is_nvidia_compute_sku" {
    run is_nvidia_compute_sku Standard_NC24rs
    assert_success
    refute_output

    run is_nvidia_compute_sku Standard_NC6
    assert_success
    refute_output

    run is_nvidia_compute_sku Standard_ND96asr_v4
    assert_success
    refute_output

    run is_nvidia_compute_sku Standard_NV32as_v4
    assert_failure
    refute_output

    run is_nvidia_compute_sku Standard_NV48s_v3
    assert_failure
    refute_output

    run is_nvidia_compute_sku Standard_HB60rs
    assert_failure
    refute_output

    run is_nvidia_compute_sku Standard_NP40s
    assert_failure
    refute_output

    run is_nvidia_compute_sku Standard_A2
    assert_failure
    refute_output
}

@test "is_vis_sku" {
    run is_vis_sku Standard_NC24rs
    assert_failure
    refute_output

    run is_vis_sku Standard_NC6
    assert_failure
    refute_output

    run is_vis_sku Standard_ND96asr_v4
    assert_failure
    refute_output

    run is_vis_sku Standard_NV32as_v4
    assert_success
    refute_output

    run is_vis_sku Standard_NV48s_v3
    assert_success
    refute_output

    run is_vis_sku Standard_HB60rs
    assert_failure
    refute_output

    run is_vis_sku Standard_NP40s
    assert_failure
    refute_output

    run is_vis_sku Standard_A2
    assert_failure
    refute_output
}

@test "is_amd_gpu_sku" {
    run is_amd_gpu_sku Standard_NC24rs
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_NC6
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_ND96asr_v4
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_NV32as_v4
    assert_success
    refute_output

    run is_amd_gpu_sku Standard_NV48s_v3
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_HB60rs
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_NP40s
    assert_failure
    refute_output

    run is_amd_gpu_sku Standard_A2
    assert_failure
    refute_output
}
