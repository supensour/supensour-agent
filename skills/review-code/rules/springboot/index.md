# Spring Boot review rules

Extends `generic.md` for Spring Boot / Java / Kotlin projects.

## Security (Spring-specific)

- [ ] No `@Query` with string concatenation — use parameterized queries or Spring Data method naming
- [ ] `@PreAuthorize` / `@Secured` on controller methods needing auth
- [ ] CSRF protection not disabled without justification
- [ ] Spring Security filter chain: order matters — verify filter placement
- [ ] No `@CrossOrigin("*")` on controllers — configure CORS centrally with allowed origins
- [ ] Request body size limits configured — prevent large payload DoS
- [ ] Actuator endpoints secured — `/actuator/**` not publicly accessible in production
- [ ] No sensitive data in Spring profiles committed to repo (`application-prod.yml` with passwords)
- [ ] `@Valid` / `@Validated` on request body DTOs — never trust client input
- [ ] Jackson deserialization: no `@JsonTypeInfo` with default typing enabled (RCE vector)

## Architecture (Spring-specific)

- [ ] Controller → Service → Repository layering respected — no repository calls from controllers
- [ ] DTOs separate from entities — no JPA entities in API request/response
- [ ] `@Transactional` at service layer, not repository or controller
- [ ] `@Transactional(readOnly = true)` for read operations
- [ ] No circular `@Autowired` dependencies — redesign if needed
- [ ] Configuration in `@ConfigurationProperties` classes, not scattered `@Value`
- [ ] Exception handling via `@ControllerAdvice` / `@RestControllerAdvice` — not per-controller try/catch
- [ ] Feature-based package structure preferred over layer-based for larger services
- [ ] No business logic in controllers — controllers map HTTP to service calls
- [ ] Interfaces for services only when multiple implementations exist or needed for testing

## Performance (Spring-specific)

- [ ] JPA: no eager fetching (`FetchType.EAGER`) on collections — use `LAZY` + fetch join
- [ ] JPA: `@BatchSize` or `@Fetch(FetchMode.SUBSELECT)` for known N+1 patterns
- [ ] No `findAll()` without pagination on potentially large tables
- [ ] `@Cacheable` cache names and keys correct — stale cache worse than no cache
- [ ] `@Async` methods return `CompletableFuture`, not `void` (unless fire-and-forget intentional)
- [ ] Connection pool sizing: HikariCP defaults reviewed for expected load
- [ ] No blocking calls in reactive (WebFlux) pipelines — `Schedulers.boundedElastic()` for unavoidable blocking
- [ ] Database migrations (Flyway/Liquibase): no full table locks on large tables in production
- [ ] Bulk operations use `saveAll()` / batch insert, not loop of `save()`

## Code quality (Spring-specific)

- [ ] Lombok: `@Data` avoided on JPA entities (breaks equals/hashCode) — use `@Getter @Setter @ToString(exclude=...)`
- [ ] `Optional` used for return types, never for fields or method parameters
- [ ] Null checks: `@NonNull` annotations or Kotlin nullability, not defensive `if (x != null)` everywhere
- [ ] Logging: SLF4J with parameterized messages (`log.info("User {} logged in", userId)`), not string concatenation
- [ ] No `System.out.println` — use proper logging
- [ ] Constants: `static final` in dedicated class or enum, not scattered magic values
- [ ] `record` types for immutable DTOs (Java 16+)
- [ ] Resource cleanup: try-with-resources for `InputStream`, `Connection`, etc.
- [ ] Spring profiles: test profile not connect to real external services

## Test coverage (Spring-specific)

- [ ] `@WebMvcTest` for controller tests — not full `@SpringBootTest` unless integration test
- [ ] `@DataJpaTest` for repository tests with embedded DB
- [ ] Service tests mock repositories with `@MockBean` or Mockito
- [ ] `@Transactional` on test class for auto-rollback (or `@DirtiesContext` if needed)
- [ ] Integration tests use `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `TestRestTemplate`
- [ ] Test containers for external dependencies (DB, Redis, Kafka) in integration tests
- [ ] `@ParameterizedTest` for boundary value testing
- [ ] Exception paths tested: verify correct HTTP status and error response body
