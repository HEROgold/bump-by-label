#!/usr/bin/env bats
# Bump labels: exact matching, custom names, auto-creation, labels on the PR.

setup() {
  load test_helper
  setup_repo
}

@test "labels that only contain a bump label's name don't bump" {
  bump dispatch minor-docs patches

  [ "$status" -eq 0 ]
  [[ "$output" == *"Version bump skipped"* ]]
  ! gh_called "pr create"
}

@test "bump labels match ignoring case" {
  bump MINOR

  [ "$status" -eq 0 ]
  assert_outputs bump-type=minor new-version=1.3.0
}

@test "custom bump label names" {
  export INPUT_LABEL_MAJOR="breaking" INPUT_LABEL_MINOR="feature" INPUT_LABEL_PATCH="fix"

  bump Major fix
  [ "$status" -eq 0 ]
  assert_outputs bump-type=patch new-version=1.2.4
}

@test "major beats minor beats patch with custom names" {
  export INPUT_LABEL_MAJOR="breaking" INPUT_LABEL_MINOR="feature" INPUT_LABEL_PATCH="fix"

  bump fix feature breaking
  [ "$status" -eq 0 ]
  assert_outputs bump-type=major
}

@test "missing bump labels are created on every run" {
  export GH_LABELS=$'major\nbug'

  bump documentation

  [ "$status" -eq 0 ]
  gh_called "label create Minor "
  gh_called "label create Patch "
  ! gh_called "label create Major "
  ! gh_called "--force"
}

@test "missing bump labels are created when the PR has bump labels too" {
  export GH_LABELS="Minor"

  bump Minor

  [ "$status" -eq 0 ]
  gh_called "label create Major "
  gh_called "label create Patch "
  ! gh_called "label create Minor "
}

@test "custom names and colours are used for created labels" {
  export INPUT_LABEL_MAJOR="breaking" INPUT_LABEL_MAJOR_COLOR="000000"

  bump

  [ "$status" -eq 0 ]
  gh_called "label create breaking --color 000000 "
}

@test "labels-to-add are created if missing and put on the bump PR" {
  export GH_LABELS=$'Major\nMinor\nPatch\nrelease'
  export INPUT_LABELS_TO_ADD="release, skip-changelog"

  bump Patch

  [ "$status" -eq 0 ]
  gh_called "label create skip-changelog "
  ! gh_called "label create release "
  gh_called "--label release --label skip-changelog"
}

@test "no --label without labels-to-add" {
  bump Patch

  [ "$status" -eq 0 ]
  ! gh_called "--label"
}
