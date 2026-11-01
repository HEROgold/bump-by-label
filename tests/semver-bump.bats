#!/usr/bin/env bats

setup() {
  load test_helper
  cd "$BATS_TEST_TMPDIR"
}

@test "bumps patch, minor and major and prints the new version" {
  echo '1.2.3' > VERSION

  run semver-bump.sh VERSION '' patch
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]
  [ "$(cat VERSION)" = "1.2.4" ]

  run semver-bump.sh VERSION '' minor
  [ "$output" = "1.3.0" ]

  run semver-bump.sh VERSION '' major
  [ "$output" = "2.0.0" ]
  [ "$(cat VERSION)" = "2.0.0" ]
}

@test "current prints the version without changing the file" {
  echo '1.2.3' > VERSION

  run semver-bump.sh VERSION '' current
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
  [ "$(cat VERSION)" = "1.2.3" ]
}

@test "only the first version after the prefix changes" {
  cat > pom.xml <<'XML'
<parent><version>9.9.9</version></parent>
<artifactId>demo</artifactId>
<version>1.2.3</version>
<dependency><version>1.2.3</version></dependency>
XML

  run semver-bump.sh pom.xml '<artifactId>demo</artifactId>\s*<version>' minor
  [ "$status" -eq 0 ]
  [ "$output" = "1.3.0" ]
  grep -qF '<parent><version>9.9.9</version></parent>' pom.xml
  grep -qF '<version>1.3.0</version>' pom.xml
  grep -qF '<dependency><version>1.2.3</version></dependency>' pom.xml
}

@test "capture groups in the prefix don't shift the version" {
  echo 'project(demo VERSION 1.2.3 LANGUAGES NONE)' > CMakeLists.txt

  run semver-bump.sh CMakeLists.txt 'project\((demo|other) VERSION ' patch
  [ "$output" = "1.2.4" ]
  grep -qF 'project(demo VERSION 1.2.4 LANGUAGES NONE)' CMakeLists.txt
}

@test "keeps CRLF line endings" {
  printf 'name=demo\r\nversion=1.2.3\r\n' > gradle.properties

  run semver-bump.sh gradle.properties '^version=' patch
  [ "$status" -eq 0 ]
  [ "$(cat gradle.properties)" = "$(printf 'name=demo\r\nversion=1.2.4\r')" ]
}

@test "fails when no version follows the prefix" {
  echo 'version = "dev"' > VERSION

  run semver-bump.sh VERSION 'version = "' patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"no MAJOR.MINOR.PATCH version"* ]]
  [ "$(cat VERSION)" = 'version = "dev"' ]
}

@test "fails on a missing file or an unknown part" {
  run semver-bump.sh missing.txt '' patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing.txt"* ]]

  echo '1.2.3' > VERSION
  run semver-bump.sh VERSION '' huge
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}
