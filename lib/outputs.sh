# shellcheck shell=bash

# Action outputs. entrypoint.sh runs write_outputs on EXIT, so every exit
# path writes all of them and steps.<id>.outputs.version-bumped is never
# undefined.
VERSION_BUMPED=false
PREVIOUS_VERSION=""
BUMPED_VERSION=""
BUMP_TYPE=""
PR_NUMBER=""
TAG=""

write_outputs() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  {
    echo "version-bumped=$VERSION_BUMPED"
    echo "previous-version=$PREVIOUS_VERSION"
    echo "new-version=$BUMPED_VERSION"
    echo "bump-type=${BUMP_TYPE:-none}"
    echo "pr-number=$PR_NUMBER"
    echo "tag=$TAG"
  } >>"$GITHUB_OUTPUT"
}
