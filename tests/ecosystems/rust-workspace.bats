#!/usr/bin/env bats

# Recipe: Rust (workspace)
#   command:  cargo set-version --workspace --bump
#   validate: cargo pkgid -p demo-app

setup() {
  load ../test_helper
  require cargo cargo-set-version
  setup_repo rust-workspace
  export INPUT_COMMAND='cargo set-version --workspace --bump'
  export INPUT_VALIDATE='cargo pkgid -p demo-app'
}

@test "Rust (workspace): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 Cargo.toml Cargo.lock crates/app/Cargo.toml
}

@test "Rust (workspace): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 Cargo.toml Cargo.lock crates/app/Cargo.toml
}

@test "Rust (workspace): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 Cargo.toml Cargo.lock crates/app/Cargo.toml
}

@test "Rust (workspace): the workspace still builds after a bump" {
  bump Patch
  [ "$status" -eq 0 ]
  git checkout -q "$(bump_branch 1.2.3 1.2.4)"
  [ "$(cargo run -q -p demo-app)" = "1.2.4" ]
}
