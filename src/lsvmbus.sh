#!/bin/bash
USAGE_MSG="Usage: lsvmbus [options]

"
HELP_MSG="${USAGE_MSG}Options:
  -h, --help     show this help message and exit
  -v, --verbose  print verbose messages. Try -vv, -vvv for  more verbose
                 messages"
optstring=":hv-:"

verbose=0

while getopts ${optstring} arg; do
    case "${arg}" in
        v) verbose=$((verbose+1)) ;;
        h) echo "$HELP_MSG"; exit 0 ;;
        -)
            case "${OPTARG}" in
                verbose) verbose=$((verbose+1)) ;;
                help) echo "$HELP_MSG"; exit 0 ;;
                *) echo >&2 "${USAGE_MSG}lsvmbus: error: no such option: --${OPTARG}"; exit 1 ;;
            esac
            ;;
        *) echo "${USAGE_MSG}lsvmbus: error: no such option: -${OPTARG}"; exit 1 ;;
    esac
done

VMBUS_SYS_PATH='/sys/bus/vmbus/devices'

if [ ! -d "$VMBUS_SYS_PATH" ]; then
    echo "$VMBUS_SYS_PATH doesn't exist: exiting..."
    exit -1
fi

VMBUS_DEV_MAP="{0e0b6031-5213-4934-818b-38d90ced39db}:[Operating system shutdown]
{9527e630-d0ae-497b-adce-e80ab0175caf}:[Time Synchronization]
{57164f39-9115-4e78-ab55-382f3bd5422d}:[Heartbeat]
{a9a0f4e7-5a45-4d96-b827-8a841e8c03e6}:[Data Exchange]
{35fa2e29-ea23-4236-96ae-3a6ebacba440}:[Backup (volume checkpoint)]
{34d14be3-dee4-41c8-9ae7-6b174977c192}:[Guest services]
{525074dc-8985-46e2-8057-a307dc18a502}:[Dynamic Memory]
{cfa8b69e-5b4a-4cc0-b98b-8ba1a1f3f95a}:Synthetic mouse
{f912ad6d-2b17-48ea-bd65-f927a61c7684}:Synthetic keyboard
{da0a7802-e377-4aac-8e77-0558eb1073f8}:Synthetic framebuffer adapter
{f8615163-df3e-46c5-913f-f2d2f965ed0e}:Synthetic network adapter
{32412632-86cb-44a2-9b5c-50d1417354f5}:Synthetic IDE Controller
{ba6163d9-04a1-4d29-b605-72e2ffb1dc7f}:Synthetic SCSI Controller
{2f9bcc4a-0069-4af3-b76b-6fd0be528cda}:Synthetic fiber channel adapter
{8c2eaf3d-32a7-4b09-ab99-bd1f1c86b501}:Synthetic RDMA adapter
{44c4f61d-4444-4400-9d52-802e27ede19f}:PCI Express pass-through
{276aacf4-ac15-426c-98dd-7521ad3f01fe}:[Reserved system device]
{f8e65716-3cb3-4a06-9a60-1889c5cccab5}:[Reserved system device]
{3375baf4-9e15-4b30-b765-67acb10d607b}:[Reserved system device]"

get_dev_desc() {
    echo "$VMBUS_DEV_MAP" | awk -F: "/$1/{print \$2; flag=1} END{if (!flag) print \"Unknown\"}"
}

get_vmbus_dev_attr() {
    dev_name=$1
    attr=$2
    cat "$VMBUS_SYS_PATH/$dev_name/$attr"
}

TEMPDIR=$(mktemp -d XXXXXX)

FORMAT0='VMBUS ID %2s: %s\n'
FORMAT1='VMBUS ID %2s: Class_ID = %s - %s\n%s\n\n'
FORMAT2='VMBUS ID %2s: Class_ID = %s - %s\n\tDevice_ID = %s\n\tSysfs path: %s\n%s\n\n'

for f in $(ls "$VMBUS_SYS_PATH"); do
    VMBUS_ID=$(get_vmbus_dev_attr $f 'id' | head -1 | tr -d '[:space:]')
    CLASS_ID=$(get_vmbus_dev_attr $f 'class_id' | head -1 | tr -d '[:space:]')
    DEVICE_ID=$(get_vmbus_dev_attr $f 'device_id' | head -1 | tr -d '[:space:]')
    DEV_DESC=$(get_dev_desc $CLASS_ID)

    CHN_VP_MAPPING=$(get_vmbus_dev_attr $f 'channel_vp_mapping' |
        sort --numeric-sort --field-separator=: |
        awk -F: '{print "\tRel_ID="$1", target_cpu="$2}'
    )

    SYSFS_PATH="$VMBUS_SYS_PATH/$f"

    # print into temp file (hard coded at double verbose)
    case $verbose in
        0) printf "$FORMAT0" "$VMBUS_ID" "$DEV_DESC" > "$TEMPDIR/$VMBUS_ID" ;;
        1) printf "$FORMAT1" "$VMBUS_ID" "$CLASS_ID" "$DEV_DESC" "$CHN_VP_MAPPING" > "$TEMPDIR/$VMBUS_ID" ;;
        *) printf "$FORMAT2" "$VMBUS_ID" "$CLASS_ID" "$DEV_DESC" "$DEVICE_ID" "$SYSFS_PATH" "$CHN_VP_MAPPING" > "$TEMPDIR/$VMBUS_ID" ;;
    esac
done

cat $(ls "$TEMPDIR" | sort -n  | sed "s|^|$TEMPDIR/|" | xargs)

rm -r "$TEMPDIR"