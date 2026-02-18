#!/bin/bash
# Security review script for fetched commits
# This script helps identify potential sensitive information in the commits

set -e

COMMITS=(
    "77a4a120a42eda9694e2fd57cef68f9475129704"  # v0.32.8
    "8cd9a1326b9a595b71496728ede94e2e2b0690ac"  # v0.33.0
    "1bdbb658597cc8879380b7b3f37d56d58834d2ea"  # v0.34.0
    "8d61ed40d0bc85a604aa78965ed5dbcde1fe700a"  # v0.35.0
    "794c0ae95d1985b3090eff723be60867ae307321"  # v0.35.1
    "4e08fe26538b4d455f5f155a35001c7fdc896888"  # v0.36.0
    "4c815c11e3c03858f954c9258d73dcaf410934ff"  # v0.37.0
    "d84336fc81fc0e86173a93be8bf0e74b64972721"  # v0.37.1
    "9174cef955b1603e5c52f5bb41341f826486e195"  # v0.37.2
    "1f8b80213ca1080c6bf35c394c2406bd2fdd11f8"  # v0.37.3
    "0085341139a2999eb14b486680832014fd5c1f3f"  # v0.37.4
    "8bc98f3d09e57c6a5882dbb59ca827805c3477a7"  # v0.37.5
    "27eae363a470fc7f8137f1bd4e6cffb2832f9454"  # v0.38.0
    "e5efe256ffec6697ade71e1cdfb61212d61d5b3b"  # v0.38.1
    "9fe47ebda1565c670d45e0b49cb3e68aac17eab0"  # v0.38.2
)

echo "========================================="
echo "Security Review of Fetched Commits"
echo "========================================="
echo ""

# Check 1: Scan for sensitive patterns
echo "=== Check 1: Scanning for sensitive patterns ==="
echo ""

SENSITIVE_PATTERNS=(
    "password"
    "api[_-]?key"
    "secret"
    "token"
    "credential"
    "private[_-]?key"
    "BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY"
    "aws[_-]?access"
    "aws[_-]?secret"
)

found_issues=0

for commit in "${COMMITS[@]}"; do
    echo "Checking commit ${commit:0:10}..."
    
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if git show "$commit" | grep -qiE "$pattern"; then
            echo "  ⚠️  WARNING: Found pattern '$pattern'"
            found_issues=$((found_issues + 1))
        fi
    done
    
    if git show "$commit" | grep -qE "sk-[a-zA-Z0-9]{48}"; then
        echo "  ⚠️  WARNING: Found potential OpenAI API key pattern"
        found_issues=$((found_issues + 1))
    fi
    
    if git show "$commit" | grep -qE "ghp_[a-zA-Z0-9]{36}"; then
        echo "  ⚠️  WARNING: Found potential GitHub personal access token"
        found_issues=$((found_issues + 1))
    fi
done

echo ""

# Check 2: List all modified files
echo "=== Check 2: Files modified in these commits ==="
echo ""

all_files=$(mktemp)
for commit in "${COMMITS[@]}"; do
    git show "$commit" --name-only --format="" >> "$all_files"
done

sort -u "$all_files" | while read -r file; do
    echo "  - $file"
done

rm "$all_files"
echo ""

# Check 3: Commit messages and metadata
echo "=== Check 3: Commit metadata ==="
echo ""

for commit in "${COMMITS[@]}"; do
    echo "Commit: ${commit:0:10}"
    git log -1 --format="  Date: %ci%n  Author: %an <%ae>%n  Message: %s" "$commit"
    echo ""
done

# Check 4: Size of changes
echo "=== Check 4: Size of changes (lines added/removed) ==="
echo ""

for commit in "${COMMITS[@]}"; do
    stats=$(git show "$commit" --shortstat --format="")
    echo "${commit:0:10}: $stats"
done

echo ""

# Summary
echo "========================================="
echo "Summary"
echo "========================================="
echo ""

if [ $found_issues -eq 0 ]; then
    echo "✓ No obvious sensitive patterns found in commit diffs"
    echo ""
    echo "⚠️  IMPORTANT: This is an automated scan only!"
    echo "   Manual review is still required to ensure:"
    echo "   1. No proprietary code or algorithms"
    echo "   2. No customer data"
    echo "   3. No internal URLs or infrastructure details"
    echo "   4. No other organization-specific sensitive information"
else
    echo "⚠️  ALERT: Found $found_issues potential sensitive patterns!"
    echo ""
    echo "   DO NOT push these tags until issues are reviewed and resolved."
    echo "   Review the warnings above and inspect the commits manually."
fi

echo ""
echo "To manually inspect a commit, use:"
echo "  git show <commit-hash>"
echo ""
echo "To see the full diff of all commits, use:"
echo "  for commit in ${COMMITS[@]}; do git show \$commit; done | less"
echo ""
