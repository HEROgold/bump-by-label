# bump-by-label

![](https://img.shields.io/badge/current_version-v5.1.0-blue)

## Overview

Bumps versions based on a merged PR's labels
This action uses Semantic versioning scheme, in the form of MAJOR.MINOR.PATCH

When a PR labelled `Major`, `Minor` or `Patch` merges, the action reads the
current version with `validate`, runs your `command` with that bump type,
reads the new version, commits the change on a
`workflow/bump-version-from-<old>-to-<new>` branch and opens a PR titled
`Bump version from <old> to <new>`. If the version didn't change, it logs
"No version bump required." and stops.

When that bump PR merges, the same workflow sees its head branch, skips the
label logic and tags the merge commit `v<new>` (see [Tags](#tags)).

## Inputs

| input | required | default | description |
|---|---|---|---|
| `github-token` | no | `${{ github.token }}` | Token for `gh` (labels, PRs) and, with `checkout`, for pushes. Pass a PAT or app token when the bump or tag pushes should start other workflows. |
| `command` | yes | | Command that bumps the version, run by bash. The bump type (`major`, `minor` or `patch`) replaces `{bump}`, or is appended when there is no `{bump}`. |
| `validate` | yes | | Command that prints the current version, run by bash. The first `MAJOR.MINOR.PATCH` in its output is used. |
| `base-branch` | no | `main` | Branch the bump PR is opened against. |
| `mode` | no | `pr` | `pr` opens a bump PR; `push` commits the bump on the base branch (see [Push mode](#push-mode)); `branch` commits the bump to the open PR's own branch (see [Branch mode](#branch-mode)). |
| `label-major` / `label-minor` / `label-patch` | no | `Major` / `Minor` / `Patch` | Bump labels. Whole names, ignoring case: `dispatch` is not `Patch`. Major beats minor beats patch. |
| `label-major-color` / `label-minor-color` / `label-patch-color` | no | `d93f0b` / `0e8a16` / `0075ca` | Colours for bump labels the action creates. |
| `labels-to-add` | no | | Comma-separated labels for the bump PR, e.g. `release,skip-changelog`. Missing ones are created. |
| `branch-prefix` | no | `workflow` | Prefix of the bump branch, `<prefix>/bump-version-from-<old>-to-<new>`. Empty for none. |
| `create-tag` | no | `true` | Tag the merge commit when a bump PR merges. |
| `tag-prefix` | no | `v` | Prefix of release tags. |
| `moving-tags` | no | `false` | Also move `v<major>` and `v<major>.<minor>` to each release. |
| `commit-user-name` | no | `github-actions[bot]` | Author and committer name of the bump commit. |
| `commit-user-email` | no | `41898282+github-actions[bot]@users.noreply.github.com` | Author and committer email; this one links commits to the bot account. |
| `checkout` | no | `true` | Check out the repository with full history and `github-token` first. Set it to `false` when an earlier step checks out, because a second checkout cleans the workspace. |

Every run creates the bump labels the repo doesn't have yet. Existing labels
are left alone, so colours and descriptions you changed stay.

## Outputs

Every run writes all outputs, also when it bumps nothing.

| output | value |
|---|---|
| `version-bumped` | `true` when a bump commit was made, else `false` |
| `previous-version` | version before the bump, from `validate`; empty when it wasn't read (no bump label) |
| `new-version` | version after the bump; empty when nothing was bumped |
| `bump-type` | `major` / `minor` / `patch` / `none` |
| `pr-number` | the bump PR's number; empty when there is none |
| `tag` | release tag this run created (merged bump PR or push mode); empty if none |

```yml
      - id: bump
        uses: herogold/bump-by-label@v5
        with: ...
      - if: steps.bump.outputs.version-bumped == 'true'
        run: echo "Bumped to ${{ steps.bump.outputs.new-version }} in #${{ steps.bump.outputs.pr-number }}"
```

## Commands

`command` and `validate` are run by bash, so quotes, pipes and `&&` work:
`semver-bump.sh pom.xml '<artifactId>demo</artifactId>\s*<version>'`.

### `{bump}`

Most tools take the bump type last, so it is appended:
`uv version --no-sync --bump` runs as `uv version --no-sync --bump patch`.
For tools that need it elsewhere, put `{bump}` where it goes:
`mytool bump {bump} --no-commit`.

### `semver-bump.sh`

Many ecosystems have no "bump by type" command. The action puts
[`scripts/semver-bump.sh`](scripts/semver-bump.sh) on PATH for `command` and
`validate`:

```sh
semver-bump.sh <file> <prefix-regex> <major|minor|patch|current>
```

It finds the first `MAJOR.MINOR.PATCH` in `<file>` that directly follows
`<prefix-regex>` (a Perl regex, may be empty), bumps it in place and prints the
new version. `current` prints the version without changing the file.

## Recipes

Each recipe is tested against a fixture project in
[`tests/fixtures`](tests/fixtures) ([`tests/ecosystems`](tests/ecosystems)).

| ecosystem | version lives in | `command` | `validate` |
|---|---|---|---|
| Python (uv) | `pyproject.toml` + `uv.lock` | `uv version --no-sync --bump` | `uv version --short` |
| Python (Poetry) | `pyproject.toml` | `poetry version` | `poetry version -s` |
| Python (Hatch) | `[tool.hatch.version]` path | `hatch version` | `hatch version` |
| JavaScript / TypeScript | `package.json` + lockfile | `npm version --no-git-tag-version` | `node -p "require('./package.json').version"` |
| Rust | `Cargo.toml` + `Cargo.lock` | `cargo set-version --bump` ([cargo-edit](https://github.com/killercup/cargo-edit)) | `cargo pkgid` |
| Rust (workspace) | `[workspace.package]` | `cargo set-version --workspace --bump` | `cargo pkgid -p <crate>` |
| Go | `VERSION` file (Go modules have no version field) | `semver-bump.sh VERSION ''` | `cat VERSION` |
| C# | `.csproj` `<Version>` | `semver-bump.sh demo.csproj '<Version>'` | `dotnet msbuild demo.csproj -getProperty:Version` |
| C / C++ (CMake) | `project(x VERSION 1.2.3)` | `semver-bump.sh CMakeLists.txt 'project\(demo VERSION '` | `semver-bump.sh CMakeLists.txt 'project\(demo VERSION ' current` |
| C / C++ (Meson) | `meson.build` `version:` | `semver-bump.sh meson.build "version: '"` | `meson introspect --projectinfo meson.build \| jq -r .version` |
| PHP | `composer.json` `version` | `semver-bump.sh composer.json '"version":\s*"'` | `jq -r .version composer.json` |
| Ruby | `.gemspec` | `semver-bump.sh demo.gemspec 'spec\.version\s*=\s*"'` | `ruby -e 'puts Gem::Specification.load("demo.gemspec").version'` |
| Java (Maven) | `pom.xml` | `semver-bump.sh pom.xml '<artifactId>demo</artifactId>\s*<version>'` | `mvn -q help:evaluate -Dexpression=project.version -DforceStdout` |
| Java (Gradle) | `gradle.properties` | `semver-bump.sh gradle.properties '^version='` | `gradle -q printVersion` (a task that prints `project.version`) |
| Elixir | `mix.exs` | `semver-bump.sh mix.exs 'version: "'` | `mix run --no-start -e 'IO.puts(Mix.Project.config()[:version])'` |
| Dart | `pubspec.yaml` | `semver-bump.sh pubspec.yaml '^version:\s*'` | `dart pub get >/dev/null && dart pub deps --json \| jq -r '.packages[] \| select(.kind == "root") \| .version'` |
| Anything else | a plain `VERSION` file | `semver-bump.sh VERSION ''` | `cat VERSION` |

Files that `command` or `validate` create (build dirs, caches) are committed
with the bump unless they are in `.gitignore`.

## Tags

A merged PR whose head branch matches
`^<branch-prefix>/bump-version-from-X.Y.Z-to-X.Y.Z$` is a bump PR. For it the
action:

1. tags the PR's merge commit `<tag-prefix><new>` and pushes the tag. An
   existing tag is never overwritten; the action logs it and goes on;
2. with `moving-tags: true`, moves `<tag-prefix><major>` and
   `<tag-prefix><major>.<minor>` to the merge commit (force-pushing only
   those tags);
3. sets `version-bumped=true`, `previous-version`, `new-version`, `bump-type`
   and `tag`, and bumps nothing.

Set `create-tag: false` when another workflow tags releases (for example one
that releases when "the tag doesn't exist yet"). Bump PRs are then still
recognised and skipped. GitHub Releases are not created.

## Push mode

With `mode: push` there is no bump PR. The action fetches the base branch,
checks out its tip, bumps, commits and `git push`es. If the push is rejected
because the base moved, it runs `validate`, `command` and `validate` again on
the new tip, up to 3 attempts. Two runs that bump at the same time therefore
make two bumps. If the push is rejected while the base hasn't moved (branch
protection, permissions), the run fails at once. It never uses `--force`,
`--force-with-lease` or `reset --hard` on the base branch.

Push mode fails if the working tree already has changes, such as files from
earlier steps that aren't in `.gitignore`, because it would commit them
straight to the base branch.

With `create-tag` on, the pushed commit is tagged right away, since no bump PR
will merge later. `pr-number` is empty.

- The pushed commit doesn't trigger another bump while the workflow runs
  only on `pull_request: closed`. With a `push` trigger and an app token or
  PAT, the bump commit starts a new run; skip it with a `github.actor` or
  commit-message check.
- Branch protection must let the token push. `GITHUB_TOKEN` can't bypass
  required reviews, so use an app token, a PAT or a ruleset bypass.
- Pushes made with `GITHUB_TOKEN` don't trigger other workflows.

Auto-merging the bump PR (#6) solves the same problem while keeping PR checks.

## Branch mode

With `mode: branch` the action bumps the version on the open PR's own branch,
as soon as a version label is added. Nothing waits for the merge. Trigger it
on `pull_request` with `types: [opened, reopened, labeled, unlabeled,
synchronize]`. It does nothing for any other action or event.

Each run compares the branch with its base branch. The branch ends up with one
bump commit on top of the base version, whatever the labels were before.
Changing the label from `Minor` to `Major` reverts the earlier bump commit and
adds a new one. Removing the label adds a `Reset version to X.Y.Z` commit.
Only commits by `commit-user-email` with a bump or reset title are reverted. If
the branch version differs from the base and no such commit explains it, the
run fails and asks you to fix the version by hand.

- The workflow needs `contents: write`. The run never uses `--force`. If the
  branch moved during the run, it redoes the bump from the new tip, up to 3
  attempts.
- Pushes made with `GITHUB_TOKEN` start CI runs that wait for approval. Use an
  app token or a PAT to avoid that.
- PRs from forks fail, because the token can't push to a fork.
- A PR with more than one version label fails.
- The working tree must be clean, and `validate` must not change files.
- These inputs are ignored: `base-branch` (the PR's base is used),
  `create-tag`, `tag-prefix`, `moving-tags`, `labels-to-add` and
  `branch-prefix`. No tag is created.

## Push events

The action also runs on a `push`, so a bump job can wait for the other jobs
of the same CI run with `needs:`. On an event without a `pull_request`, it
asks the GitHub API for the merged PR the pushed commit (`.after`, or
`GITHUB_SHA`) came from, and handles the push like that PR's merge. A merged
bump PR is tagged and a labelled PR is bumped, the same as on
`pull_request: closed`. A commit that came from no merged PR bumps nothing.

```yml
on:
  push:
    branches: [main]

jobs:
  test:
    # ...

  bump-version:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: astral-sh/setup-uv@v7
      - uses: herogold/bump-by-label@v5
        with:
          command: "uv version --no-sync --bump"
          validate: "uv version --short"
```

## Permissions and failures

The token needs `contents: write` and `pull-requests: write`. With
`GITHUB_TOKEN`, also turn on *Settings → Actions → General → Workflow
permissions → Allow GitHub Actions to create and approve pull requests*; the
action fails with that hint when `gh pr create` is refused.

The run fails, naming the command and its output, when `command` fails, or
when `validate` fails or prints no `MAJOR.MINOR.PATCH`.

## Example usage

```yml
# .github/workflows/auto-version-bump.yml
name: Bump Version By Labels

on:
  pull_request:
    types: [closed]
    branches:
      - main
      - master

jobs:
  bump-version:
    if: github.event.pull_request.merged == true && github.actor != 'github-actions[bot]'

    name: Bump Project Version
    runs-on: ubuntu-latest

    steps:
      - name: Install uv
        uses: astral-sh/setup-uv@v7

      - name: Bump by labels
        uses: herogold/bump-by-label@v5
        with:
          command: "uv version --no-sync --bump"
          validate: "uv version --short"
```

The action checks out the repository itself, with `fetch-depth: 0`.
Toolchain setup steps such as `astral-sh/setup-uv` can still come first,
because they install outside the workspace. Files an earlier step writes into
the workspace are removed by the checkout. Set `checkout: false` when the
workflow checks out on its own.

## Upgrading from v4

v5 renames two inputs and checks out the repository by default.

| v4 | v5 |
|---|---|
| `github_token` (required) | `github-token`, optional, defaults to `${{ github.token }}` |
| `base_branch` | `base-branch` |
| your own `actions/checkout` step with `fetch-depth: 0` | `checkout: true` (default) |

To upgrade:

1. Rename `base_branch` to `base-branch`.
2. Drop `github_token: ${{ secrets.GITHUB_TOKEN }}`. Pass `github-token` only
   for a PAT or app token.
3. Remove the `actions/checkout` step before the action, or keep it and set
   `checkout: false`. Keep it when an earlier step writes files the bump
   needs into the workspace.

Pin `@v5` to follow v5 releases, `@v5.0` for fixes only, or `@v5.0.0` for
one release.

## Development

`entrypoint.sh` only picks the path a run takes. The code for each path is in
[`lib/`](lib), and a path's files are loaded only when the run takes it:

| file | holds |
|---|---|
| `lib/inputs.sh` | reading and checking the `INPUT_*` variables |
| `lib/outputs.sh` | the action outputs, written on every exit |
| `lib/event.sh` | reading the event, finding the PR of a push, recognising bump branches |
| `lib/labels.sh` | creating labels, picking the bump type |
| `lib/version.sh` | running `validate` and `command`, committing |
| `lib/tag.sh` | release and moving tags (only with `create-tag`) |
| `lib/push-mode.sh` | push mode (only with `mode: push`) |
| `lib/branch-mode.sh` | the bump on a PR's own branch (only with `mode: branch`) |
| `lib/pr-mode.sh` | the bump branch and PR (only with `mode: pr`) |

Tests use [bats-core](https://github.com/bats-core/bats-core). They run
`entrypoint.sh` against a temp repo whose `origin` is a local bare repo, with a
stub `gh` that records its calls instead of calling GitHub.

```sh
bats tests/*.bats                    # entrypoint and semver-bump.sh
bats tests/ecosystems/rust.bats      # one ecosystem; skips if its tools are missing
```

CI runs each ecosystem in its own job with its toolchain installed
(`REQUIRE_TOOLCHAIN=1` turns a missing tool into a failure).

### Releasing

This repo releases itself with its own action. The version is in `VERSION`.

1. Merge a PR labelled `Major`, `Minor` or `Patch`. After CI passes on
   `main`, the `bump` job runs this repo's action (`uses: ./`) and opens a
   bump PR that changes `VERSION` and the badge above.
2. Merge the bump PR. CI runs again, and the `release` job
   ([`release.yml`](.github/workflows/release.yml)) tags the commit
   `vX.Y.Z`, creates the GitHub release with generated notes, and moves the
   `vX` and `vX.Y` tags to it.

A bump PR opened with `GITHUB_TOKEN` gets no CI run of its own. Its checks
run after it merges, before the release job.
