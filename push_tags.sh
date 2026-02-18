#!/bin/bash
# Script to push the created tags to GitHub

set -e

echo "Pushing tags to GitHub..."

# Read tags from file and push them
while IFS= read -r tag; do
    echo "Pushing $tag..."
    git push origin "$tag"
done < .github-tags-to-push.txt

echo ""
echo "All tags pushed successfully!"
echo ""
echo "You can verify the tags at: https://github.com/NatLabRockies/REopt.jl/tags"
