# Shared setup for the bats tests: a work repo whose `origin` is a local bare
# repo, a fake pull_request event, and a stub `gh` that records its calls.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/entrypoint.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"
PATH="$REPO_ROOT/scripts:$PATH"

# Keep the developer's and the system's git config (autocrlf, signing, hooks)
# out of the test repos.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# setup_repo [fixture]: creates origin.git and a clone in $WORK, seeded with
# tests/fixtures/<fixture> (or a VERSION file with 1.2.3), and cd's into it.
setup_repo() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git init -q "$WORK"
  if [ -n "${1:-}" ]; then
    cp -R "$FIXTURES/$1/." "$WORK/"
  else
    echo '1.2.3' > "$WORK/VERSION"
  fi
  git -C "$WORK" add -A
  git -C "$WORK" -c user.name=dev -c user.email=dev@example.com commit -q -m "initial"
  git -C "$WORK" remote add origin "$ORIGIN"
  git -C "$WORK" push -q -u origin main
  cd "$WORK" || return 1

  stub_gh
  export GITHUB_ACTOR="octocat"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  export GITHUB_EVENT_PATH="$BATS_TEST_TMPDIR/event.json"
  : > "$GITHUB_OUTPUT"
  export INPUT_COMMAND="semver-bump.sh VERSION ''"
  export INPUT_VALIDATE="cat VERSION"
  export INPUT_BASE_BRANCH="main"
  pr_event
}

# stub_gh: puts a fake `gh` first on PATH. Each call is appended to $GH_LOG
# as one shell-quoted line. Behaviour is steered by:
#   GH_PR_VIEW_EXIT  exit status of `gh pr view` (default 1: no PR yet)
#   GH_LABELS        output of `gh label list` (newline-separated names)
#   GH_PR_CREATE_EXIT    make `gh pr create` fail with this status
#   GH_PR_CREATE_STDERR  what `gh pr create` prints on stderr
stub_gh() {
  GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : > "$GH_LOG"
  export GH_LOG
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$GH_LOG"
echo >> "$GH_LOG"
case "$1 $2" in
  "pr view")
    if [ "${GH_PR_VIEW_EXIT:-1}" -eq 0 ]; then echo "${GH_PR_NUMBER:-7}"; fi
    exit "${GH_PR_VIEW_EXIT:-1}" ;;
  "pr create")
    if [ "${GH_PR_CREATE_EXIT:-0}" -ne 0 ]; then
      echo "${GH_PR_CREATE_STDERR:-}" >&2
      exit "$GH_PR_CREATE_EXIT"
    fi
    echo "https://github.com/owner/repo/pull/${GH_PR_NUMBER:-7}"
    if [ -n "${GH_PR_CREATE_STDERR:-}" ]; then
      echo "$GH_PR_CREATE_STDERR" >&2
    fi ;;
  "label list") printf '%s\n' "${GH_LABELS:-}" | sed '/^$/d' ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# pr_event [label...]: writes a merged pull_request event with these labels.
# PR_HEAD_REF and MERGE_SHA override the head branch and merge commit.
pr_event() {
  jq -n \
    --arg head "${PR_HEAD_REF:-feature}" \
    --arg sha "${MERGE_SHA:-$(git rev-parse HEAD)}" \
    '{pull_request: {number: 42, merged: true, head: {ref: $head}, base: {ref: "main"},
      merge_commit_sha: $sha, labels: ($ARGS.positional | map({name: .}))}}' \
    --args "$@" > "$GITHUB_EVENT_PATH"
}

# bump <label...>: runs the entrypoint for a merged PR with these labels.
# Its output is echoed so bats shows it when the test fails.
bump() {
  pr_event "$@"
  run bash "$ENTRYPOINT"
  # shellcheck disable=SC2154 # `run` sets $output
  echo "$output"
}

# bump_branch <old> <new>: the name of the branch a bump from old to new uses.
bump_branch() {
  echo "${INPUT_BRANCH_PREFIX:-workflow}/bump-version-from-$1-to-$2"
}

# assert_bumped <old> <new> <file...>: the bump branch on origin has <new>
# in each file, and main still has <old>.
assert_bumped() {
  local old=$1 new=$2 file branch
  branch=$(bump_branch "$old" "$new")
  shift 2
  for file in "$@"; do
    remote_file "$branch" "$file" | grep -qF "$new" || {
      echo "$file on $branch doesn't contain $new:" >&2
      remote_file "$branch" "$file" >&2
      return 1
    }
    remote_file main "$file" | grep -qF "$old"
  done
}

# gh_called <text>: true when a recorded gh call contains <text>.
gh_called() {
  grep -qF -- "$1" "$GH_LOG"
}

# remote_file <branch> <path>: prints a file from a branch on origin.
remote_file() {
  git --git-dir="$ORIGIN" show "$1:$2"
}

# require <tool...>: skips the test when a tool is missing, or fails it when
# REQUIRE_TOOLCHAIN=1 (set in CI so a broken setup step can't pass silently).
require() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if [ "${REQUIRE_TOOLCHAIN:-}" = 1 ]; then
        echo "required tool not found: $tool" >&2
        return 1
      fi
      skip "$tool not installed"
    fi
  done
}

# output <name>: the last value written for <name> to $GITHUB_OUTPUT.
output() {
  grep "^$1=" "$GITHUB_OUTPUT" | tail -n 1 | cut -d= -f2-
}

# assert_outputs <name=value...>: every action output was written, and the
# named ones have these values.
assert_outputs() {
  local name pair
  for name in version-bumped previous-version new-version bump-type pr-number tag; do
    grep -q "^$name=" "$GITHUB_OUTPUT" || {
      echo "output $name was not written" >&2
      return 1
    }
  done
  for pair in "$@"; do
    [ "$(output "${pair%%=*}")" = "${pair#*=}" ] || {
      echo "output ${pair%%=*} is '$(output "${pair%%=*}")', expected '${pair#*=}'" >&2
      return 1
    }
  done
}
