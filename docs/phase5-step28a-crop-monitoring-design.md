# Phase 5, Step 28A: Crop Monitoring Foundation Design

Status: design proposal only; no endpoint, model, migration, service, or Flutter observation code exists yet.  
Source audit date: 2026-11-27  
Audited repository HEAD: `94128481b36be0373cb127fd2c3ecfc42be5f34f`

## 1. Purpose and boundary

This document proposes the first provider-neutral Crop Monitoring foundation for AgroCrew: authenticated farmers can record dated, human-written observations against an existing CropCycle they own. It deliberately excludes weather, sensors, images, automated findings, diagnoses, recommendations, AI summaries, confidence scores, and generic metadata.

The recommended first implementation is a thin full-stack vertical slice delivered backend-first: implement and verify the database/API contract first, then add a small Flutter timeline and creation form against that stable contract. This step implements neither part.

## 2. Existing architecture findings

The proposal is grounded in these current files and behaviors:

| Area | Current source | Observed convention |
|---|---|---|
| Farm persistence | `backend/app/db/models/farm.py` | `farms.user_id` owns Farms; timestamp columns use timezone-aware `DateTime`, `server_default=func.now()`, and `onupdate=func.now()`. Farm deletion is restricted by CropCycle children. |
| CropCycle persistence | `backend/app/db/models/crop_cycle.py` | `crop_cycles.farm_id` is `RESTRICT`; status is a validated string; dates use SQL `Date`; no lifecycle or version field exists. |
| Schemas | `backend/app/schemas/farm.py`, `backend/app/schemas/crop_cycle.py` | Pydantic v2, `extra="forbid"`, strict positive integer inputs where relevant, explicit trimming, 10,000-character notes, and exact ISO calendar-date validation. |
| Services | `backend/app/services/farm_service.py`, `backend/app/services/crop_cycle_service.py` | SQLAlchemy service functions own transaction boundaries, commit/refresh on success, roll back and sanitize database errors, and use owner-scoped queries. PostgreSQL writes lock relevant parent/resource rows. |
| HTTP routes | `backend/app/api/v1/endpoints/farms.py`, `backend/app/api/v1/endpoints/crops.py` | `/api/v1`, Bearer authentication, positive path IDs, JSON response models, 201 create, 200 reads/replace, 204 delete, owner-scoped 404, validation 422, generic 500, and delete conflict 409. |
| Authentication | `backend/app/api/dependencies.py` | `get_current_user` uses the existing HTTP Bearer access token and loads an active User. |
| Validation errors | `backend/app/main.py` | FastAPI validation errors return sanitized `{"detail": [...]}` bodies with the rejected input removed. |
| Pagination/sort | Farm and CropCycle endpoints/services | Bare JSON arrays; `limit` 1–100 (default 100), zero-based `offset` (default 0), deterministic creation-time then ID ordering. |
| Alembic | `backend/alembic/versions/8023513d143e_create_farms_table.py`, `backend/alembic/versions/2a688eee651b_create_crop_cycles_table.py` | Named constraints through project naming conventions, explicit foreign-key `ondelete`, and explicit indexes. |
| Backend tests | `backend/tests/conftest.py`, CropCycle model/API/PostgreSQL tests | Ordinary tests use isolated in-memory SQLite with foreign keys enabled; PostgreSQL checks are opt-in and must target a disposable database. Tests cover ownership equivalence, rollback, schema metadata, and OpenAPI. |
| Flutter data flow | `mobile/lib/core/network/api_client.dart`, `mobile/lib/features/auth/data/auth_session.dart`, `mobile/lib/features/crops/data/` | Feature services sit above `ApiClient` and `AuthSession`; reads can refresh/retry once, mutations are sent once, response models parse defensively, and session generations reject stale work. |
| Flutter UI | `mobile/lib/features/crops/presentation/`, `mobile/integration_test/crop_cycle_flow_test.dart` | Profile → My Crop Cycles → details navigation; page size 20; responsive scroll layouts; refresh/retry/empty states; authoritative inspection after ambiguous mutations; synthetic mock-backed integration fixtures. |

Current CropCycle behavior is unrestricted enum membership, permanent deletion, visibility regardless of status, and last-writer-wins update. This design does not claim or introduce lifecycle transition rules.

## 3. Outstanding CropCycle product decisions

All recommendations in this table are proposals, not current behavior.

