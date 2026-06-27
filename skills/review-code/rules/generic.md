# Generic review rules

Base rules. Language modules override/extend.

## Security

- [ ] No hardcoded secrets, tokens, passwords, API keys in code or config
- [ ] No SQL/NoSQL injection — all queries parameterized
- [ ] No XSS — user input sanitized before rendering
- [ ] No path traversal — file paths validated and sandboxed
- [ ] No insecure deserialization of untrusted data
- [ ] No sensitive data in logs (PII, tokens, passwords)
- [ ] No sensitive data in URL query parameters
- [ ] Auth/authz checks on all protected endpoints
- [ ] CORS restrictive, not `*` in production
- [ ] Crypto uses standard libraries, not custom
- [ ] Dependencies: no known CVEs in added/updated packages
- [ ] File uploads: type/size validated, no execution of uploaded content

## Architecture & design

- [ ] Single responsibility — one thing per function/class
- [ ] No god objects/functions (>200 lines warrants scrutiny)
- [ ] Dependencies flow inward (domain not depend on infrastructure)
- [ ] No circular dependencies between modules
- [ ] Abstractions justified — no premature abstraction for single use
- [ ] Public API surface minimal — no exposed internals
- [ ] Error types specific, not generic catch-all
- [ ] Configuration externalized, not hardcoded
- [ ] No tight coupling to vendor/library without abstraction at boundary
- [ ] Breaking API/contract changes versioned or backward-compatible

## Performance & scalability

- [ ] No N+1 queries — batch or join
- [ ] No unbounded queries — pagination or limits present
- [ ] No synchronous blocking in async contexts
- [ ] Large collections: stream or paginate, not load-all-in-memory
- [ ] Expensive ops not inside loops without justification
- [ ] Cache invalidation correct when caching added
- [ ] DB indexes exist for new query patterns
- [ ] No unnecessary network calls (batch, deduplicate)

## Code quality & maintainability

- [ ] Naming clear — variables/functions describe intent
- [ ] No dead code (unreachable branches, unused imports, commented-out blocks)
- [ ] Error handling: specific catch, meaningful messages, proper propagation
- [ ] No swallowed exceptions (empty catch blocks)
- [ ] Complex logic has tests, not just comments
- [ ] Magic numbers/strings extracted to named constants
- [ ] No copy-paste duplication >10 lines — extract shared logic
- [ ] Consistent patterns with existing codebase

## Business & financial impact

- [ ] Money/quantity calculations use appropriate precision (no float for currency)
- [ ] Financial transactions idempotent or guarded against double-processing
- [ ] User-facing data changes auditable (who changed what, when)
- [ ] Rate limiting on endpoints that cost money (API calls, SMS, email)
- [ ] Graceful degradation — failures don't cascade to unrelated features
- [ ] Data validation at system boundaries — reject garbage early
- [ ] Regulatory: PII handling, data retention, consent flows where applicable

## Test coverage

- [ ] New public functions/methods have tests
- [ ] New branches (if/else, switch, try/catch) have coverage
- [ ] Edge cases covered: null, empty, boundary values, error paths
- [ ] Tests deterministic — no time-dependent, order-dependent, or flaky patterns
- [ ] Test names describe scenario, not implementation
- [ ] Integration points mocked at correct boundary (not too deep, not too shallow)
