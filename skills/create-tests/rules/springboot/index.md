# Spring Boot / Java test conventions (entry)

Extends `rules/generic.md`. Entry point for the `springboot` language module — JUnit 5 (Jupiter) +
Mockito. Load this, then the relevant `types/<type>.md`, then any matching `cases/*`.

## Framework & tooling

- **Runner:** JUnit Jupiter (`org.junit.jupiter.api.*`). Build: Maven (`pom.xml`) or Gradle.
- **Mocking:** Mockito (`org.mockito.*`); Spring context mocks via `@MockBean` / `@MockitoSpyBean`.
- **Async:** Awaitility (`await().atMost(...).until(...)`). Web: `WebTestClient` / `MockMvc` / RestAssured.

## File naming & location

- **Name:** `<ClassName>Test.java` (or `<ClassName>Tests.java` to match an existing project).
  e.g. `ConverterUtils.java` → `ConverterUtilsTest.java`.
- **Location:** `src/test/java/`, **package mirrors the source** (`com.x.utils` source →
  `com.x.utils` test). Same package gives package-private access.
- **Kotlin sources** (`.kt`): same conventions, mirrored under the Kotlin source set —
  `src/main/kotlin/<pkg>/Foo.kt` → `src/test/kotlin/<pkg>/FooTest.kt`. JUnit 5 + Mockito usage is
  otherwise identical (Kotlin-specific idioms like `mockk` are not assumed unless the project uses them).

## Running + coverage

Use `scripts/run-tests.sh springboot <ClassName>` — it resolves the build tool for you
(`project.test_command` in `<repo>/.supensour/config/config.yaml` → `pom.xml` → `build.gradle[.kts]`).
`scripts/test-command.sh springboot coverage --spec <TestClass>` prints the resolved command.

```bash
# Maven
mvn test -Dtest=<ClassName>                         # single test class
mvn test -Dtest='<Class1>,<Class2>'                 # several
mvn -q test -Dtest=<Classes> jacoco:report          # + coverage report (jacoco if configured)

# Gradle
./gradlew test --tests <ClassName>
./gradlew test --tests <Classes> jacocoTestReport   # + coverage report
```

Run once to verify; don't re-run after every edit.

## Coverage goals

- High coverage on utilities/services: every public method, every branch, edge + error paths.
- Assert the **error path contract** (exception type/message, HTTP status + body), not just that it throws.
- Minimum viable — cover the behavior and branches; skip redundant permutations.

## References

- Test types: [types/unit.md](types/unit.md)  (integration: later)
- Cases: (none yet — add under `cases/` as patterns emerge, e.g. testcontainers, transactional rollback)