| Issue | Existing behavior | Options and trade-offs | Recommended proposal | Compatibility/migration impact | Blocks observation MVP? |
|---|---|---|---|---|---|
| Status transitions | Any of `planned`, `active`, `harvested`, `cancelled` can replace any other value. | Unrestricted is simple but permits inconsistent history; a transition graph improves consistency but needs reopening/correction rules; role/workflow rules are more complex. | Keep transitions unrestricted for the first observation slice; design a separate lifecycle policy before tightening them. | A later policy changes validation and may require handling existing sequences, but no data rewrite is necessarily required. | No. |
| Editing harvested/cancelled cycles | Fully editable. | Keep editable supports corrections but weakens historical stability; read-only protects history but needs reopen/correction workflows; limited fields split the difference but complicate UI/API. | Keep current behavior for MVP; later prefer explicit reopen/correction rather than silent edits. | Later enforcement affects PUT and Flutter affordances; existing records remain readable. | No. |
| Completed-cycle visibility/archive | Harvested/cancelled remain in the same list; no archive flag. | Always visible is simple but lists grow; status-filtered/archive views improve usability; separate archive storage complicates queries and links. | Retain records in the same table and add filters/archive presentation later, not physical relocation. | Additive query/UI change; likely no destructive migration. | No. |
| CropCycle deletion | Permanent hard delete is allowed when no dependent FK blocks it. | Hard delete is simple but loses history; soft delete preserves data but affects every query/unique rule; restrict preserves child history but prevents requested deletion; cascade is convenient but destructive. | Once observations exist, use FK `RESTRICT` and return the already-documented 409 for a cycle with observations. Consider soft deletion only as a later cross-product policy. | The observation migration's FK determines behavior. Existing childless cycles remain deletable. Product approval is required before migration. | Yes, the FK deletion action must be approved for implementation; it does not block this design. |
| Child records and deletion | No observation child exists; CropCycle delete already maps dependency integrity failures to 409. | Restrict, cascade, or soft-delete/archive. Cascade risks accidental loss; restrict matches Farm→CropCycle history protection; archive provides retention but is wider work. | `RESTRICT` CropCycle deletion while observations exist. | New FK makes some formerly successful deletes return 409; Flutter already has a conflict category to extend with clearer copy. | Same as above. |
| Concurrent edits | Row locks serialize writers, then last writer wins; no client version token. | Keep last-writer-wins; add `updated_at` precondition; add integer version/ETag. Optimistic concurrency prevents lost updates but adds 409/412 and recovery UX. | Keep last-writer-wins for create-only observation MVP; require optimistic concurrency design before observation editing is added. | No initial migration; later version column or reliable timestamp/ETag contract is additive. | No for create/list/detail; relevant before PUT. |
| Historical observations after completion | Not applicable because observations do not exist. | Retain, hide, archive, or delete. Retention supports traceability/analytics; deletion reduces storage/privacy exposure; hiding is presentation-only. | Retain and keep readable after harvest/cancellation; lifecycle completion must not erase observation history. | Compatible with `RESTRICT`; future retention/erasure tools must traverse the hierarchy deliberately. | No, provided retention proposal is accepted. |

## 4. Recommended Observation MVP

An observation is a farmer-authored factual note about what they saw or did on a calendar date. Category names describe the subject of the note, not a confirmed diagnosis. No additional field is essential in the first record: ownership comes from the parent, provenance is deterministically manual because this table/API accepts only manual observations, and timestamps provide basic audit context. If automated inputs arrive later, use a separate finding/ingestion model or add an explicit provenance migration; never silently mix them into this contract.

### 4.1 Field contract

| Field | Type | Required | Validation/default | Database | API serialization | Ownership | Justification |
|---|---|---:|---|---|---|---|---|
| `id` | positive integer | Response only | Server generated | `Integer`, primary key | JSON integer | Not client assignable | Stable identifier for links, deduplication, and later audit references. |
| `crop_cycle_id` | positive integer | Path and response | Path `gt=0`; immutable after creation | Non-null `Integer` FK to `crop_cycles.id` | JSON integer | Parent must resolve through an owned Farm; absent from body | Establishes the only ownership path and prevents reassignment. |
| `observation_date` | calendar date | Yes | Exact `YYYY-MM-DD`; no datetime coercion; no default | Non-null SQL `Date` | JSON string `YYYY-MM-DD` | Inherits parent ownership | Captures when the field observation occurred, independently of upload time. Future-date policy is intentionally not imposed yet. |
| `category` | controlled string | Yes | One of values below; no default | Non-null `String(32)` plus check constraint | Lowercase wire string | Inherits parent ownership | Gives consistent filtering/analytics without claiming a diagnosis. |
| `notes` | string | Yes | Trim outer whitespace; 1–10,000 Unicode characters after trimming | Non-null `Text` plus nonblank check | JSON string | Farmer-authored content | A record without notes is not useful; same maximum as existing note fields. |
| `created_at` | timestamp | Response only | Database generated | Non-null timezone-aware `DateTime`, server `now()` | ISO 8601 datetime including offset/`Z` as emitted by FastAPI | Server-controlled | Records ingestion/audit time. |
| `updated_at` | timestamp | Response only | Generated; same as creation until future edits | Non-null timezone-aware `DateTime`, server `now()`, `onupdate` | ISO 8601 datetime including offset/`Z` | Server-controlled | Keeps the response future-compatible with later editing. |

