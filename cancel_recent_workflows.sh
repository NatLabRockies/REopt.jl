#!/bin/bash

# Script to cancel and delete GitHub Actions workflow runs triggered in the last N minutes
# This script requires GitHub CLI (gh) to be installed and authenticated with appropriate permissions
#
# Usage:
#   ./cancel_recent_workflows.sh [REPO] [MINUTES_AGO]
#
# Arguments:
#   REPO        - GitHub repository in format "owner/repo" (default: auto-detect from current git repo)
#   MINUTES_AGO - Number of minutes to look back (default: 30)

set -e

# Get repository from argument or detect from git
if [ -n "$1" ]; then
  REPO="$1"
else
  # Try to detect from git remote
  REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$|\1|' || echo "")
  if [ -z "$REPO" ]; then
    REPO="NatLabRockies/REopt.jl"
  fi
fi

# Get minutes ago from argument or use default
MINUTES_AGO="${2:-30}"

CUTOFF_TIME=$(date -u -d "$MINUTES_AGO minutes ago" --iso-8601=seconds)

echo "================================================"
echo "Cancelling and Deleting Recent Workflow Runs"
echo "Repository: $REPO"
echo "Minutes ago: $MINUTES_AGO"
echo "Cutoff time: $CUTOFF_TIME"
echo "================================================"
echo ""

# Get all workflow runs from the last 30 minutes
echo "Fetching workflow runs triggered after $CUTOFF_TIME..."
WORKFLOW_RUNS=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$REPO/actions/runs?per_page=100" \
  --jq ".workflow_runs[] | select(.created_at >= \"$CUTOFF_TIME\") | .id")

if [ -z "$WORKFLOW_RUNS" ]; then
  echo "No workflow runs found in the last 30 minutes."
  exit 0
fi

echo "Found the following workflow runs to cancel and delete:"
echo "$WORKFLOW_RUNS"
echo ""

# Cancel and delete each workflow run
for RUN_ID in $WORKFLOW_RUNS; do
  echo "Processing workflow run: $RUN_ID"
  
  # Get workflow run details
  RUN_INFO=$(gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO/actions/runs/$RUN_ID" \
    --jq '{name: .name, status: .status, created_at: .created_at}')
  
  echo "  Details: $RUN_INFO"
  
  # Cancel the workflow run if it's in progress or queued
  STATUS=$(echo "$RUN_INFO" | jq -r '.status')
  if [ "$STATUS" = "in_progress" ] || [ "$STATUS" = "queued" ] || [ "$STATUS" = "waiting" ]; then
    echo "  Cancelling workflow run $RUN_ID..."
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/$REPO/actions/runs/$RUN_ID/cancel" || echo "  Failed to cancel (may already be completed)"
  else
    echo "  Workflow run is already $STATUS, skipping cancellation."
  fi
  
  # Delete the workflow run
  echo "  Deleting workflow run $RUN_ID..."
  gh api \
    --method DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO/actions/runs/$RUN_ID" && echo "  Successfully deleted!" || echo "  Failed to delete!"
  
  echo ""
done

echo "================================================"
echo "All workflow runs from the last $MINUTES_AGO minutes have been processed."
echo "================================================"
