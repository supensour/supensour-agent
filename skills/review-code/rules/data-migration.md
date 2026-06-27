# Data migration review rules

Extends `generic.md` and `springboot.md` for projects where migrations live in `src/main/java/migrations/Migration_*.java`.

## Trigger function dependencies

- [ ] Migration creates trigger via `EXECUTE FUNCTION <fn>(...)`: verify function created by **prior** migration (lower version) before flagging missing dependency.

  **How to check:**
  1. Extract function name from trigger DDL (e.g., `process_history` from `EXECUTE FUNCTION process_history(...)`).
  2. Search `src/main/resources/sql/` for `.sql` file containing `CREATE OR REPLACE FUNCTION <fn>` or `CREATE FUNCTION <fn>`.
  3. Search `src/main/java/migrations/` for migration loading that SQL file (e.g., via `@Value("classpath:sql/<file>.sql")` + `queryHelper.executeQuery(...)`).
  4. Compare migration version (`Long` from `version()`) against current. Lower → function guaranteed at runtime → **no finding**.
  5. No creating migration found → flag 🟠 high: missing prerequisite function, migration fails at trigger creation.

## Table creation

- [ ] Business key columns in unique indexes must be `NOT NULL` — PostgreSQL treats two NULLs as distinct, silently bypassing uniqueness. Check every `.column(...)` feeding `createUniqueIndex` or `constraint(...).primaryKey/unique(...)`.
- [ ] `createTable` in `migrate()` needs matching `dropTableIfExists` (not `dropTable`) in `rollback()` for safe partial-failure recovery.
- [ ] Prefer `dropTableIfExists` over `dropTable` in rollback — `migrate()` failed before table creation → bare `dropTable` throws and masks original error.

## Code quality

- [ ] Logger must be `private static final Logger LOG` — `final` required. Enforce codebase convention.
- [ ] Remove all commented-out `@Autowired` boilerplate from auto-generated template before merge — any `// @Autowired` block not actively used is dead code.