Required MVP category wire values:

- `general`
- `growth`
- `irrigation`
- `pest_or_disease_symptom`
- `soil`
- `other`

`pest_or_disease_symptom` means the farmer observed a possible symptom. It does not confirm a pest, disease, cause, treatment, or severity.

Future extensions, each requiring its own reviewed contract, include attachments/images, location/plot, structured measurements and units, explicit provenance, creator/audit identity, device/source identifiers, weather snapshots, and machine-generated findings. Generic JSON metadata, confidence, diagnosis, sensor columns, and recommendation fields are rejected from this MVP.

## 5. Ownership and authorization

The sole authority chain is:

```text
get_current_user → Farm.user_id → CropCycle.farm_id → CropObservation.crop_cycle_id
```

- Every endpoint uses the existing `get_current_user` Bearer dependency.
- The service resolves the parent using the same owner-scoped CropCycle/Farm join used today. POST locks the owned CropCycle row on PostgreSQL before inserting, serializing creation against CropCycle deletion.
- Observation reads join Observation → CropCycle → Farm and filter `Farm.user_id == current_user.id`.
- A missing CropCycle and another user's CropCycle both return `404 {"detail":"Crop not found."}`. A missing/foreign observation under an owned or foreign parent returns the same observation-scoped `404 {"detail":"Observation not found."}` without revealing existence.
- Clients cannot send `user_id`, `farm_id`, or `crop_cycle_id` in the JSON body; unknown fields are rejected with 422. The crop ID comes only from the path.
- A future update schema must omit `crop_cycle_id`, so ordinary update cannot reparent an observation.
- Do not add `user_id` or `farm_id` columns: they duplicate mutable hierarchy facts, introduce mismatch risk, and are unnecessary for authorization. Add denormalized ownership only if measured query/security requirements later justify constraints that guarantee consistency.

## 6. Proposed API contract

These routes are proposed and are not currently implemented.

### 6.1 Initial endpoint set

| Method and path | Success | Purpose |
|---|---:|---|
| `POST /api/v1/crops/{crop_cycle_id}/observations` | 201 | Create one manual observation under an owned CropCycle. |
| `GET /api/v1/crops/{crop_cycle_id}/observations?limit=100&offset=0` | 200 | Return a paginated bare JSON array timeline for the owned CropCycle. |
| `GET /api/v1/crops/{crop_cycle_id}/observations/{observation_id}` | 200 | Authoritative read for refresh, deep-linking, and mutation-outcome inspection readiness. |

Create/list alone could render a basic screen, but detail GET is retained because it is small, makes owner-scoped observation lookup explicit, and supports the project's authoritative-inspection safety pattern. PUT and DELETE are deferred: creation plus history is the smallest safe write surface while lifecycle, retention, and concurrency decisions remain open.

### 6.2 JSON examples

POST body:

```json
{
  "observation_date": "2026-11-27",
  "category": "irrigation",
  "notes": "Topsoil was dry before the evening irrigation."
}
```

201 response (GET detail uses the same shape):

```json
{
  "id": 41,
  "crop_cycle_id": 12,
  "observation_date": "2026-11-27",
  "category": "irrigation",
  "notes": "Topsoil was dry before the evening irrigation.",
  "created_at": "2026-11-27T14:20:10.123456Z",
  "updated_at": "2026-11-27T14:20:10.123456Z"
}
```

