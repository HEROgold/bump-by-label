# shellcheck shell=bash
# shellcheck disable=SC2034 # the publish_* functions and the outputs read these

# run_command: runs `command` through bash so its quoting works. `{bump}` is
# replaced by the bump type; without it, the bump type is appended as the
# last argument.
run_command() {
  if [[ $COMMAND == *"{bump}"* ]]; then
    bash -c "${COMMAND//\{bump\}/$BUMP_TYPE}"
  else
    bash -c "$COMMAND \"\$1\"" bump-by-label "$BUMP_TYPE"
  fi
}

# read_version: prints the first MAJOR.MINOR.PATCH that `validate` prints on
# stdout. Its stderr goes to the log as is: tool warnings there often name
# versions. Fails the run with the command and its output when it fails or
# prints no version.
read_version() {
  local output status=0 version
  output=$(bash -c "$VALIDATE") || status=$?
  if [ "$status" -ne 0 ]; then
    echo "Error: the validate command failed (exit $status): $VALIDATE" >&2
    echo "$output" >&2
    return 1
  fi
  # No match is handled below, so grep's exit status is ignored on purpose.
  version=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' <<<"$output" | head -n 1) || true
  if [ -z "$version" ]; then
    echo "Error: the validate command printed no MAJOR.MINOR.PATCH version: $VALIDATE" >&2
    echo "$output" >&2
    return 1
  fi
  echo "$version"
}

# bump_version: reads the version, runs `command` and reads it again. Sets
# OLD_VERSION, NEW_VERSION and TITLE. Call it as a plain statement, never in
# an `if` or `||`: there set -e is off and a failing validate wouldn't stop.
bump_version() {
  echo "Validating the current version..."
  OLD_VERSION=$(read_version)
  PREVIOUS_VERSION=$OLD_VERSION
  echo "Current version: $OLD_VERSION"
  echo "Running command: $COMMAND"
  echo "Found bump-type: $BUMP_TYPE"
  run_command
  echo "Validating the new version..."
  NEW_VERSION=$(read_version)
  echo "New version validated: $NEW_VERSION"
  TITLE="Bump version from ${OLD_VERSION} to ${NEW_VERSION}"
}

# stop_if_unchanged: ends the run when `command` didn't change the version.
stop_if_unchanged() {
  if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
    echo "No version bump required."
    exit 0
  fi
}

# commit_bump: commits everything the command changed as "$TITLE".
commit_bump() {
  git add -A
  git commit -m "$TITLE"
}
