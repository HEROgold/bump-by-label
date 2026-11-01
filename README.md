# bump-by-label

![](https://img.shields.io/badge/current_version-v3.0.0-blue)

## Overview

Bumps versions based on a merged PR's labels
This action uses Semantic versioning scheme, in the form of MAJOR.MINOR.PATCH

When a PR labelled `Major`, `Minor` or `Patch` merges, the action runs your
`command` with that bump type, reads the new version with `validate`, commits
the change on a `bump-version-<new>` branch and opens a PR for it.

## Inputs

| input | required | default | description |
|---|---|---|---|
| `github_token` | yes | | Token for `gh` (labels, PRs). |
| `command` | yes | | Command that bumps the version, run by bash. The bump type (`major`, `minor` or `patch`) replaces `{bump}`, or is appended when there is no `{bump}`. |
| `validate` | yes | | Command that prints the current version, run by bash. The first `MAJOR.MINOR.PATCH` in its output is used. |
| `base_branch` | no | `main` | Branch the bump PR is opened against. |
| `commit-user-name` | no | `github-actions[bot]` | Author and committer name of the bump commit. |
| `commit-user-email` | no | `41898282+github-actions[bot]@users.noreply.github.com` | Author and committer email; this one links commits to the bot account. |

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
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install uv
        uses: astral-sh/setup-uv@v6

      - name: Bump by labels
        uses: herogold/bump-by-label@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          command: "uv version --no-sync --bump"
          validate: "uv version --short"
```

## Development

Tests use [bats-core](https://github.com/bats-core/bats-core). They run
`entrypoint.sh` against a temp repo whose `origin` is a local bare repo, with a
stub `gh` that records its calls instead of calling GitHub.

```sh
bats tests/*.bats                    # entrypoint and semver-bump.sh
bats tests/ecosystems/rust.bats      # one ecosystem; skips if its tools are missing
```

CI runs each ecosystem in its own job with its toolchain installed
(`REQUIRE_TOOLCHAIN=1` turns a missing tool into a failure).
