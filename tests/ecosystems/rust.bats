#!/usr/bin/env bats

# Recipe: Rust
#   command:  cargo set-version --bump
#   validate: cargo pkgid

setup() {
  load ../test_helper
  require cargo cargo-set-version
  setup_repo rust
  export INPUT_COMMAND='cargo set-version --bump'
  export INPUT_VALIDATE='cargo pkgid'
}

@test "Rust: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 Cargo.toml Cargo.lock
}

@test "Rust: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 Cargo.toml Cargo.lock
}

@test "Rust: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 Cargo.toml Cargo.lock
}
