# bump-by-label

![](https://img.shields.io/badge/current_version-v1.0.0-blue)

## Overview

Bumps versions based on a merged PR's labels
This action uses Semantic versioning scheme, in the form of MAJOR.MINOR.PATCH

## Inputs

### `command`

**Required** The command to run, where the *new* version will be inserted at {version}. I.E: `uv version --bump {version}`.

### `validate`

**Required** The command to run, to get the new version. I.E: `uv version`.

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

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.*"

      - name: Install uv
        uses: astral-sh/setup-uv@v4
        with:
          version: "latest"

      - name: Bump by labels
        uses: herogold/bump-by-label@v1.0.0
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          command: "uv version"
          validate: "uv version --bump"

```
