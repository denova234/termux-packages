#!/bin/bash
# Enhanced build-all.sh - safe for cloud and GitHub Actions environments.

set -e -u -o pipefail

TERMUX_SCRIPTDIR=$(cd "$(realpath "$(dirname "$0")")"; pwd)

# Store pid of current process for docker cleanup
source "$TERMUX_SCRIPTDIR/scripts/utils/docker/docker.sh"; docker__create_docker_exec_pid_file

if [ "$(uname -o)" = "Android" ] || [ -e "/system/bin/app_process" ]; then
    echo "On-device execution of this script is not supported."
    exit 1
fi

# Load local config if exists
test -f "$HOME"/.termuxrc && . "$HOME"/.termuxrc
: ${TERMUX_TOPDIR:="$HOME/.termux-build"}
: ${TERMUX_ARCH:="aarch64"}
: ${TERMUX_DEBUG_BUILD:=""}
: ${TERMUX_INSTALL_DEPS:="-s"}
: ${TERMUX_OUTPUT_DIR:="$TERMUX_TOPDIR/output"}

_show_usage() {
    echo "Usage: ./build-all.sh [-a ARCH] [-d] [-i] [-o DIR]"
    echo "Build all packages in dependency order with resume and artifact support."
    echo "  -a Architecture (default: aarch64)"
    echo "  -d Build with debug symbols"
    echo "  -i Build dependencies too"
    echo "  -o Output directory (default: ~/.termux-build/output)"
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

if [[ ! "$TERMUX_ARCH" =~ ^(all|aarch64|arm|i686|x86_64)$ ]]; then
    echo "ERROR: Invalid arch '$TERMUX_ARCH'" >&2
    exit 1
fi

BUILDSCRIPT=$(dirname "$0")/build-package.sh
BUILDALL_DIR=$TERMUX_TOPDIR/_buildall-$TERMUX_ARCH
BUILDORDER_FILE=$BUILDALL_DIR/buildorder.txt
BUILDSTATUS_FILE=$BUILDALL_DIR/buildstatus.txt
ARTIFACT_DIR=/tmp/artifacts

mkdir -p "$BUILDALL_DIR" "$TERMUX_OUTPUT_DIR" "$ARTIFACT_DIR"

# Generate build order if missing
if [ ! -f "$BUILDORDER_FILE" ]; then
    echo "Generating build order..."
    "$TERMUX_SCRIPTDIR/scripts/buildorder.py" > "$BUILDORDER_FILE"
fi

# Continue from previous progress
if [ -e "$BUILDSTATUS_FILE" ]; then
    echo "Continuing build-all from: $BUILDSTATUS_FILE"
else
    echo "Starting fresh build for $TERMUX_ARCH"
fi

exec > >(tee -a "$BUILDALL_DIR/ALL.out")
exec 2> >(tee -a "$BUILDALL_DIR/ALL.err" >&2)
trap 'echo ERROR: See $BUILDALL_DIR/${PKG}.err' ERR

while read -r PKG PKG_DIR; do
    # Skip already built packages
    if [ -e "$BUILDSTATUS_FILE" ] && grep -qx "$PKG" "$BUILDSTATUS_FILE"; then
        echo "Skipping $PKG"
        continue
    fi

    echo "------------------------------------------------------------"
    echo "Building $PKG..."
    BUILD_START=$(date +%s)

    # Run package build
    if bash -x "$BUILDSCRIPT" -a "$TERMUX_ARCH" $TERMUX_DEBUG_BUILD \
        ${TERMUX_OUTPUT_DIR+-o $TERMUX_OUTPUT_DIR} $TERMUX_INSTALL_DEPS "$PKG_DIR" \
        > "$BUILDALL_DIR/${PKG}.out" 2> "$BUILDALL_DIR/${PKG}.err"; then

        echo "$PKG" >> "$BUILDSTATUS_FILE"
        BUILD_END=$(date +%s)
        BUILD_SECONDS=$(( BUILD_END - BUILD_START ))
        echo "✅ $PKG built successfully in ${BUILD_SECONDS}s"

        # Copy built debs to artifact folder (safe for CI)
        find "$TERMUX_OUTPUT_DIR" -type f -name "${PKG}_*.deb" -exec cp {} "$ARTIFACT_DIR" \; || true

    else
        echo "❌ Failed building $PKG (see ${PKG}.err)"
        continue
    fi

    # Optional: periodic flush to prevent losing logs
    sync || true
done < "$BUILDORDER_FILE"

echo "------------------------------------------------------------"
echo "🎉 Finished building all packages for $TERMUX_ARCH"
echo "Artifacts saved to: $ARTIFACT_DIR"
