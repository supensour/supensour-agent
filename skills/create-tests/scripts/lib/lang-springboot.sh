#!/usr/bin/env bash
# lang-springboot.sh — Spring Boot / Java (JUnit5 + Maven) implementation.
# Uniform interface: springboot_spec_path / springboot_run_tests. Sourced by common.sh.

# springboot_spec_path <source-file> → conventional test path under src/test/java.
# src/main/java/<pkg>/Foo.java → src/test/java/<pkg>/FooTest.java
springboot_spec_path() {
  local src="$1" rel base dir
  rel="${src#src/main/java/}"          # strip source root if present
  dir="$(dirname "$rel")"
  base="$(basename "$rel" .java)"
  if [ "$dir" = "." ]; then
    printf 'src/test/java/%sTest.java' "$base"
  else
    printf 'src/test/java/%s/%sTest.java' "$dir" "$base"
  fi
}

# springboot_class <source-or-test-file> → bare class name for -Dtest (no package, no .java).
springboot_class() {
  local b; b="$(basename "$1" .java)"; printf '%s' "$b"
}

# springboot_run_tests <ClassName|source-file> → mvn test -Dtest=<Class>.
# Accepts a class name or a path (path → class name extracted). Prints output; exit = result.
springboot_run_tests() {
  local arg="$1" cls
  case "$arg" in
    *.java) cls="$(springboot_class "$arg")" ;;
    *)      cls="$arg" ;;
  esac
  # Ensure the class targets a *Test (so passing a source class still runs its test).
  case "$cls" in *Test|*Tests) : ;; *) cls="${cls}Test" ;; esac
  [ -f pom.xml ] || { warn "No pom.xml — run from the Maven project root."; return 2; }
  mvn test -Dtest="$cls"
}
