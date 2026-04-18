#!/system/bin/sh
SCRIPT_NAME="${0##*/}"
SCRIPT_NUM="${SCRIPT_NAME%.sh}"
. /data/local/tmp/schat/core.sh
dispatch_script "$@"
