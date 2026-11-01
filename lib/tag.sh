# shellcheck shell=bash
# shellcheck disable=SC2034 # TAG is an output

# Loaded only when create-tag is on.

# tag_release <sha>: tags <sha> as <tag-prefix><BUMPED_VERSION> unless that
# tag exists, and moves the major and major.minor tags when moving-tags is on.
tag_release() {
  local sha=$1 release_tag="${TAG_PREFIX}${BUMPED_VERSION}" moving_tag
  local major=${BUMPED_VERSION%%.*} minor
  minor=${BUMPED_VERSION#*.}
  minor=${minor%%.*}

  if git ls-remote --exit-code --tags origin "refs/tags/$release_tag" >/dev/null; then
    echo "Tag $release_tag already exists; not tagging."
  else
    git tag -a "$release_tag" -m "Release $release_tag" "$sha"
    git push origin "refs/tags/$release_tag"
    TAG=$release_tag
    echo "Tagged $sha as $release_tag."
  fi

  # Moving tags follow only a release this run tagged, so they never end up
  # on a commit the release tag doesn't point at.
  if [ "$MOVING_TAGS" = true ] && [ -n "$TAG" ]; then
    # The only force-pushes besides the bump branch, and only of these tags.
    for moving_tag in "${TAG_PREFIX}${major}" "${TAG_PREFIX}${major}.${minor}"; do
      git tag -f -a "$moving_tag" -m "Release $release_tag" "$sha"
      git push -f origin "refs/tags/$moving_tag"
      echo "Moved $moving_tag to $sha."
    done
  fi
}

# tag_merge_commit: tags the merge commit of the merged bump PR.
tag_merge_commit() {
  local merge_sha
  merge_sha=$(event_field '.pull_request.merge_commit_sha // ""')
  if [ -z "$merge_sha" ]; then
    echo "Error: the event has no pull_request.merge_commit_sha to tag." >&2
    exit 1
  fi
  if ! git cat-file -e "${merge_sha}^{commit}" 2>/dev/null; then
    git fetch -q origin "$merge_sha"
  fi
  tag_release "$merge_sha"
}
