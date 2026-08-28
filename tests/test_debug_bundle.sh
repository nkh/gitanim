#!/usr/bin/env bash
# Test for dv_debug_bundle.sh script.
#
# Verifies:
#   1. -h / --help works and exits 0
#   2. Running without args produces an error and exits non-zero
#   3. Running with valid args produces a tar.gz bundle with all expected files
#   4. The bundle contains the user-supplied description
#
# Usage: bash tests/test_debug_bundle.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/dv_debug_bundle.sh"
PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== dv_debug_bundle.sh tests ==="
echo ""

# --- Test 1: -h flag ---
echo "Test 1: -h prints help and exits 0"
out=$("$SCRIPT" -h 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"NAME"* && "$out" == *"SYNOPSIS"* && "$out" == *"DESCRIPTION"* ]]; then
    ok "-h shows help and exits 0"
else
    fail "-h did not show help (rc=$rc)"
    echo "    output: $out" | head -3
fi

# --- Test 2: --help flag ---
echo "Test 2: --help prints help and exits 0"
out=$("$SCRIPT" --help 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"OPTIONS"* && "$out" == *"EXAMPLES"* ]]; then
    ok "--help shows full help and exits 0"
else
    fail "--help did not show full help (rc=$rc)"
fi

# --- Test 3: No args produces error ---
echo "Test 3: no args produces error and exits non-zero"
out=$("$SCRIPT" 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"requires"* ]]; then
    ok "no args produces error and exits non-zero (rc=$rc)"
else
    fail "no args did not produce error (rc=$rc)"
    echo "    output: $out" | head -3
fi

# --- Test 4: Non-existent file ---
echo "Test 4: non-existent file produces error"
out=$("$SCRIPT" /nonexistent_old.py /nonexistent_new.py 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"does not exist"* ]]; then
    ok "non-existent file produces error"
else
    fail "non-existent file did not produce error (rc=$rc)"
    echo "    output: $out" | head -3
fi

# --- Test 5: Valid invocation produces bundle ---
echo "Test 5: valid invocation produces tar.gz bundle with all expected files"
OLD="$ROOT/tests/examples/01_small_python/old.py"
NEW="$ROOT/tests/examples/01_small_python/new.py"
DESC="test description for bundle test"
out=$("$SCRIPT" "$OLD" "$NEW" "$DESC" 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 ]]; then
    fail "valid invocation failed (rc=$rc)"
    echo "    output: $out" | head -5
else
    # Extract the tarball path from the last line
    tarball=$(echo "$out" | grep -oE '/tmp/diffvim_debug_[0-9_]+\.tar\.gz' | head -1)
    if [[ -z "$tarball" || ! -f "$tarball" ]]; then
        fail "tarball not found in output or filesystem"
        echo "    output: $out" | tail -3
    else
        ok "tarball created at $tarball"
        # Extract and verify contents
        tmpdir=$(mktemp -d)
        tar -xzf "$tarball" -C "$tmpdir" 2>/dev/null
        bundle_dir=$(ls -d "$tmpdir"/diffvim_debug_* 2>/dev/null | head -1)
        if [[ -z "$bundle_dir" ]]; then
            fail "could not extract bundle"
        else
            # Check for required files
            required_files=(
                old.txt new.txt raw_ops.txt post_ops.txt timed_ops.txt
                animator_output.txt output_diff.txt binary_md5s.txt
                settings.conf system_info.txt description.txt op_counts.txt
            )
            all_present=1
            for f in "${required_files[@]}"; do
                if [[ ! -f "$bundle_dir/$f" ]]; then
                    fail "missing file in bundle: $f"
                    all_present=0
                fi
            done
            if [[ $all_present -eq 1 ]]; then
                ok "all ${#required_files[@]} required files present in bundle"
            fi
            # Check description content
            actual_desc=$(cat "$bundle_dir/description.txt")
            if [[ "$actual_desc" == "$DESC" ]]; then
                ok "description.txt contains the user-supplied description"
            else
                fail "description.txt mismatch: expected '$DESC', got '$actual_desc'"
            fi
            # Check old.txt and new.txt match the originals
            if diff -q "$OLD" "$bundle_dir/old.txt" >/dev/null; then
                ok "old.txt matches input old file"
            else
                fail "old.txt does not match input old file"
            fi
            if diff -q "$NEW" "$bundle_dir/new.txt" >/dev/null; then
                ok "new.txt matches input new file"
            else
                fail "new.txt does not match input new file"
            fi
            # Check binary_md5s.txt has all 5 binaries
            n_md5s=$(grep -c ":" "$bundle_dir/binary_md5s.txt")
            if [[ $n_md5s -ge 5 ]]; then
                ok "binary_md5s.txt has $n_md5s entries"
            else
                fail "binary_md5s.txt has only $n_md5s entries (expected >= 5)"
            fi
            # Check system_info.txt has key fields
            if grep -q "OS:" "$bundle_dir/system_info.txt" && \
               grep -q "Git commit:" "$bundle_dir/system_info.txt"; then
                ok "system_info.txt has OS and Git commit info"
            else
                fail "system_info.txt missing OS or Git commit"
            fi
        fi
        rm -rf "$tmpdir"
        rm -f "$tarball"
    fi
fi

# --- Test 6: Bundle works on a non-trivial example ---
echo "Test 6: bundle works on example 02 (large python)"
OLD="$ROOT/tests/examples/02_large_python/old.py"
NEW="$ROOT/tests/examples/02_large_python/new.py"
out=$("$SCRIPT" "$OLD" "$NEW" "example 02 bundle" 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 ]]; then
    fail "example 02 bundle failed (rc=$rc)"
else
    tarball=$(echo "$out" | grep -oE '/tmp/diffvim_debug_[0-9_]+\.tar\.gz' | head -1)
    if [[ -n "$tarball" && -f "$tarball" ]]; then
        # Verify the animator output matches the expected new.py
        tmpdir=$(mktemp -d)
        tar -xzf "$tarball" -C "$tmpdir" 2>/dev/null
        bundle_dir=$(ls -d "$tmpdir"/diffvim_debug_* | head -1)
        if diff -q "$NEW" "$bundle_dir/animator_output.txt" >/dev/null 2>&1; then
            ok "example 02 animator output matches new.py"
        else
            fail "example 02 animator output does not match new.py"
        fi
        rm -rf "$tmpdir"
        rm -f "$tarball"
    else
        fail "example 02 bundle tarball not found"
    fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
exit 0
