# shellcheck shell=bash
# shellcheck disable=SC2034 # the other lib files read these

# read_inputs: reads the INPUT_* environment variables action.yml sets and
# applies their defaults. A missing required input or an unknown mode ends
# the run. GH_TOKEN is set by action.yml too.
read_inputs() {
  COMMAND=${INPUT_COMMAND:?INPUT_COMMAND (the command input) is required}
  VALIDATE=${INPUT_VALIDATE:?INPUT_VALIDATE (the validate input) is required}
  BASE_BRANCH=${INPUT_BASE_BRANCH:-main}
  MODE=${INPUT_MODE:-pr}
  case $MODE in
    pr | push) ;;
    *)
      echo "Error: mode must be 'pr' or 'push', not '$MODE'." >&2
      exit 1
      ;;
  esac
  BRANCH_PREFIX=${INPUT_BRANCH_PREFIX-workflow}
  CREATE_TAG=${INPUT_CREATE_TAG:-true}
  TAG_PREFIX=${INPUT_TAG_PREFIX-v}
  MOVING_TAGS=${INPUT_MOVING_TAGS:-false}
  LABEL_MAJOR=${INPUT_LABEL_MAJOR:-Major}
  LABEL_MINOR=${INPUT_LABEL_MINOR:-Minor}
  LABEL_PATCH=${INPUT_LABEL_PATCH:-Patch}
  LABEL_MAJOR_COLOR=${INPUT_LABEL_MAJOR_COLOR:-d93f0b}
  LABEL_MINOR_COLOR=${INPUT_LABEL_MINOR_COLOR:-0e8a16}
  LABEL_PATCH_COLOR=${INPUT_LABEL_PATCH_COLOR:-0075ca}
  LABELS_TO_ADD=${INPUT_LABELS_TO_ADD:-}
  # 41898282 is the user id of github-actions[bot]; this noreply address is
  # what links commits to the bot account.
  COMMIT_USER_NAME=${INPUT_COMMIT_USER_NAME:-github-actions[bot]}
  COMMIT_USER_EMAIL=${INPUT_COMMIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}
}
