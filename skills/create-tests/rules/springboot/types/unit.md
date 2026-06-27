# Spring Boot — unit test conventions

Extends `rules/springboot/index.md`. Applies to `--type unit` (the default). Unit tests run **without**
the Spring context — plain JUnit + Mockito. (Slice/integration tests like `@WebMvcTest`, `@DataJpaTest`,
`@SpringBootTest` belong to `types/integration.md`, added later.)

## Watermark placement

Watermark text from `bash scripts/watermark.sh`; `@author` value from `bash scripts/watermark.sh --author`
(both configurable in `<repo-root>/supensour-config.yaml`). Defaults shown below.

- **New test class** → class-level Javadoc with the watermark + `@author`, directly above the class:
  ```java
  /**
   * Generated with skill supensour:create-tests · suprayan@supensour · github.com/supensour/supensour-agent
   *
   * @author supensour-agent@create-tests
   */
  @ExtendWith(MockitoExtension.class)
  class OrderServiceTest { ... }
  ```
- **New `@Test` method added to an EXISTING class not created by this skill** → a one-line comment with
  the watermark directly above the new method; leave the rest of the class untouched:
  ```java
  // Generated with skill supensour:create-tests · suprayan@supensour
  @Test
  @DisplayName("rejects negative amount")
  void rejectsNegative() { ... }
  ```
  (A class is "skill-created" if it already contains `supensour:create-tests`. If so, just add the
  method with no per-method comment.)

## Structure

New test class — Javadoc watermark above the class, package/imports as usual:

```java
package com.example.order;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Generated with skill supensour:create-tests · suprayan@supensour · github.com/supensour/supensour-agent
 *
 * @author supensour-agent@create-tests
 */
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

  @Mock OrderRepository repository;
  @InjectMocks OrderService service;

  @BeforeEach
  void setUp() { /* shared arrange */ }

  @Test
  @DisplayName("returns total for a valid order")
  void computesTotal() {
    when(repository.findById(1L)).thenReturn(Optional.of(anOrder()));
    var total = service.total(1L);
    assertEquals(new BigDecimal("42.00"), total);
    verify(repository).findById(1L);
  }

  @Test
  @DisplayName("throws NotFound when order is missing")
  void missingOrder() {
    when(repository.findById(99L)).thenReturn(Optional.empty());
    assertThrows(OrderNotFoundException.class, () -> service.total(99L));
  }
}
```

## Conventions

- `@ExtendWith(MockitoExtension.class)` + `@Mock`/`@InjectMocks` for the unit-under-test's collaborators.
- `@DisplayName` describes the scenario in plain language.
- Static-import `Assertions.*` and `Mockito.*`.
- One behavior per `@Test`. Use `@BeforeEach` only for genuinely shared arrange.
- **Parameterized**: `@ParameterizedTest` (+ `@ValueSource`/`@CsvSource`/`@MethodSource`) for boundary
  and table-driven inputs instead of copy-pasted tests.
- **Error paths**: `assertThrows(Type.class, () -> ...)` and assert the message/cause where it matters.
- **Money/precision**: assert `BigDecimal` with explicit scale; never compare floats.
- `verify(...)` interactions only when the interaction *is* the contract; don't over-verify.

## Mocking

- Mock at the collaborator boundary (repositories, clients, gateways). Don't mock value objects or the
  class under test.
- `when(...).thenReturn(...)` / `.thenThrow(...)`; `ArgumentCaptor` to assert arguments passed downstream.
- Avoid `@SpringBootTest` for units — it boots the context and is slow; that's an integration concern.
