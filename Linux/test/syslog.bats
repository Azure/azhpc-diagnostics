#!/bin/usr/env bats
# testing analysis of syslog collection
LOG_LOCATIONS=( /var/log/syslog /var/log/messages )

function setup {
    load "test_helper/bats-support/load"
    load "test_helper/bats-assert/load"
    load "$BATS_TEST_DIRNAME/../src/gather_azhpc_vm_diagnostics.sh" --no-update
    load "$BATS_TEST_DIRNAME/mocks.bash"

    for f in ${LOG_LOCATIONS[@]}; do
        if ! [ -f $f ]; then
            touch $f
        fi
    done

    DIAG_DIR=$(mktemp -d)
    mkdir -p "$DIAG_DIR/VM"
}

function teardown {
    rm -rf "$DIAG_DIR"

    for f in ${LOG_LOCATIONS[@]}; do
        if ! [ -s $f ]; then
            rm $f
        fi
    done
}

@test "filter_syslog removes audit lines" {
    filter() { 
        echo 'Dec 31 23:59:59 hostname audit: CWD cwd="/"' | filter_syslog
    }
    run filter
    refute_output "audit"
}

@test "filter_syslog doesn't remove non-audit syslog lines" {
    filter() { 
        echo 'Dec 31 23:59:59 hostname kernel: CWD cwd="/"' | filter_syslog
    }
    run filter
    assert_output 'Dec 31 23:59:59 hostname kernel: CWD cwd="/"'
}

@test "filter_syslog doesn't remove lines that happen to have \"audit\" in them" {
    filter() { 
        echo 'Dec 31 23:59:59 audit kernel: CWD audit="/"' | filter_syslog
    }
    run filter
    assert_output 'Dec 31 23:59:59 audit kernel: CWD audit="/"'
}

@test "Check that exactly one log is collected" {
    fetch_syslog >/dev/null

    assert_equal "$(ls "$DIAG_DIR/VM" | grep -Ec 'syslog|messages|journald.log')" 1
}
