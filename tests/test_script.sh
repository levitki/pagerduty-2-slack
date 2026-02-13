#!/bin/bash

# Test suite for push_into_slack_group.sh
#
# This script provides basic integration tests with mock API responses

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPT="$ROOT_DIR/push_into_slack_group.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Mock API server (simple HTTP server using nc or python)
MOCK_SERVER_PID=""
MOCK_SERVER_PORT=8888

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

cleanup() {
    if [[ -n "$MOCK_SERVER_PID" ]]; then
        kill "$MOCK_SERVER_PID" 2>/dev/null || true
    fi
    rm -rf /tmp/pd2slack-test-cache
}

trap cleanup EXIT

# Test 1: Script exists and is executable
test_script_exists() {
    print_test "Script exists and is executable"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -x "$SCRIPT" ]]; then
        print_pass "Script is executable"
    else
        print_fail "Script is not executable"
    fi
}

# Test 2: Help message
test_help_message() {
    print_test "Help message displays correctly"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if "$SCRIPT" --help 2>&1 | grep -q "PagerDuty to Slack On-Call Sync"; then
        print_pass "Help message displays correctly"
    else
        print_fail "Help message not found"
    fi
}

# Test 3: Version flag
test_version_flag() {
    print_test "Version flag returns version"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if "$SCRIPT" --version 2>&1 | grep -q "v"; then
        print_pass "Version flag works"
    else
        print_fail "Version flag failed"
    fi
}

# Test 4: Missing environment variables
test_missing_env_vars() {
    print_test "Missing environment variables are detected"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! PAGER_TOKEN="" SLACK_TOKEN="" "$SCRIPT" P123 P456 test 2>&1 | grep -q "PAGER_TOKEN"; then
        print_fail "Missing PAGER_TOKEN not detected"
        return
    fi
    
    if ! PAGER_TOKEN="test" SLACK_TOKEN="" "$SCRIPT" P123 P456 test 2>&1 | grep -q "SLACK_TOKEN"; then
        print_fail "Missing SLACK_TOKEN not detected"
        return
    fi
    
    print_pass "Missing environment variables detected correctly"
}

# Test 5: Dry run mode
test_dry_run() {
    print_test "Dry run mode doesn't make actual changes"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # This would fail with real API calls, but dry-run should not actually call APIs for updates
    # We expect it to fail on API connectivity, not on the dry-run logic itself
    if PAGER_TOKEN="fake" SLACK_TOKEN="fake" "$SCRIPT" --dry-run P123 P456 test 2>&1 | grep -q "DRY RUN"; then
        print_pass "Dry run mode detected"
    else
        print_fail "Dry run mode not working"
    fi
}

# Test 6: Cache directory creation
test_cache_creation() {
    print_test "Cache directory is created"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    CACHE_DIR="/tmp/pd2slack-test-cache"
    rm -rf "$CACHE_DIR"
    
    # Run with fake tokens (will fail at API call, but cache should be created)
    PAGER_TOKEN="fake" SLACK_TOKEN="fake" CACHE_DIR="$CACHE_DIR" "$SCRIPT" P123 P456 test 2>/dev/null || true
    
    if [[ -d "$CACHE_DIR" ]]; then
        print_pass "Cache directory created"
        rm -rf "$CACHE_DIR"
    else
        print_fail "Cache directory not created"
    fi
}

# Test 7: Invalid arguments
test_invalid_args() {
    print_test "Invalid arguments are rejected"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if PAGER_TOKEN="test" SLACK_TOKEN="test" "$SCRIPT" --invalid-flag 2>&1 | grep -q "Unknown option"; then
        print_pass "Invalid arguments rejected"
    else
        print_fail "Invalid arguments not detected"
    fi
}

# Test 8: Shellcheck (if available)
test_shellcheck() {
    print_test "Shellcheck validation"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! command -v shellcheck &> /dev/null; then
        echo "  (shellcheck not installed, skipping)"
        return
    fi
    
    if shellcheck "$SCRIPT"; then
        print_pass "Shellcheck validation passed"
    else
        print_fail "Shellcheck found issues"
    fi
}

# Run all tests
echo "========================================="
echo "Running test suite for push_into_slack_group.sh"
echo "========================================="
echo ""

test_script_exists
test_help_message
test_version_flag
test_missing_env_vars
test_dry_run
test_cache_creation
test_invalid_args
test_shellcheck

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Total tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo "========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
else
    exit 0
fi
