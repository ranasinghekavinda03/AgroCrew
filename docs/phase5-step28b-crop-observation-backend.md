# Phase 5, Step 28B: Crop Observation Backend

Implementation date: 2026-11-27  
Repository HEAD during implementation: `94128481b36be0373cb127fd2c3ecfc42be5f34f`  
Scope: backend foundation only; Flutter Observation work is deferred.

## Implemented contract

AgroCrew now has a manual `CropObservation` backend resource nested under an existing CropCycle. The implementation accepts the six approved categories: `general`, `growth`, `irrigation`, `pest_or_disease_symptom`, `soil`, and `other`. Notes are required, trimmed, nonblank, and limited to 10,000 Unicode code points by the API schema. Observation dates accept exact `YYYY-MM-DD` calendar values, including future dates, and reject datetime coercion.

The implementation adds no diagnosis, confidence, recommendation, image, sensor, weather, device, AI, or generic metadata fields.

## Persistence and migration

`backend/app/db/models/crop_observation.py` defines `crop_observations` with:

- Generated integer `id`.
- Required `crop_cycle_id` foreign key to `crop_cycles.id` with `ON DELETE RESTRICT`.
- Required SQL `DATE` observation date.
- Required `VARCHAR(32)` category with a six-value database check.
- Required `TEXT` notes with a trimmed-nonblank database check.
- Server-generated timezone-aware created and updated timestamps; ORM updates advance `updated_at`.
- Composite timeline index on `crop_cycle_id`, `observation_date`, `created_at`, and `id`.

The composite index uses ascending column definitions. PostgreSQL can scan it backward for the query's all-descending order, and the plain-column definition is portable to the SQLite metadata tests.

CropCycle exposes an `observations` relationship using `passive_deletes="all"` and no delete/delete-orphan cascade. The database foreign key remains the deletion authority. Deleting an observed CropCycle therefore reaches the existing `IntegrityError` handling and returns HTTP 409; a childless CropCycle still returns 204.

Alembic revision `7c4f1e8a9b2d` follows `2a688eee651b`. Its upgrade creates only the observation table and index. Its downgrade drops only those Step 28B objects. Offline PostgreSQL SQL generation passed, but the revision was not applied to any user database.

## Schemas

`CropObservationCreate` accepts only:

```json
{
  "observation_date": "2026-11-27",
  "category": "irrigation",
  "notes": "Topsoil was dry before irrigation."
}
```

Unknown fields are forbidden. The path supplies the immutable parent ID; clients cannot provide observation, CropCycle, Farm, User, or timestamp ownership fields.

`CropObservationResponse` returns `id`, `crop_cycle_id`, `observation_date`, `category`, `notes`, `created_at`, and `updated_at`.

## Ownership and service behavior

Every operation derives authorization through:

```text
authenticated User -> Farm.user_id -> CropCycle.farm_id -> CropObservation.crop_cycle_id
```

Create locks the owner-scoped CropCycle row, inserts once, commits, and refreshes. Reads use owner-scoped joins and never trust client ownership. Database failures roll back and become a detail-free service exception. Missing and foreign parents are indistinguishable. Detail reads require both the nested CropCycle ID and Observation ID to match.

## API routes

All routes use the existing Bearer dependency:

| Route | Success | Behavior |
|---|---:|---|
| `POST /api/v1/crops/{crop_cycle_id}/observations` | 201 | Creates one manual observation. |
| `GET /api/v1/crops/{crop_cycle_id}/observations` | 200 | Returns a bare JSON array. |
| `GET /api/v1/crops/{crop_cycle_id}/observations/{observation_id}` | 200 | Returns one nested, owner-scoped observation. |

Collection query parameters are `limit` 1-100, default 100, and zero-based `offset`, default 0. Ordering is `observation_date DESC`, `created_at DESC`, then `id DESC`.

Errors follow existing conventions: 401 authentication, owner-scoped 404, sanitized 422 validation, and generic 500 service failure. There is no Observation PUT or DELETE endpoint.

## Automated verification

Commands were run from `backend/` with the existing virtual environment:

```powershell
.\.venv\Scripts\python.exe -m pytest -q -rs `
  tests\test_crop_observation_schema.py `
  tests\test_crop_observation_model.py `
  tests\test_crop_observation_service.py `
  tests\test_crop_observation_api.py `
  tests\test_crop_observation_postgres_integration.py
```

Result: exit 0; 75 passed, 1 skipped, 1 existing Starlette TestClient deprecation warning.

```powershell
.\.venv\Scripts\python.exe -m pytest -q -rs
```

Result: exit 0; 274 passed, 5 skipped, 1 existing Starlette TestClient deprecation warning. The historical baseline was 199 passed and 4 skipped; Step 28B adds 75 passing tests and one opt-in PostgreSQL module.

```powershell
.\.venv\Scripts\python.exe -m alembic history
.\.venv\Scripts\python.exe -m alembic upgrade head --sql
.\.venv\Scripts\python.exe -m alembic downgrade 7c4f1e8a9b2d:2a688eee651b --sql
.\.venv\Scripts\python.exe -m compileall -q app tests
```

All exited 0. Alembic reports `7c4f1e8a9b2d` as head and generated PostgreSQL upgrade and downgrade DDL without connecting or applying it. The downgrade SQL drops only the timeline index and `crop_observations` table before restoring the prior revision marker.

## PostgreSQL status

`backend/tests/test_crop_observation_postgres_integration.py` is opt-in through `RUN_POSTGRES_INTEGRATION=1` and checks the real constraint/index/FK behavior and rejected parent deletion. It was skipped because no disposable isolated PostgreSQL database was verified. Runtime migration upgrade/downgrade/re-upgrade and create-versus-delete concurrency therefore remain pending; neither the user's development database nor Docker volumes were touched.

## Known limitations and deferred work

- Offset pagination is not snapshot-consistent during concurrent inserts.
- There is no Observation edit/delete, optimistic version, attachment, filter, archive, or retention-erasure workflow.
- CropCycle lifecycle transitions remain unrestricted and unchanged.
- Actual PostgreSQL migration runtime and lock-concurrency verification remain pending on disposable infrastructure.
- Flutter models, services, navigation, screens, and integration tests are deferred to a later approved step.
- No manual Web, Android, or live-backend testing was requested or run.
