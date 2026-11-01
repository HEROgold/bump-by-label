#!/usr/bin/env bats

# Recipe: Java (Maven)
#   command:  semver-bump.sh pom.xml '<artifactId>demo</artifactId>\s*<version>'
#   validate: mvn -q help:evaluate -Dexpression=project.version -DforceStdout

setup() {
  load ../test_helper
  require mvn
  setup_repo maven
  export INPUT_COMMAND="semver-bump.sh pom.xml '<artifactId>demo</artifactId>\\s*<version>'"
  export INPUT_VALIDATE='mvn -q help:evaluate -Dexpression=project.version -DforceStdout'
}

@test "Java (Maven): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 pom.xml
}

@test "Java (Maven): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 pom.xml
}

@test "Java (Maven): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 pom.xml
}
