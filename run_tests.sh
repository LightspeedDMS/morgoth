#!/bin/bash
# Morgoth Test Runner
# Runs all behavioral tests using the Sigil compiler

set +e  # Don't exit on errors - we want to run all tests

SIGIL_COMPILER="../sigil-lang/parser/target/release/sigil"
TEST_DIR="tests"
PASS=0
FAIL=0
SKIP=0
TEMP_DIR="/tmp/morgoth_tests_$$"

# Parse command-line arguments
FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --filter PATTERN  Run only tests matching pattern (e.g., P8, P2_21)"
            echo "  --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Run all tests"
            echo "  $0 --filter P8        # Run Phase 8 tests"
            echo "  $0 --filter P1_11     # Run layout tests"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create temp directory
mkdir -p "$TEMP_DIR"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo -e "${BLUE}Morgoth Test Suite${NC}"
echo -e "${BLUE}==================${NC}"
echo ""

# Check compiler exists
if [ ! -f "$SIGIL_COMPILER" ]; then
    echo -e "${RED}Error: Sigil compiler not found at $SIGIL_COMPILER${NC}"
    echo "Run: cd ../sigil-lang/parser && cargo build --release --no-default-features --features jit,native,protocols"
    exit 1
fi

# Run a single test
run_test() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sg)
    local expected="${test_file%.sg}.expected"
    local test_out="$TEMP_DIR/${test_name}.out"
    local test_err="$TEMP_DIR/${test_name}.err"

    # Check if test should be skipped
    if grep -q "^// SKIP" "$test_file" 2>/dev/null; then
        echo -e "  ${YELLOW}SKIP${NC}: $test_name"
        ((SKIP++))
        return 0
    fi

    echo -n "  $test_name ... "

    if [ -f "$expected" ]; then
        if ! "$SIGIL_COMPILER" run "$test_file" > "$test_out" 2>"$test_err"; then
            echo -e "${RED}FAIL${NC} (runtime error)"
            if [ -s "$test_err" ]; then
                sed 's/^/    /' "$test_err" | head -10
            fi
            ((FAIL++))
            return 1
        fi

        if diff -q "$expected" "$test_out" > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (output mismatch)"
            echo "    Expected:"
            sed 's/^/      /' "$expected"
            echo "    Got:"
            sed 's/^/      /' "$test_out"
            ((FAIL++))
            return 1
        fi
    else
        if "$SIGIL_COMPILER" run "$test_file" > "$test_out" 2>&1; then
            echo -e "${GREEN}PASS${NC} (no output check)"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (runtime error)"
            if [ -s "$test_out" ]; then
                sed 's/^/    /' "$test_out" | head -10
            fi
            ((FAIL++))
            return 1
        fi
    fi
}

# Find and run tests
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
test_files=$(find "$SCRIPT_DIR/$TEST_DIR" -name "*.sg" -type f | sort)

for test_file in $test_files; do
    test_name=$(basename "$test_file" .sg)
    # Apply filter if set
    if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
        continue
    fi
    run_test "$test_file"
done

echo ""
echo -e "${BLUE}==================${NC}"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
if [ $SKIP -gt 0 ]; then
    echo -e "${YELLOW}Skipped: $SKIP${NC}"
fi

TOTAL=$((PASS + FAIL))
if [ $TOTAL -gt 0 ]; then
    PERCENTAGE=$((PASS * 100 / TOTAL))
    echo -e "${BLUE}Pass rate: ${PERCENTAGE}% ($PASS/$TOTAL)${NC}"
fi

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
