#!/bin/usr/env bats
# testing collection of nvidia diagnostics

CUDA_PATH=/usr/local/cuda/samples/1_Utilities/bandwidthTest

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load ../src/gather_azhpc_vm_diagnostics.sh --no-update

    DIAG_DIR=$(mktemp -d)
    CUDA_SAMPLE_BW_DIR=$(mktemp -d)

    function make {
        if ! PARSED_OPTIONS=$(getopt -n "$0" -o C: --long 'directory:' -- "$@"); then
            return 1
        fi
        eval set -- "$PARSED_OPTIONS"
        local changed_dir

        while [ "$1" != "--" ]; do
            case "$1" in
                -C|--directory) shift; changed_dir=true; pushd "$1" || return 1;;
            esac
            shift
        done
        
        if [ "$1" == clean ]; then
            rm ./bandwidthTest
            touch ./make-cleaned
        else
            echo '#!/bin/bash' >./bandwidthTest
            echo "echo 'CUDA bandwidth result goes here'" >>./bandwidthTest
            chmod 700 ./bandwidthTest
            touch ./make-built
        fi

        if [ "$changed_dir" == true ]; then
            popd
        fi
    }
}

function teardown {
    rm -rf "$DIAG_DIR"
}

@test "get_gpu_numa" {
    run get_gpu_numa Standard_ND96asr_v4 -1
    assert_failure
    refute_output

    run get_gpu_numa Standard_ND96asr_v4 0
    assert_success
    assert_output 0
    
    run get_gpu_numa Standard_ND96asr_v4 3
    assert_success
    assert_output 1
    
    run get_gpu_numa Standard_ND96asr_v4 7
    assert_success
    assert_output 3
    
    run get_gpu_numa Standard_ND96asr_v4 8
    assert_failure
    refute_output
    
    run get_gpu_numa Standard_ND40rs_v2 0
    assert_failure
    refute_output
}

@test "compile cuda samples" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    function make {
        if [ "$2" == clean ]; then
            rm "$CUDA_SAMPLE_BW_DIR/bandwidthTest"
            touch "$CUDA_SAMPLE_BW_DIR/make-cleaned"
        else
            echo '#!/bin/bash' >"$CUDA_SAMPLE_BW_DIR/bandwidthTest"
            echo "echo 'CUDA bandwidth result goes here'" >>"$CUDA_SAMPLE_BW_DIR/bandwidthTest"
            chmod 700 "$CUDA_SAMPLE_BW_DIR/bandwidthTest"
            touch "$CUDA_SAMPLE_BW_DIR/make-built"
        fi
    }

    run run_cuda_bandwidth_test
    assert [ -f "$CUDA_SAMPLE_BW_DIR/make-built" ]
    assert [ -f "$CUDA_SAMPLE_BW_DIR/make-cleaned" ]
}

@test "fail gracefully when there are no cuda samples" {
    rm -rf "$CUDA_SAMPLE_BW_DIR"
    run run_cuda_bandwidth_test
    assert_failure
    refute_output
}


@test "fail gracefully when make is not installed" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    hide_command make
    run run_cuda_bandwidth_test
    assert_failure
    refute_output
}

@test "run cuda samples" {
    . "$BATS_TEST_DIRNAME/mocks.bash"
    function make {
        echo '#!/bin/bash' >"$CUDA_SAMPLE_BW_DIR/bandwidthTest"
        echo 'echo "CUDA bandwidth result for device $CUDA_VISIBLE_DEVICES goes here"' >>"$CUDA_SAMPLE_BW_DIR/bandwidthTest"
        chmod 700 "$CUDA_SAMPLE_BW_DIR/bandwidthTest"
    }

    function get_gpu_numa {
        echo "0"
    }

    function numactl {
        shift 2
        $@
    }

    run run_cuda_bandwidth_test "Standard_ND96asr_v4"
    assert_success
    for i in {0..3}; do
        run cat "$DIAG_DIR/Nvidia/bandwidthTest/$i.out"
        assert_success
        assert_output "CUDA bandwidth result for device $i goes here"
    done
}
