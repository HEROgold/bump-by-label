#!/usr/bin/env bats

# Recipe: Elixir
#   command:  semver-bump.sh mix.exs 'version: "'
#   validate: mix run --no-start -e 'IO.puts(Mix.Project.config()[:version])'

setup() {
  load ../test_helper
  require mix
  setup_repo elixir
  export INPUT_COMMAND="semver-bump.sh mix.exs 'version: \"'"
  export INPUT_VALIDATE="mix run --no-start -e 'IO.puts(Mix.Project.config()[:version])'"
}

@test "Elixir: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 mix.exs
}

@test "Elixir: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 mix.exs
}

@test "Elixir: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 mix.exs
}
