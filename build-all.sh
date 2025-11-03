#!/bin/bash
# Enhanced build-all.sh: builds all packages (aarch64) and logs failed ones without stopping.

set -e -u -o pipefail

TERMUX_SCRIPTDIR=$(cd "$(realpath "$(dirname "$0")")"; pwd)
source "$TERMUX_SCRIPTDIR/scripts/utils/docker/docker.sh"; docker__create_docker_exec_pid_file

if [ "$(uname -o)" = "Android" ] || [ -e "/system/bin/app_process" ]; then
    echo "On-device execution of this script is not supported."
    exit 1
fi

# Read settings
test -f "$HOME"/.termuxrc && . "$HOME"/.termuxrc
: ${TERMUX_TOPDIR:="$HOME/.termux-build"}
: ${TERMUX_ARCH:="aarch64"}
: ${TERMUX_DEBUG_BUILD:=""}
: ${TERMUX_INSTALL_DEPS:="-s"}
: ${TERMUX_OUTPUT_DIR:="debs/"}

_show_usage() {
    echo "Usage: ./build-all.sh [-a ARCH] [-d] [-i] [-o DIR]"
    echo "Build all packages. Continues on errors, logs failures."
    exit 1
}

while getopts :a:hdio: option; do
case "$option" in
    a) TERMUX_ARCH="$OPTARG";;
    d) TERMUX_DEBUG_BUILD='-d';;
    i) TERMUX_INSTALL_DEPS='-i';;
    o) TERMUX_OUTPUT_DIR="$(realpath -m "$OPTARG")";;
    h) _show_usage;;
    *) _show_usage >&2 ;;
esac
done
shift $((OPTIND-1))
if [ "$#" -ne 0 ]; then _show_usage; fi

if [[ ! "$TERMUX_ARCH" =~ ^(aarch64|arm|i686|x86_64|all)$ ]]; then
    echo "ERROR: Invalid arch '$TERMUX_ARCH'" 1>&2
    exit 1
fi

BUILDSCRIPT=$TERMUX_SCRIPTDIR/build-package.sh
BUILDALL_DIR=$TERMUX_TOPDIR/_buildall-$TERMUX_ARCH
BUILDORDER_FILE=$BUILDALL_DIR/buildorder.txt
BUILDSTATUS_FILE=$BUILDALL_DIR/buildstatus.txt
FAILED_FILE=$BUILDALL_DIR/failed_packages.txt

mkdir -p "$BUILDALL_DIR"
rm -f "$FAILED_FILE"

if [ -e "$BUILDORDER_FILE" ]; then
    echo "Using existing buildorder file: $BUILDORDER_FILE"
else
    "$TERMUX_SCRIPTDIR/scripts/buildorder.py" > "$BUILDORDER_FILE"
fi

if [ -e "$BUILDSTATUS_FILE" ]; then
    echo "Continuing build-all from: $BUILDSTATUS_FILE"
fi

exec > >(tee -a "$BUILDALL_DIR/ALL.out")
exec 2> >(tee -a "$BUILDALL_DIR/ALL.err" >&2)

echo "=== Starting Termux build for architecture: $TERMUX_ARCH ==="
START_TIME=$(date +%s)

while read -r PKG PKG_DIR; do
    if [ -e "$BUILDSTATUS_FILE" ] && grep -q "^$PKG\$" "$BUILDSTATUS_FILE"; then
        echo "Skipping $PKG (already built)"
        continue
    fi

    echo "Building $PKG..."
    BUILD_START=$(date +%s)
    set +e
    bash -x "$BUILDSCRIPT" -a "$TERMUX_ARCH" $TERMUX_DEBUG_BUILD \
        ${TERMUX_OUTPUT_DIR+-o $TERMUX_OUTPUT_DIR} $TERMUX_INSTALL_DEPS "$PKG_DIR" \
        >"$BUILDALL_DIR/${PKG}.out" 2>"$BUILDALL_DIR/${PKG}.err"
    RESULT=$?
    set -e

    BUILD_END=$(date +%s)
    BUILD_SECONDS=$((BUILD_END - BUILD_START))

    if [ $RESULT -eq 0 ]; then
        echo "$PKG built successfully in ${BUILD_SECONDS}s"
        echo "$PKG" >> "$BUILDSTATUS_FILE"
    else
        echo "❌ Failed to build $PKG (exit code $RESULT)"
        echo "$PKG" >> "$FAILED_FILE"
    fi
done < "$BUILDORDER_FILE"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo "=== Build process completed in ${TOTAL_TIME}s ==="
if [ -s "$FAILED_FILE" ]; then
    echo
    echo "⚠️ The following packages failed to build:"
    cat "$FAILED_FILE"
    echo
else
    echo "✅ All packages built successfully!"
fi
