# bump-by-label

![](https://img.shields.io/badge/current_version-v0.0.0-blue)

## Overview

Bumps versions based on a merged PR's labels
This action uses Semantic versioning scheme, in the form of MAJOR.MINOR.PATCH

## Inputs

### `command`

**Required** The command to run, where the *new* version will be inserted at {version}. Default: `uv version --bump {version}`.

## Example usage

```yml
uses: herogold/bump-by-label
with:
  command: 'uv version --bump'
```