List response is a JSON array of these objects. `limit` is an integer from 1 through 100, default 100; `offset` is an integer at least 0, default 0. Results are newest observation first by `observation_date DESC`, then `created_at DESC`, then `id DESC`. The ID tie-break makes ordering deterministic. Offset pagination matches the project even though it can shift during concurrent inserts; the Flutter list should request 20 and deduplicate IDs defensively.

### 6.3 Errors and validation

- All routes require `Authorization: Bearer <access-token>`; missing/invalid credentials return the existing 401 with `WWW-Authenticate: Bearer`.
- Non-positive path IDs, bad query bounds, wrong/missing fields, blank/oversized notes, invalid category/date, datetime supplied as a date, and unknown body fields return sanitized FastAPI 422 responses: `{"detail":[...]}`.
- Parent CropCycle failures use owner-scoped 404. Observation detail failures use owner-scoped 404. Foreign and nonexistent resources must be indistinguishable.
- Service/database failures roll back and return a generic 500 such as `{"detail":"Unable to process the observation operation at this time."}`; raw database messages are never exposed.
- No normal 409 is expected from create/list/detail. A parent-delete race is prevented by the parent row lock and FK. Future PUT may use 409/412 for optimistic concurrency; future DELETE may use 409 for dependent records/retention rules.
- `notes` maximum is 10,000 characters; `category` storage maximum is 32. `observation_date` is date-only; timestamps are ISO 8601 instants, never date-only values.

## 7. Proposed database and migration design

Proposed table: `crop_observations`.

```text
id                 INTEGER      PRIMARY KEY
crop_cycle_id      INTEGER      NOT NULL FK crop_cycles(id) ON DELETE RESTRICT
observation_date   DATE         NOT NULL
category           VARCHAR(32)  NOT NULL
notes              TEXT         NOT NULL
created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
```

Constraints should require trimmed nonblank notes and category membership. Create an index matching the main query, preferably `(crop_cycle_id, observation_date DESC, created_at DESC, id DESC)` on PostgreSQL. If cross-database migration portability makes explicit descending metadata awkward, the same ascending composite columns can still support reverse traversal; verify the actual PostgreSQL plan later. A simple FK index alone is insufficiently aligned with the timeline sort.

The create transaction locks the owner-scoped CropCycle, inserts, commits, refreshes, and rolls back on any SQLAlchemy error. The FK is the final integrity guard. Relationships should use `passive_deletes="all"` so ORM behavior does not bypass the database policy.

Deletion alternatives:

| Policy | Benefit | Cost/risk | Assessment |
|---|---|---|---|
| `RESTRICT` | Preserves observation history; matches Farm→CropCycle policy and existing CropCycle 409 branch. | Users cannot hard-delete a cycle until a later retention/deletion workflow exists. | Recommended proposal; requires approval before migration. |
| `CASCADE` | Simple cleanup and no orphan rows. | One CropCycle delete silently destroys all monitoring history and future AI evidence. | Rejected for MVP. |
| Soft-delete/archive | Retains history while hiding active views; can support restoration. | Requires schema and filters across CropCycle APIs/UI, privacy erasure semantics, and uniqueness/audit decisions. | Valuable future cross-cutting design, too broad for initial observations. |

The migration must be additive and downgrade by dropping only the new table/index/constraints. A future category expansion requires an application Literal and database-check migration; future provenance/version/attachment tables can reference stable observation IDs. No migration is created in Step 28A.

## 8. Category strategy

| Approach | Validation/forms | Localization/analytics/ML | Migration/reporting | Decision |
|---|---|---|---|---|
| Controlled string enum | Strong API/dropdown validation; simple Flutter mapping. | Wire keys remain language-neutral; labels localize client-side; consistent aggregates and training labels. | Adding a key requires coordinated code/check-constraint migration. | Recommended with the six broad keys above. |
| Arbitrary string | Flexible and easy to add. | Spelling/language synonyms fragment analytics and training data; harder UI/filtering. | No enum migration, but costly cleanup and inconsistent reports. | Rejected. |
| Reference table | Runtime extensibility and localized metadata. | Strong reporting if governed. | Adds joins, admin/versioning/seed lifecycle for only six values. | Deferred until categories truly need administration. |
| General only | Minimal form and no classification mistakes. | Little filtering/analytics value; later backfill is unreliable. | Easiest schema, weakest data. | Rejected because a small broad set adds useful structure without diagnosis. |

Store stable lowercase keys, not translated labels. Category is the topic of a manual observation; it must never encode confidence, recommendations, or confirmation of disease.

## 9. Flutter integration design

Navigation should extend the existing flow:

