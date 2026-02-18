# Cancel and Remove Recent GitHub Actions Workflows

This document provides instructions for cancelling and removing GitHub Actions workflow runs that were triggered in the last 30 minutes.

## Identified Workflow Runs (Last 30 Minutes)

As of 2026-02-18 04:07 UTC, the following workflow runs were identified:

| Run ID | Name | Status | Created At |
|--------|------|--------|------------|
| 22126082348 | Documentation | completed | 2026-02-18T04:06:45Z |
| 22126082161 | Run tests | completed | 2026-02-18T04:06:44Z |
| 22126081879 | Running Copilot coding agent | in_progress | 2026-02-18T04:06:43Z |

## Method 1: Using the GitHub Actions Workflow (Recommended)

The easiest way to cancel and delete recent workflow runs is to use the provided GitHub Actions workflow. This workflow has the necessary permissions to perform these operations.

### Steps:

1. Go to the Actions tab in the GitHub repository
2. Select "Cancel and Delete Recent Workflow Runs" from the left sidebar
3. Click "Run workflow" button
4. Enter the number of minutes (default is 30)
5. Click "Run workflow" to execute

The workflow will automatically:
- Find all workflow runs triggered within the specified time period
- Cancel any in-progress or queued runs
- Delete all identified workflow runs (except itself)
- Provide a detailed log of all operations

## Method 2: Automated Script

A script has been created to automatically cancel and delete all workflow runs from the last 30 minutes: `cancel_recent_workflows.sh`

### Prerequisites

- GitHub CLI (`gh`) must be installed and authenticated
- The authenticated user must have appropriate permissions to cancel and delete workflow runs (typically requires `repo` scope or admin access)

### Usage

```bash
# Make sure you're authenticated with GitHub CLI
gh auth status

# Run the script
./cancel_recent_workflows.sh
```

## Method 3: Manual Cancellation and Deletion

If you prefer to manually cancel and delete workflow runs, use the following commands:

### Cancel In-Progress Runs

```bash
# Cancel workflow run 22126081879 (if still in progress)
gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/NatLabRockies/REopt.jl/actions/runs/22126081879/cancel
```

### Delete Workflow Runs

```bash
# Delete workflow run 22126082348
gh api --method DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/NatLabRockies/REopt.jl/actions/runs/22126082348

# Delete workflow run 22126082161
gh api --method DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/NatLabRockies/REopt.jl/actions/runs/22126082161

# Delete workflow run 22126081879
gh api --method DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/NatLabRockies/REopt.jl/actions/runs/22126081879
```

## Alternative: Using curl with GitHub Token

If you have a GitHub personal access token with appropriate permissions:

```bash
# Set your GitHub token
export GITHUB_TOKEN="your_token_here"

# Cancel in-progress run
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/NatLabRockies/REopt.jl/actions/runs/22126081879/cancel

# Delete workflow runs
curl -X DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/NatLabRockies/REopt.jl/actions/runs/22126082348

curl -X DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/NatLabRockies/REopt.jl/actions/runs/22126082161

curl -X DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/NatLabRockies/REopt.jl/actions/runs/22126081879
```

## Verification

After running the cancellation and deletion commands, verify that the workflow runs have been removed:

```bash
# List recent workflow runs
gh run list --repo NatLabRockies/REopt.jl --limit 10

# Or check specific run IDs (should return 404 if deleted)
gh api /repos/NatLabRockies/REopt.jl/actions/runs/22126082348
gh api /repos/NatLabRockies/REopt.jl/actions/runs/22126082161
gh api /repos/NatLabRockies/REopt.jl/actions/runs/22126081879
```

## Notes

- Deleting workflow runs is permanent and cannot be undone
- Workflow run logs and artifacts will also be deleted
- Only users with appropriate permissions can cancel and delete workflow runs
- Completed workflow runs can be deleted, but cannot be "cancelled" (they're already done)
