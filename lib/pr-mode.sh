# shellcheck shell=bash
# shellcheck disable=SC2034 # the outputs read these

# Loaded only with mode: pr.

# publish_pr: bumps, force-pushes the bump branch and opens a bump PR, or
# updates the one that is already open for that branch.
publish_pr() {
  local branch_name existing_pr pr_output pr_status=0 label
  local -a pr_args extra_labels

  bump_version
  stop_if_unchanged

  # Old and new version are both in the name, so rerunning the same bump
  # force-pushes the same branch and a different bump gets its own.
  # read_bump_pr recognises merged bump PRs by this name.
  branch_name="$(bump_branch_start)${OLD_VERSION}-to-${NEW_VERSION}"

  # Always rebuild the branch from the current default branch tip rather than
  # reusing whatever the existing local/remote branch points at: the bump
  # branch is disposable and regenerated on every run, so a --force push is the
  # correct (and only reliable) way to publish it.
  git checkout -B "$branch_name" "origin/${BASE_BRANCH}"
  commit_bump
  git push --force origin "$branch_name"
  VERSION_BUMPED=true
  BUMPED_VERSION=$NEW_VERSION

  if existing_pr=$(gh pr view "$branch_name" --json number --jq .number 2>/dev/null); then
    PR_NUMBER=$existing_pr
    echo "PR #$PR_NUMBER for $branch_name already exists; updated it with the force-push above."
    return 0
  fi

  pr_args=(
    --title "$TITLE"
    --body "Automated version bump from ${OLD_VERSION} to ${NEW_VERSION}."
    --base "$BASE_BRANCH"
    --head "$branch_name"
  )
  if [ -n "${GITHUB_ACTOR:-}" ]; then
    pr_args+=(--assignee "$GITHUB_ACTOR")
  fi
  IFS=',' read -ra extra_labels <<<"$LABELS_TO_ADD"
  for label in "${extra_labels[@]}"; do
    label="${label#"${label%%[![:space:]]*}"}"
    label="${label%"${label##*[![:space:]]}"}"
    if [ -n "$label" ]; then
      ensure_label "$label" "ededed" "Added to version bump PRs by bump-by-label"
      pr_args+=(--label "$label")
    fi
  done

  pr_output=$(gh pr create "${pr_args[@]}" 2>&1) || pr_status=$?
  echo "$pr_output"
  if [ "$pr_status" -ne 0 ]; then
    if grep -q "not permitted to create or approve pull requests" <<<"$pr_output"; then
      echo "Error: GitHub Actions may not open PRs in this repository. Turn on" \
        "Settings > Actions > General > Workflow permissions >" \
        "\"Allow GitHub Actions to create and approve pull requests\"," \
        "or pass a PAT or app token as github-token." >&2
    else
      echo "Error: gh pr create failed (exit $pr_status)." >&2
    fi
    exit "$pr_status"
  fi
  # gh pr create prints the new PR's URL, which ends in its number. The output
  # includes stderr, so take the URL rather than the last line.
  PR_NUMBER=$(grep -Eo '/pull/[0-9]+' <<<"$pr_output" | tail -n 1) || true
  PR_NUMBER=${PR_NUMBER##*/}
}
