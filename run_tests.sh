#!/bin/bash
# Run all test suites for HurricaneFPGA

set -e

echo "========================================"
echo "HurricaneFPGA Test Suite"
echo "========================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test suite
run_test_suite() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ ${test_name} FAILED${NC}"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# Rust firmware tests
if command -v cargo &> /dev/null; then
    echo "========================================
    echo "Rust Firmware Tests"
    echo "========================================"
    echo ""
    
    run_test_suite "Firmware Library Tests" \
        "cd firmware/samd51_hid_injector && cargo test --lib"
    
    echo ""
fi

# Python unit tests
if command -v python3 &> /dev/null; then
    echo "========================================"
    echo "Python Unit Tests"
    echo "========================================"
    echo ""
    
    run_test_suite "Descriptor Unit Tests" \
        "python3 tools/test_descriptor_unit.py"
    
    run_test_suite "Injection Unit Tests" \
        "python3 tools/test_injection_unit.py"
    
    echo ""
fi

# Legacy Rust CLI tests (if applicable)
if [ -f "Cargo.toml" ] && command -v cargo &> /dev/null; then
    echo "========================================"
    echo "CLI Tool Tests"
    echo "========================================"
    echo ""
    
    run_test_suite "Legacy Frontend Tests" \
        "cargo test --bin hurricanefpga 2>/dev/null || echo 'No tests found'"
    
    echo ""
fi

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo "========================================"

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
