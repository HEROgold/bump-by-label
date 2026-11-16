#!/usr/bin/env bats

# Recipe: C#
#   command:  semver-bump.sh demo.csproj '<Version>'
#   validate: dotnet msbuild demo.csproj -getProperty:Version

setup() {
  load ../test_helper
  require dotnet
  # MSBuild keeps worker and server processes alive for 15 minutes after a
  # build. They hold bats' output open, so bats waits for them to exit.
  export MSBUILDDISABLENODEREUSE=1
  export DOTNET_CLI_USE_MSBUILD_SERVER=0
  setup_repo csharp
  export INPUT_COMMAND="semver-bump.sh demo.csproj '<Version>'"
  export INPUT_VALIDATE='dotnet msbuild demo.csproj -getProperty:Version'
}

@test "C#: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 demo.csproj
}

@test "C#: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 demo.csproj
}

@test "C#: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 demo.csproj
}
