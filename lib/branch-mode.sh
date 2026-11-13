# shellcheck shell=bash
# shellcheck disable=SC2034 # the outputs read these

# Loaded only with mode: branch.

# semver_add <x.y.z> <major|minor|patch>: prints the version bumped by that
# type. Pure bash, so the target is known before `command` runs.
semver_add() {
  local major minor patch
  IFS=. read -r major minor patch <<<"$1"
  case $2 in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

# branch_error <message>: prints a workflow error and ends the run.
branch_error() {
  echo "::error::$1"
  exit 1
}

# undo_earlier_bumps: reverts, newest first, the bump-by-label commits the
# head branch has on top of the base branch, so the next bump starts from the
# base version. Stages the reverts without committing them. Fails the run when
# the version differs from the base but no such commit explains it.
undo_earlier_bumps() {
  local sha email subject version
  local -a bumps=()
  while IFS=$'\t' read -r sha email subject; do
    [ "$email" = "$COMMIT_USER_EMAIL" ] || continue
    if [[ $subject =~ ^(Bump\ version\ from\ [0-9]+\.[0-9]+\.[0-9]+\ to\ [0-9]+\.[0-9]+\.[0-9]+|Reset\ version\ to\ [0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      bumps+=("$sha")
    fi
  done < <(git log --no-merges --format=$'%H\t%ae\t%s' "origin/$BASE_REF..HEAD")

  if [ "${#bumps[@]}" -eq 0 ]; then
    branch_error "The version on $HEAD_REF is $CURRENT and $BASE_REF has $BASE_VERSION, but no bump-by-label commit changed it. The version was edited by hand; undo that edit or remove the version label."
  fi
  if ! git revert --no-commit "${bumps[@]}"; then
    git revert --abort || true
    branch_error "Couldn't undo the earlier bump commits on $HEAD_REF; fix the version by hand."
  fi
  version=$(read_version)
  if [ "$version" != "$BASE_VERSION" ]; then
    git reset -q --hard HEAD
    branch_error "After undoing the earlier bumps the version is $version, not $BASE_VERSION from $BASE_REF. Fix the version by hand."
  fi
}

# publish_branch: makes the head branch of an open PR carry exactly one bump
# on top of its base branch, matching the PR's version label. Earlier bump
# commits by this action are reverted first, so changing or removing the
# label never stacks bumps. When the push is rejected because the head moved,
# it redoes everything from the new tip. Up to 3 attempts. Never forces.
publish_branch() {
  local action attempt tip target new_version

  if [ "$(event_field 'has("pull_request")')" != true ]; then
    action="no pull_request in the event"
  else
    action=$(event_field '.action // ""')
  fi
  case $action in
    opened | reopened | labeled | unlabeled | synchronize) ;;
    *)
      echo "mode: branch only acts on open pull requests; nothing to do for '$action'."
      return 0
      ;;
  esac

  PR_NUMBER=$(event_field '.pull_request.number // ""')
  local head_repo base_repo
  head_repo=$(event_field '.pull_request.head.repo.full_name // ""')
  base_repo=$(event_field '.pull_request.base.repo.full_name // ""')
  if [ "$head_repo" != "$base_repo" ]; then
    branch_error "PR #$PR_NUMBER comes from the fork $head_repo. bump-by-label can't push there; bump the version by hand."
  fi
  if [ "$(bump_label_count)" -gt 1 ]; then
    branch_error "PR #$PR_NUMBER has more than one version label. Keep one of '$LABEL_MAJOR', '$LABEL_MINOR', '$LABEL_PATCH'."
  fi

  BASE_REF=$(event_field '.pull_request.base.ref')
  HEAD_REF=$(event_field '.pull_request.head.ref')

  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: the working tree has uncommitted changes from earlier steps;" \
      "branch mode would commit them to $HEAD_REF:" >&2
    git status --short >&2
    exit 1
  fi

  for attempt in 1 2 3; do
    git fetch -q origin "$BASE_REF" "$HEAD_REF"
    git checkout -q --detach "origin/$BASE_REF"
    BASE_VERSION=$(read_version)
    tip=$(git rev-parse "origin/$HEAD_REF")
    git checkout -q -B "$HEAD_REF" "$tip"
    CURRENT=$(read_version)
    if [ -n "$(git status --porcelain)" ]; then
      echo "Error: the validate command changed files; it must only read the version:" >&2
      git status --short >&2
      exit 1
    fi

    BUMP_TYPE=$(bump_type_from_labels)
    if [ -z "$BUMP_TYPE" ]; then
      target=$BASE_VERSION
    else
      target=$(semver_add "$BASE_VERSION" "$BUMP_TYPE")
    fi

    PREVIOUS_VERSION=$BASE_VERSION
    if [ "$CURRENT" = "$target" ]; then
      echo "$HEAD_REF already has version $target; nothing to do."
      VERSION_BUMPED=false
      return 0
    fi

    if [ "$CURRENT" != "$BASE_VERSION" ]; then
      undo_earlier_bumps
    fi

    if [ "$target" != "$BASE_VERSION" ]; then
      echo "Running command: $COMMAND"
      run_command
      new_version=$(read_version)
      if [ "$new_version" != "$target" ]; then
        branch_error "The command produced $new_version, expected $target."
      fi
      TITLE="Bump version from $BASE_VERSION to $target"
    else
      TITLE="Reset version to $BASE_VERSION"
      BUMP_TYPE=none
    fi

    commit_bump
    if git push origin "HEAD:refs/heads/$HEAD_REF"; then
      VERSION_BUMPED=true
      BUMPED_VERSION=$target
      echo "Pushed '$TITLE' to $HEAD_REF. Its CI run needs approval, because GITHUB_TOKEN pushed it."
      return 0
    fi
    git fetch -q origin "$HEAD_REF"
    if [ "$(git rev-parse "origin/$HEAD_REF")" = "$tip" ]; then
      branch_error "The push to $HEAD_REF was refused and the branch hasn't moved. The token needs contents: write."
    fi
    echo "$HEAD_REF moved during attempt $attempt; redoing the bump from its new tip."
  done
  branch_error "$HEAD_REF kept moving; gave up after 3 attempts. Nothing was pushed."
}
