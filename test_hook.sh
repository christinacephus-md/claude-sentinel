#!/bin/bash
# Claude Model Router v2.0 - Test Suite

ROUTER="$HOME/.claude/plugins/model-router/hooks/model_router.py"
REPORT="$HOME/.claude/plugins/model-router/hooks/cost_report.py"
PASS=0
FAIL=0

echo ""
echo "+---------------------------------------------------------+"
echo "|  Model Router v2.0 - Test Suite                         |"
echo "+---------------------------------------------------------+"
echo ""

run_test() {
    local name="$1"
    local prompt="$2"
    local expected="$3"

    result=$(echo "{\"prompt\":\"$prompt\"}" | python3 "$ROUTER" 2>&1)
    if echo "$result" | grep -qi "$expected"; then
        echo "  PASS: $name -> $expected"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected $expected)"
        echo "        Got: $(echo "$result" | grep -i 'recommendation' | head -1)"
        FAIL=$((FAIL + 1))
    fi
}

echo "  --- Haiku Tests (simple tasks) ---"
run_test "File read" "Show me the contents of README.md" "haiku"
run_test "Quick lookup" "What is the current version?" "haiku"
run_test "Status check" "Check the status of the build" "haiku"
run_test "Short follow-up" "yes" "haiku"
run_test "Approval" "looks good do it" "haiku"
run_test "Simple view" "list all the files in src" "haiku"

echo ""
echo "  --- Sonnet Tests (standard tasks) ---"
run_test "Error handling" "Add error handling to the user login function in auth.go" "sonnet"
run_test "Test writing" "Write unit tests for the patient lookup handler" "sonnet"
run_test "Bug fix" "Fix the null pointer in handler.py line 42" "sonnet"

echo ""
echo "  --- Opus Tests (complex tasks) ---"
run_test "Architecture" "Design a microservices architecture for our patient data API with security guardrails and HIPAA compliance across the entire codebase" "opus"
run_test "Deep research" "Research and synthesize a comprehensive strategy for migrating our infrastructure to terraform" "opus"
run_test "Security audit" "Audit the entire authentication module for security vulnerabilities and investigate access control patterns across all services" "opus"

echo ""
echo "  --- Cost Report Test ---"
if python3 "$REPORT" 2>&1 | grep -q "Cost Report\|No routing data"; then
    echo "  PASS: Cost report runs successfully"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Cost report failed"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  --- Results ---"
TOTAL=$((PASS + FAIL))
echo "  $PASS/$TOTAL passed"
if [ $FAIL -gt 0 ]; then
    echo "  $FAIL tests failed"
fi
echo ""