```text
Authenticated Profile → My Crop Cycles → Crop Cycle Details → Observations
```

Crop Cycle Details gets an Observations action. The Observation timeline uses a responsive, constrained scroll layout and page size 20, newest observation date first. Each card shows date, localized category label, a safe note preview, and created timestamp when useful. It provides pull/action refresh, Load more, a clear empty state (“No observations recorded yet”), first-page error with retry, and load-more error without discarding existing items.

Add Observation contains a date picker/text fallback constrained to exact calendar date, category dropdown, multiline notes with required/10,000-character validation, and one submit action. A separate details screen is optional visually, but a lightweight details route is recommended when notes are long; it performs the authoritative detail GET. Editing and deletion controls remain absent in the first slice.

Implementation should add an observation model/service under the existing crop feature (or a narrowly named observations subfeature), reuse `ApiClient`, `AuthSession`, `AuthService`, and current error types/patterns, and introduce no new global state framework. Defensive JSON parsing must require all response fields, validate positive IDs/date/category/timestamps, and confirm returned parent/id values.

Reads may follow the existing single refresh-and-retry behavior. POST must be sent once and never automatically replayed. A timeout, network failure, unexpected status, or invalid successful response after sending is an ambiguous creation: disable blind resubmission and direct the user back to refresh the authoritative timeline before trying again. Capture the session generation at route/request start, ignore stale responses, and invalidate protected routes after logout/account replacement. Preserve current list content during transient refresh errors. Android/Web layouts must remain scrollable with large text and narrow widths.

Recommended sequence: backend model/schema/service/router/migration and isolated tests; then Flutter model/service tests; then timeline/form widgets; finally mock-backed integration. This is backend-first inside one thin full-stack feature, not a backend-only product release.

## 10. Data quality and future AI readiness

- Preserve `observation_date` separately from server timestamps; never infer it from upload time.
- Treat every MVP row as manual farmer-authored input. Keep the original notes distinct from any later normalized value, summary, diagnosis, or recommendation.
- Use stable IDs, controlled category keys, strict dates, nonblank bounded notes, timestamps, FK integrity, deterministic ordering, and rollback-safe transactions.
- Do not invent values for missing future measurements. Add nullable, unit-aware structured fields only with a real use case; absence must remain absence.
- Retain observations after CropCycle completion under the proposed policy. Define retention, export, correction history, account deletion, and legal/privacy needs before production claims.
- Images, precise location, device data, or external enrichment require explicit consent, purpose, access, retention/deletion, and provenance designs before collection.
- If editing is later allowed, add optimistic concurrency and an audit/history approach so training/evidence pipelines can distinguish original from corrected data.
- Later automated findings must record source/version/time and remain clearly labeled as inferred. Never overwrite farmer notes or present probabilistic output as confirmed agronomic fact.
- Recommendations must cite their evidence and limitations and allow human review; no confidence field should exist until a defined evaluated model produces it.

## 11. Test strategy for the next implementation

All mutation tests use synthetic users/Farms/CropCycles in isolated databases, never development records.

### Backend sequence

1. Schema unit tests: exact date-only parsing (including rejecting datetime strings/impossible dates), all category keys and unknown keys, trimmed nonblank notes, 10,000 boundary, unknown field rejection, and positive strict IDs/query bounds.
2. Model tests: columns/nullability/defaults/checks/FK/index metadata, persistence of Unicode, timestamps, parent relationship, invalid category/blank notes/FK rejection, and rollback recovery.
3. Service tests: owned parent create, parent missing/foreign equivalence, owner-scoped list/detail, transaction commit/refresh, injected insert/commit failure rollback, and no leaked SQL details.
4. API tests: 201/200 shapes, Bearer requirement, missing/foreign parent 404, missing/foreign observation 404 equality, cross-user list isolation, body ownership-field rejection, validation 422 sanitization, default/boundary pagination, empty/out-of-range pages, and OpenAPI security/responses.
5. Ordering tests: mixed dates plus identical dates/timestamps prove `observation_date DESC, created_at DESC, id DESC`; page boundaries are deterministic in a stable dataset.
6. Regression: complete existing Farm/CropCycle/auth backend suite, including confirmation that childless CropCycle deletion still works and observed-cycle deletion returns 409 once `RESTRICT` is implemented.
7. Opt-in isolated PostgreSQL: real FK/check/index semantics, row-lock create-vs-delete behavior, timestamp behavior, owner isolation, rollback, and deletion restriction. Skip unless the database is explicitly verified disposable.
8. Alembic: clean upgrade to head, schema inspection, downgrade one revision, re-upgrade, and preservation of existing tables/data using only disposable databases.

