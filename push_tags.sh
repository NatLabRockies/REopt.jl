#!/bin/bash
# Script to push the created tags to GitHub
#
# Usage: ./push_tags.sh
# Note: This script is already executable. If needed, make it executable with:
#       chmod +x push_tags.sh

set -e

echo "Pushing tags to GitHub..."

# Read tags from file and push them
while IFS= read -r tag; do
    # Skip empty lines
    [ -z "$tag" ] && continue
    echo "Pushing $tag..."
    git push origin "$tag"
done < .github-tags-to-push.txt

echo ""
echo "All tags pushed successfully!"
echo ""
echo "You can verify the tags at: https://github.com/NatLabRockies/REopt.jl/tags"
