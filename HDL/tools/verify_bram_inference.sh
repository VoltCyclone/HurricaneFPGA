#!/bin/bash
###############################################################################
# Block RAM Inference Verification Script
# 
# This script checks Verilog files for problematic patterns that prevent
# block RAM inference and cause synthesis to use thousands of flip-flops.
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDL_DIR="$SCRIPT_DIR/.."
RTL_DIR="$HDL_DIR/hardware/rtl"

echo "=========================================="
echo "Block RAM Inference Verification"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to RTL directory
cd "$RTL_DIR"

echo "Checking for problematic patterns in Verilog files..."
echo ""

# Counter for issues
ISSUES=0

echo "=== 1. Checking for asynchronous memory reads (assign statements) ==="
echo ""
if grep -rn "assign.*\[.*\]" --include="*.v" usb_proxy/ usb_interface/ 2>/dev/null | grep -v "//.*assign" | grep -v "assign.*\[.*:.*\]"; then
    echo -e "${RED}❌ FOUND: Asynchronous memory reads via assign statements${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✓ No asynchronous memory reads found${NC}"
fi
echo ""

echo "=== 2. Checking for memory reads in if conditions ==="
echo ""
if grep -rn "if.*\[.*\].*==" --include="*.v" usb_proxy/ usb_interface/ 2>/dev/null | grep -v "//.*if" | grep -v "\[.*:.*\]"; then
    echo -e "${RED}❌ FOUND: Memory reads in if conditions (combinatorial)${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✓ No problematic if condition reads found${NC}"
fi
echo ""

echo "=== 3. Checking for memories without block RAM attributes ==="
echo ""
# Find all array declarations
FOUND_UNATTRIBUTED=0
while IFS= read -r line; do
    FILE=$(echo "$line" | cut -d: -f1)
    LINENO=$(echo "$line" | cut -d: -f2)
    
    # Check if the previous 3 lines contain syn_ramstyle attribute
    if ! sed -n "$((LINENO-3)),$((LINENO-1))p" "$FILE" 2>/dev/null | grep -q "syn_ramstyle"; then
        # Exclude small arrays (< 16 elements) and already known small buffers
        if ! echo "$line" | grep -qE "\[(0:)?([0-9]|1[0-5])\]"; then
            echo -e "${YELLOW}⚠️  $line${NC}"
            FOUND_UNATTRIBUTED=1
        fi
    fi
done < <(grep -rn "reg \[.*\].*\[" --include="*.v" usb_proxy/ usb_interface/ 2>/dev/null)

if [ $FOUND_UNATTRIBUTED -eq 0 ]; then
    echo -e "${GREEN}✓ All large memories have block RAM attributes${NC}"
else
    echo -e "${YELLOW}Note: Some memories without attributes (may be intentional for small buffers)${NC}"
fi
echo ""

echo "=== 4. Listing all block RAM declarations ==="
echo ""
grep -rn "syn_ramstyle.*block_ram" --include="*.v" usb_proxy/ usb_interface/ 2>/dev/null | while IFS= read -r line; do
    FILE=$(echo "$line" | cut -d: -f1)
    LINENO=$(echo "$line" | cut -d: -f2)
    # Show the attribute and the next line (the memory declaration)
    echo -e "${GREEN}$FILE:$LINENO${NC}"
    sed -n "${LINENO}p" "$FILE"
    sed -n "$((LINENO+1))p" "$FILE"
    echo ""
done

echo "=== 5. Key files fixed for block RAM inference ==="
echo ""
FILES_TO_CHECK=(
    "usb_proxy/uart_interface.v:simple_fifo"
    "usb_proxy/usb_descriptor_forwarder.v:desc_buffer"
    "usb_interface/usb_enumerator.v:rx_buffer"
    "usb_proxy/usb_monitor.v:packet_buffer"
    "usb_proxy/debug_interface.v:response_buffer"
    "usb_proxy/uart_debug_output.v:msg_buffer"
)

for entry in "${FILES_TO_CHECK[@]}"; do
    FILE=$(echo "$entry" | cut -d: -f1)
    BUFFER=$(echo "$entry" | cut -d: -f2)
    
    if grep -q "syn_ramstyle.*block_ram" "$FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ $FILE ($BUFFER) - Block RAM attribute present${NC}"
    else
        echo -e "${RED}❌ $FILE ($BUFFER) - Missing block RAM attribute${NC}"
        ISSUES=$((ISSUES + 1))
    fi
done

echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Block RAM inference should work correctly.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run synthesis: cd HDL && make fast"
    echo "  2. Check synthesis log for 'Inferred BRAM' messages"
    echo "  3. Synthesis should complete in 5-7 minutes (not hours)"
    exit 0
else
    echo -e "${RED}❌ Found $ISSUES critical issues that may prevent block RAM inference${NC}"
    echo ""
    echo "Please review the issues above and fix them before synthesis."
    exit 1
fi