### Flutter sequence

1. Model tests for strict complete JSON, Unicode, IDs, date-only values, timestamps, category mapping, length boundaries, and serialization.
2. Service tests for URLs/query parameters/Bearer headers, pagination, parent/id matching, 401 refresh-and-read retry, one-shot POST, ambiguous-create classification, sanitized error mapping, and session-generation rejection.
3. Widget tests for empty/loading/error/retry/list/load-more, responsive widths/text scale, form validation/date/category/notes, accessibility keys/labels, refresh retention, logout invalidation, and ambiguous mutation inspection flow.
4. Mock-backed integration from CropCycle Details through timeline/create/refresh, asserting one POST and ID deduplication. Later user-scheduled Web/Android and isolated real-backend acceptance remains separate.

## 12. Recommended scope, rejected alternatives, risks, and approvals

### Recommended next implementation scope (Step 28B only after approval)

- `CropObservation` SQLAlchemy model and relationships.
- Pydantic create/response schemas; no update schema yet.
- Observation service create/list/get with owner-scoped joins and transaction handling.
- Nested router with POST/list/detail GET.
- One additive Alembic revision using the approved FK deletion policy and composite timeline index.
- Backend schema/model/service/API tests and opt-in PostgreSQL tests.
- After backend stability, Flutter model/service/timeline/add form/details and focused tests as the same thin feature slice.

Likely future paths (names are proposals, not implemented):

```text
backend/app/db/models/crop_observation.py
backend/app/schemas/crop_observation.py
backend/app/services/crop_observation_service.py
backend/app/api/v1/endpoints/crop_observations.py
backend/alembic/versions/<revision>_create_crop_observations_table.py
backend/tests/test_crop_observation_model.py
backend/tests/test_crop_observation_service.py
backend/tests/test_crop_observation_api.py
backend/tests/test_crop_observation_postgres_integration.py
mobile/lib/features/crops/data/models/crop_observation.dart
mobile/lib/features/crops/data/crop_observation_service.dart
mobile/lib/features/crops/presentation/crop_observations_screen.dart
mobile/lib/features/crops/presentation/add_crop_observation_screen.dart
```

Rejected for the MVP: generic JSON metadata (weak contract), duplicated owner/Farm columns (consistency risk), arbitrary categories (poor data quality), a category reference table (premature administration), cascade deletion (history loss), observation PUT/DELETE (unresolved retention/concurrency), images/sensors/weather/AI fields (separate consent/provenance requirements), diagnoses/confidence/recommendations (unsupported certainty), and a new Flutter state framework (unnecessary architectural expansion).

Key risks and mitigations:

| Risk | Mitigation |
|---|---|
| Cross-user disclosure | Owner-scoped joins at every read/write; make missing and foreign 404 responses identical; two-user tests. |
| History loss | Approve `RESTRICT`; no observation DELETE in first slice; define retention before destructive features. |
| Duplicate creation after timeout | Never replay POST; expose ambiguity and require authoritative list inspection. |
| Category rigidity | Start with broad stable keys and use coordinated additive migrations when evidence supports change. |
| Offset page shifting | Deterministic tie-breaks, client ID deduplication, refresh; consider cursor pagination later. |
| Lost updates | No update endpoint now; design version/ETag behavior before adding it. |
| Notes mistaken for diagnosis | Explicit UI/API language and category semantics; keep inferred findings separate. |

Explicit approvals still required before implementation:

1. Approve the proposed six category keys.
2. Approve required, trimmed notes with a 10,000-character maximum and no future-date restriction for `observation_date`.
3. Approve CropCycle FK `ON DELETE RESTRICT` once observations exist and continued access after harvest/cancellation.
4. Approve the three-endpoint create/list/detail slice while deferring PUT/DELETE.
5. Decide later—not as an MVP blocker—the full CropCycle transition, archive, soft-delete, retention/erasure, and optimistic-concurrency policies.

## 13. Design verdict

**PASS WITH WARNINGS.** The proposed contract is small, secure, deterministic, provider-neutral, aligned with current AgroCrew conventions, and ready to become an implementation plan after the four MVP approvals above. The warning is that the parent deletion action is a user-visible compatibility choice and must be approved before creating the migration. No Step 28B behavior is implemented here.
