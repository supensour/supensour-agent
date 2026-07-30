#!/usr/bin/env bash
# lang-springboot.sh — Spring Boot / Java + Kotlin (JUnit5) implementation.
# Uniform interface: springboot_spec_path / springboot_run_tests / springboot_coverage_scan.
# Build tool: Maven (pom.xml) or Gradle (build.gradle[.kts]); overridable via project config.

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

# springboot_class <source-or-test-file> → bare class name for -Dtest / --tests
# (no package, no extension). Handles .java and .kt.
springboot_class() {
  local b; b="$(basename "$1")"
  b="${b%.java}"; b="${b%.kt}"
  printf '%s' "$b"
}

# _sb_build_tool → maven | gradle | "" (none detected).
_sb_build_tool() {
  [ -f pom.xml ] && { printf 'maven'; return; }
  { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && { printf 'gradle'; return; }
  printf ''
}

# _sb_gradle_cmd → ./gradlew when wrapped, else gradle.
_sb_gradle_cmd() { [ -x ./gradlew ] && printf './gradlew' || printf 'gradle'; }

# _sb_cmd_template <coverage|plain> → command template. Placeholders: {class} {classes} {spec}.
# {class}/{classes} = comma-separated bare class names.
_sb_cmd_template() {
  local mode="$1" t tool
  if [ "$mode" = coverage ]; then
    t="$(proj_get project test_command_coverage 2>/dev/null || true)"
  else
    t="$(proj_get project test_command 2>/dev/null || true)"
  fi
  [ -n "$t" ] && { printf '%s' "$t"; return; }

  tool="$(_sb_build_tool)"
  case "$tool:$mode" in
    maven:coverage)  printf 'mvn -q test -Dtest={classes} jacoco:report' ;;
    maven:*)         printf 'mvn test -Dtest={classes}' ;;
    gradle:coverage) printf '%s test --tests {classes} jacocoTestReport' "$(_sb_gradle_cmd)" ;;
    gradle:*)        printf '%s test --tests {classes}' "$(_sb_gradle_cmd)" ;;
    *)               printf '' ;;
  esac
}

# springboot_test_command <coverage|plain> <class-or-path>... → exact command string.
# Exposed so the analyst can put a verbatim `Run:` line in a plan.
springboot_test_command() {
  local mode="$1"; shift
  local classes="" c cmd
  for c in "$@"; do
    c="$(springboot_class "$c")"
    case "$c" in *Test|*Tests) : ;; *) c="${c}Test" ;; esac
    classes="${classes:+$classes,}$c"
  done
  cmd="$(_sb_cmd_template "$mode")"
  [ -n "$cmd" ] || { printf ''; return; }
  cmd="${cmd//\{classes\}/$classes}"
  cmd="${cmd//\{class\}/$classes}"
  cmd="${cmd//\{spec\}/$*}"
  # Accepted for template symmetry with vue; JaCoCo's reporters come from the build
  # config, so there is nothing to inject here.
  cmd="${cmd//\{reporter_args\}/}"
  printf '%s' "$cmd" | sed -E 's/[[:space:]]{2,}/ /g; s/[[:space:]]+$//'
}

# _sb_jacoco_csv → path of the JaCoCo csv report for the detected build tool, if present.
_sb_jacoco_csv() {
  local p
  for p in target/site/jacoco/jacoco.csv \
           build/reports/jacoco/test/jacocoTestReport.csv \
           build/reports/jacoco/jacocoTestReport/jacocoTestReport.csv; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# springboot_coverage_scan <source-file>... → keyed TSV per source:
#   <src>\tinstructions=<n>\tbranches=<n>\tmethods=<n>\tlines=<n>\t<SKIP|GENERATE>
# Runs the existing *Test classes for the given sources with a coverage report, then reads
# the JaCoCo csv. SKIP when every metric >= ${CT_THRESHOLD:-100}. Fail-safe: no build tool,
# no existing tests, a failing run or no report → GENERATE for all (never skip on no data).
springboot_coverage_scan() {
  local srcs=("$@") src test tests=() csv cmd
  local threshold="${CT_THRESHOLD:-100}"

  _sb_scan_all_generate() {
    local s; for s in "${srcs[@]}"; do
      printf '%s\tinstructions=-\tbranches=-\tmethods=-\tlines=-\tGENERATE\n' "$s"
    done
  }

  [ -n "$(_sb_build_tool)" ] || { warn "No pom.xml / build.gradle — coverage scan skipped."; _sb_scan_all_generate; return 0; }

  for src in "${srcs[@]}"; do
    test="$(springboot_spec_path "$src")"
    [ -f "$test" ] && tests+=("$test")
  done
  [ "${#tests[@]}" -gt 0 ] || { log "No existing test classes for the target set — all targets need generation."; _sb_scan_all_generate; return 0; }

  cmd="$(springboot_test_command coverage "${tests[@]}")"
  [ -n "$cmd" ] || { warn "No test command resolved — treating all targets as GENERATE."; _sb_scan_all_generate; return 0; }

  assert_allowed_cmd "$cmd"
  log "▶ coverage scan (threshold ${threshold}%): $cmd"
  if ! eval "$cmd" >/dev/null 2>&1; then
    warn "Existing tests failed or JaCoCo is not configured — treating all targets as GENERATE."
    _sb_scan_all_generate; return 0
  fi

  csv="$(_sb_jacoco_csv)" || { warn "No JaCoCo csv report found (csv reporter off?) — treating all targets as GENERATE."; _sb_scan_all_generate; return 0; }

  for src in "${srcs[@]}"; do
    local rel pkg cls
    rel="${src#src/main/java/}"; rel="${rel#src/main/kotlin/}"
    cls="$(springboot_class "$rel")"
    pkg="$(dirname "$rel")"; pkg="${pkg//\//.}"; [ "$pkg" = "." ] && pkg=""
    awk -F, -v pkg="$pkg" -v cls="$cls" -v src="$src" -v min="$threshold" '
      NR == 1 { next }
      $2 == pkg && $3 == cls {
        i = pct_of($4, $5); b = pct_of($6, $7); l = pct_of($8, $9); m = pct_of($12, $13)
        full = (i >= min && b >= min && l >= min && m >= min)
        printf "%s\tinstructions=%.2f\tbranches=%.2f\tmethods=%.2f\tlines=%.2f\t%s\n", \
               src, i, b, m, l, (full ? "SKIP" : "GENERATE")
        found = 1; exit
      }
      END { if (!found) printf "%s\tinstructions=-\tbranches=-\tmethods=-\tlines=-\tGENERATE\n", src }
      function pct_of(missed, covered) {
        total = missed + covered
        return (total == 0) ? 100 : (covered * 100 / total)
      }
    ' "$csv"
  done
}

# springboot_run_tests <ClassName|source-file|test-file> → run that test class.
# Accepts a class name or a path (.java/.kt); a source class is mapped to its *Test.
springboot_run_tests() {
  local cmd
  [ -n "$(_sb_build_tool)" ] || { warn "No pom.xml / build.gradle — run from the project root."; return 2; }
  cmd="$(springboot_test_command plain "$1")"
  [ -n "$cmd" ] || { warn "No test command resolved."; return 2; }
  run_checked "$cmd"
}
