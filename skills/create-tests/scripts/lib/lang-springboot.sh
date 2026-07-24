#!/usr/bin/env bash
# lang-springboot.sh — Spring Boot / Java (JUnit5 + Maven) implementation.
# Uniform interface: springboot_spec_path / springboot_run_tests. Sourced by common.sh.

# springboot_spec_path <source-file> → conventional test path under src/test/<java|kotlin>.
# src/main/java/<pkg>/Foo.java     → src/test/java/<pkg>/FooTest.java
# src/main/kotlin/<pkg>/Foo.kt     → src/test/kotlin/<pkg>/FooTest.kt
springboot_spec_path() {
  local src="$1" rel base dir ext testroot
  case "$src" in
    *.kt)   ext=kt;   testroot=src/test/kotlin ;;
    *)      ext=java; testroot=src/test/java ;;
  esac
  rel="${src#src/main/java/}"
  rel="${rel#src/main/kotlin/}"        # strip source root if present (either layout)
  dir="$(dirname "$rel")"
  base="$(basename "$rel" ".$ext")"
  if [ "$dir" = "." ]; then
    printf '%s/%sTest.%s' "$testroot" "$base" "$ext"
  else
    printf '%s/%s/%sTest.%s' "$testroot" "$dir" "$base" "$ext"
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
