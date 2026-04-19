#!/bin/bash
# ==========================================================================
# run_visual_tests.sh - Visual regression test runner
#
# Usage:
#   ./t/visual/run_visual_tests.sh              # Run all tests
#   ./t/visual/run_visual_tests.sh --init       # Generate golden images
#   ./t/visual/run_visual_tests.sh --accept     # Accept all failing as new golden
#   ./t/visual/run_visual_tests.sh --update NAME # Accept specific test
#   ./t/visual/run_visual_tests.sh --threshold 0.005  # Set diff threshold
#   ./t/visual/run_visual_tests.sh --list       # List golden images
#   ./t/visual/run_visual_tests.sh --clean      # Remove output/diff files
#
# This script starts Xvfb if needed and runs the visual test suite.
# ==========================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_DIR="${VISUAL_TEST_BASE:-$PROJECT_DIR}"

GOLDEN_DIR="$BASE_DIR/t/visual/golden"
OUTPUT_DIR="$BASE_DIR/t/visual/output"
DIFFS_DIR="$BASE_DIR/t/visual/diffs"
REPORT_FILE="$OUTPUT_DIR/report.txt"

THRESHOLD="${VISUAL_TEST_THRESHOLD:-0.01}"
MODE="test"  # test | init | accept | update

TARGET_NAME=""

# --- Parse arguments ---
for arg in "$@"; do
    case "$arg" in
        --init)
            MODE="init"
            ;;
        --accept)
            MODE="accept"
            ;;
        --update)
            MODE="update"
            ;;
        --list)
            MODE="list"
            ;;
        --clean)
            MODE="clean"
            ;;
        --threshold)
            shift
            THRESHOLD="${1:-0.01}"
            ;;
        *)
            TARGET_NAME="$arg"
            ;;
    esac
done

export VISUAL_TEST_BASE="$BASE_DIR"
export VISUAL_TEST_THRESHOLD="$THRESHOLD"

# --- Helper functions ---

setup_dirs() {
    mkdir -p "$GOLDEN_DIR" "$OUTPUT_DIR" "$DIFFS_DIR"
}

cleanup_output() {
    rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
    rm -f "$DIFFS_DIR"/*.png 2>/dev/null || true
    rm -f "$REPORT_FILE" 2>/dev/null || true
}

check_xvfb() {
    if [ -n "${DISPLAY:-}" ]; then
        echo "DISPLAY already set to $DISPLAY"
    else
        echo "No DISPLAY set - Xvfb will be started by the test script"
    fi
}

check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: python3 is required for visual tests"
        exit 1
    fi
    if ! python3 -c "from PIL import Image; import numpy" 2>/dev/null; then
        echo "ERROR: Python Pillow and numpy are required"
        echo "Install with: pip install Pillow numpy"
        exit 1
    fi
}

list_golden() {
    echo "Golden images in $GOLDEN_DIR:"
    echo "---"
    if [ -d "$GOLDEN_DIR" ]; then
        ls -1 "$GOLDEN_DIR"/*.png 2>/dev/null | while read -r f; do
            basename "$f"
        done
    else
        echo "(no golden images yet)"
    fi
}

# --- Main ---

case "$MODE" in
    list)
        list_golden
        exit 0
        ;;

    clean)
        cleanup_output
        echo "Cleaned output and diff files"
        exit 0
        ;;

    init|accept|update|test)
        setup_dirs
        cleanup_output
        check_python
        check_xvfb

        echo "=== Visual Regression Tests ==="
        echo "Mode:      $MODE"
        echo "Threshold: $THRESHOLD"
        echo "Golden:    $GOLDEN_DIR"
        echo "Output:    $OUTPUT_DIR"
        echo "Diffs:     $DIFFS_DIR"
        echo "---"

        # Export for the Perl test script
        export VISUAL_TEST_MODE="$MODE"
        export VISUAL_TEST_GOLDEN_DIR="$GOLDEN_DIR"
        export VISUAL_TEST_OUTPUT_DIR="$OUTPUT_DIR"
        export VISUAL_TEST_DIFFS_DIR="$DIFFS_DIR"
        export VISUAL_TEST_THRESHOLD="$THRESHOLD"
        if [ -n "$TARGET_NAME" ]; then
            export VISUAL_TEST_TARGET="$TARGET_NAME"
        fi

        # Run the Perl test harness
        cd "$BASE_DIR"
        perl -Ilib -It/lib "$SCRIPT_DIR/run_visual_tests.pl" "$@"
        exit $?
        ;;

    *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 [--init|--accept|--update|--list|--clean] [--threshold N]"
        exit 1
        ;;
esac
