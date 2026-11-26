# AgroCrew Project Handover

Last source audit: 2026-11-26, Step 27I
Audited branch/HEAD: `main` at `2a6def109f67d181fda4eb69d327f12ecc7ea462`

This handover distinguishes implementation from verification. “Implemented” means source exists. “Automatically verified” means a relevant automated check passed. “Runtime limited” means implementation and tests exist but an external runtime was unavailable or incomplete. “Not implemented” means no working source was found.

## 1. Product status

AgroCrew currently provides authenticated Farm and CropCycle management through a FastAPI backend and Flutter Android/Web client. The CropCycle phase (Steps 27A–27H) is implemented and has broad automated coverage.

The repository still describes a future multi-agent smart farming assistant, but weather, crop monitoring sensors, agronomic recommendations, disease detection, ML models, AI agents, orchestration, reminders, and production deployment are not implemented. Marketing text in the home screen is aspirational, not evidence of those features.

The application must not be described as production-ready. Real PostgreSQL acceptance was not run in Steps 27H/27I, Android runtime integration did not complete, and no deployment/operations baseline exists.

## 2. Architecture and data flow

```text
Farmer
  -> Flutter screens (Android/Web)
  -> AuthSession + Auth/Farm/CropCycle services
  -> ApiClient JSON requests
  -> FastAPI /api/v1 routes
  -> get_current_user Bearer validation
  -> Auth/Farm/CropCycle service functions
  -> SQLAlchemy models
  -> PostgreSQL
```

- `backend/app/main.py` builds FastAPI, CORS, routing, and sanitized validation responses.
- `backend/app/api/dependencies.py` validates access JWTs and loads an active User.
- `backend/app/api/v1/endpoints/` contains auth, Farm, CropCycle, and health routes.
- `backend/app/services/` contains database operations and rollback/error boundaries.
- `backend/app/db/models/` and `backend/alembic/versions/` define Users, refresh tokens, Farms, and CropCycles.
- `mobile/lib/app.dart` owns application/session routing.
- `mobile/lib/features/auth/` implements authentication and session safety.
- `mobile/lib/features/farms/` and `mobile/lib/features/crops/` implement feature services, models, and screens.
- `mobile/lib/core/network/api_client.dart` provides bounded HTTP operations; feature services decide retry safety.

Ownership is server-side. Farms use `Farm.user_id`. CropCycles have no direct User ID; ownership is resolved by joining `CropCycle.farm_id` to an owned Farm.

## 3. Feature inventory

### Authentication

| Feature | Status | Implementation | Automated evidence | Limitation |
|---|---|---|---|---|
| Registration | Automatically verified | `backend/app/api/v1/endpoints/auth.py`, `mobile/lib/features/auth/presentation/register_screen.dart` | `backend/tests/test_registration.py`, `mobile/test/register_screen_test.dart`, integration registration flow | No production deployment/rate-limit review. |
| Login/profile | Automatically verified | auth endpoint/service and Flutter login/profile screens | backend login/current-user tests; Flutter login tests | Real-backend manual acceptance deferred. |
| Access refresh | Automatically verified | refresh-token service and `AuthSession` single-flight refresh | refresh backend tests; `automatic_token_refresh_test.dart`, service tests | Access JWT remains stateless until expiry. |
| Logout | Automatically verified | backend refresh-token revocation; local cleanup state machine | logout backend/Flutter tests | Remote outcome can be uncertain during network failure. |
| Session restoration | Automatically verified | `AuthSession.restore`, versioned token record | restoration/startup tests | Web intentionally has no persistent session. |
| Secure storage | Automatically verified in unit/widget scope | Android `flutter_secure_storage`; Web `MemoryAuthTokenStore` | `auth_token_store_test.dart` | Physical-device secure-store behavior not freshly accepted. |
| Account replacement safety | Automatically verified | session generation and ordered persistence | session, service, and screen race tests | None demonstrated beyond external runtime limits. |

### Farm management

| Feature | Status | Implementation | Automated evidence | Limitation |
|---|---|---|---|---|
| List/pagination | Automatically verified | Farm API/service and `my_farms_screen.dart` | Farm API/service/screen tests | Offset pagination is not snapshot-consistent. |
| Details | Automatically verified | Farm detail endpoint/service/screen | Farm API and screen tests | Manual device acceptance deferred. |
| Create/edit/delete | Automatically verified | Farm endpoints/services/screens | Farm backend, service, screen, and historical integration tests | Uncertain Farm mutations are sent once, but Farm UI does not have the CropCycle workflow's complete authoritative inspection state machine. |
| Ownership/error handling | Automatically verified | owner-scoped backend queries and sanitized client mapping | two-owner/backend and Flutter error tests | Farm deletion returns 409 while CropCycles exist. |

### CropCycle management

| Feature | Status | Implementation | Automated evidence | Limitation |
|---|---|---|---|---|
| List/filter/Farm metadata pagination | Automatically verified | `my_crop_cycles_screen.dart`, Crop/Farm services | `crop_cycle_screens_test.dart`, `crop_cycle_flow_test.dart` | Offset pagination may shift under concurrent writes. |
| Create | Automatically verified | create endpoint/schema/service and add screen | backend API, service, add-screen, native/Web integration tests | Mock Web integration does not prove DB persistence. |
| Details | Automatically verified | detail endpoint/service/screen | API/service/detail-screen/integration tests | Live backend manual GET deferred. |
| Edit/full replacement | Automatically verified | PUT endpoint/schema/service and edit screen | API/service/edit-screen/integration tests | Last-writer-wins; no optimistic concurrency token. |
| Delete | Automatically verified | DELETE endpoint/service and confirmation UI | API/service/detail-screen/integration tests | Future dependent data could produce 409. |
| Validation/date-only/status | Automatically verified | Pydantic schema, DB constraints, Dart model/form validation | backend schema/API/model tests and Flutter model/form tests | Status is enum validation only; no lifecycle policy. |
| Ownership/authentication | Automatically verified | Farm join + Bearer dependency | two-owner backend tests and authenticated service tests | Live PostgreSQL acceptance not rerun. |
| Mutation uncertainty | Automatically verified | non-replay service failures and UI inspection paths | CropCycle service/add/edit/details tests | Network ambiguity cannot be eliminated; inspection is required. |
| Session invalidation/stale responses | Automatically verified | generation checks at session/service/screen layers | deterministic Completer-controlled tests | Android final runtime incomplete. |
| Responsive UI | Automatically verified in widget/Web scope | scrollable constrained layouts | narrow/wide/text-scale tests; genuine Chrome flow | Physical-device matrix not covered. |

## 4. CropCycle API contract matrix

| Operation | Backend contract | Flutter contract | Result |
|---|---|---|---|
| POST `/api/v1/crops` | 201; owned positive `farm_id`; create fields | `CropCycleCreate.toJson`, expects 201 | Match |
| GET `/api/v1/crops` | 200; limit 1–100, offset ≥0, optional owned `farm_id` | requests limit/offset/filter, expects list | Match |
| GET `/api/v1/crops/{id}` | 200; owner-scoped; foreign/missing 404 | authoritative detail GET | Match |
| PUT `/api/v1/crops/{id}` | 200; full replacement; no Farm reassignment | sends required fields and explicit nullable fields; omits `farm_id` | Match |
| DELETE `/api/v1/crops/{id}` | 204 empty body; owner-scoped; conflict 409 possible | accepts 204 and never auto-replays | Match |
| Authentication | Bearer access JWT | access token supplied by current `AuthSession` generation | Match |
| Validation | 422; extra fields forbidden; strict positive IDs/count | local validation plus safe 422 mapping | Match |
| Status | planned/active/harvested/cancelled | matching Dart enum/wire values | Match |
| Dates | exact ISO `YYYY-MM-DD` calendar dates | strict date-only parser/formatter | Match |

No material backend/Flutter mismatch was found in Step 27I.

## 5. Authentication and security audit

Confirmed controls:

- Password hashes are handled by the backend; password hashes are not returned.
- Refresh tokens are stored hashed in PostgreSQL and rotated/revoked transactionally.
- Protected routes require an active User loaded from Bearer access-token claims.
- Client write payloads cannot assign User ownership.
- Missing and foreign-owned resources share 404 behavior.
- Crop creation locks the owned Farm row; update/delete lock the owner-scoped CropCycle row on PostgreSQL.
- Client GET operations may refresh and retry once after 401; POST/PUT/DELETE are never automatically replayed.
- Session generation changes reject stale in-flight responses after logout/account replacement.
- Token persistence ordering prevents an older refresh/login from overwriting a newer account.
- Mutation errors are sanitized; raw response bodies and token values are not displayed.
- Uncertain CropCycle mutations require authoritative inspection before another conflicting mutation.

No demonstrated substantial security defect was found in this audit.

Source-grounded risks, not confirmed exploits:

- Access JWTs are not server-revoked at logout and remain usable until expiry.
- No production rate limiting, security monitoring, or abuse-prevention layer was found.
- Broad Python dependency requirements are not a reproducible locked production set.
- Android release currently uses debug signing.
- Production secret management, TLS termination, backups, audit logging, and incident response are not implemented.
- Last-writer-wins updates can overwrite a concurrent edit.

## 6. Verification evidence

Step 27I commands run on 2026-11-26:

| Category | Command | Result |
|---|---|---|
| Flutter analysis | `flutter analyze` | Exit 0; no issues |
| Native Flutter | `flutter test --reporter compact` | Exit 0; 474 passed, 0 failed, 0 skipped |
| Mock integration | `flutter test -d flutter-tester integration_test/crop_cycle_flow_test.dart --reporter expanded` | Exit 0; 2 passed |
| Genuine Chrome | `flutter run -d chrome --target integration_test/crop_cycle_flow_test.dart` | PASS; both declared scenarios completed |
| Backend API | `.\.venv\Scripts\python.exe -m pytest -q -rs` | Exit 0; 199 passed, 4 skipped, 1 deprecation warning |

The four skipped backend modules are the opt-in Farm/CropCycle PostgreSQL integration tests. They were not enabled because an isolated disposable PostgreSQL database was not confirmed.

Step 27H additionally passed the genuine-Web CropCycle model harness. Android built and installed, but its emulator became offline before final runtime completion. Do not combine these runner counts into a single total.

## 7. Development setup

The root `README.md` contains the current safe commands for Docker/PostgreSQL checks, backend startup, Flutter Web, native tests, mock integration, genuine Chrome runtime, backend API tests, and opt-in isolated PostgreSQL tests.

Important boundaries:

- Never print or commit `backend/.env`.
- Never use the user's development database for disposable mutation tests.
- Never remove the PostgreSQL volume to repair tests.
- Android emulator host access uses `10.0.2.2`; Web uses host loopback.
- `API_BASE_URL` is supplied using `--dart-define` when the default is unsuitable.

## 8. Known limitations

- Android integration did not complete because the emulator became offline.
- Step 27H/27I did not execute PostgreSQL integration or live FastAPI/PostgreSQL CRUD.
- Real-backend manual acceptance remains postponed by user preference.
- Offset pagination can omit/duplicate records when concurrent writes change boundaries; client ID deduplication only handles duplicates received.
- Web login state is memory-only and ends on reload.
- FarmService has one-shot mutation and stale-session protection, but Farm mutation recovery is less comprehensive than CropCycle authoritative inspection.
- Crop lifecycle transitions are not modeled.
- No archive/history policy exists for completed CropCycles.
- No optimistic concurrency/versioning exists.
- No production deployment, backups, monitoring, release signing, or operational security baseline exists.

## 9. Future manual acceptance plan

This plan is for a later user-scheduled session. It is not required now. Use only synthetic accounts and disposable test records; do not delete an existing Tomato record or reset the database.

1. Start the existing PostgreSQL service and development backend without changing volumes. **PASS:** health endpoint returns 200 and migrations are current. **FAIL:** service, migration, or health errors.
2. Launch one client with the correct local API URL and log in to a synthetic account. **PASS:** verified profile appears without exposing tokens. **FAIL:** unexpected login/session error.
3. Create a disposable Farm with a unique name. Refresh My Farms. **PASS:** exactly one Farm persists. **FAIL:** missing or duplicated Farm.
4. Open My Crop Cycles, select the disposable Farm, and create a uniquely named CropCycle with date-only fields. **PASS:** it appears once after refresh. **FAIL:** wrong Farm, duplicate, missing, or shifted date.
5. Open Details. **PASS:** authoritative values and Farm name match. **FAIL:** cached/wrong/missing values.
6. Edit the CropCycle, explicitly clear optional variety/harvest/count/notes, and save. **PASS:** cleared values remain empty after authoritative refresh. **FAIL:** old values return or Farm assignment changes.
7. Open Delete and cancel. **PASS:** record remains and no deletion message appears. **FAIL:** record disappears.
8. Confirm deletion of only the disposable CropCycle. **PASS:** Details closes, filtered list refreshes, and the record is absent. **FAIL:** wrong record removed or stale record remains.
9. Switch All Farms ↔ disposable Farm and refresh. **PASS:** filter and list contents remain consistent. **FAIL:** cross-Farm data or lost selection.
10. Use browser Back through Edit/Details/List. **PASS:** navigation is session-safe and filter state is preserved. **FAIL:** protected stale route or lost state.
11. Repeat navigation and keyboard/scroll checks on Android. **PASS:** controls are reachable, Back is correct, and no framework exception occurs. **FAIL:** overflow, stuck keyboard, unreachable action, or crash.
12. Log out, then use browser/device Back. **PASS:** protected data is cleared and login is required. **FAIL:** previous-account data remains visible.

## 10. Smart-farming readiness

| Area | Actual status |
|---|---|
| Weather data | Not implemented; no provider, cache, units, attribution, or key handling selected. |
| Crop monitoring | Only manual Farm/CropCycle records exist; no sensor, imagery, observation, or time-series feature. |
| Recommendations | Not implemented; no agronomy source, rules engine, or recommendation schema. |
| Disease detection | Not implemented; no inference path or dataset. |
| Machine learning | Not implemented; `ml/` contains no source files. |
| AI agents | Not implemented; no model/provider/tool contract. |
| Multi-agent orchestration | Not implemented; no runtime, roles, permission model, or evaluation harness. |
| Notifications/reminders | Not implemented; no scheduler, consent flow, or delivery provider. |
| Production deployment | Not implemented; no hosting, TLS, secret store, backup, monitoring, or release workflow. |

## 11. Recommended next-phase sequence

Keep each step independently reviewable:

1. Close the verification gap: run isolated PostgreSQL integration and scheduled manual Android/Web acceptance when the user is ready.
2. Define CropCycle lifecycle/archive/concurrency requirements before adding more write behavior.
3. Add a small, provider-neutral observation/monitoring data contract with backend tests; do not start with AI.
4. Decide weather geography, units, freshness, attribution, provider, and secret handling; then add a read-only adapter with contract tests and caching.
5. Define evidence-backed recommendation inputs/outputs, safety language, and provenance before implementing rules or models.
6. If disease detection is prioritized, decide licensed data, target classes, evaluation metrics, inference location, privacy, and escalation behavior before selecting a model.
7. Define agent responsibilities, tool permissions, audit logs, human confirmation, privacy, cost, and evaluation before selecting any AI provider or orchestration framework.
8. Add notifications only after triggers, timezone behavior, consent, deduplication, and opt-out requirements are explicit.
9. Establish staging, pinned dependencies, secret management, backups/restore, monitoring, TLS, release signing, and rollback before claiming production readiness.

Open product decisions include target regions/crops/languages, lifecycle policy, archive/delete rules, observation fields, weather and AI providers, agronomy sources, disease scope, privacy/retention, notification channels, and hosting requirements.

## 12. Historical evidence state

At Step 27I start, Git still showed these tracked files deleted:

- `AgroCrew-Step-27D-CropCycle-List-Review-Evidence.md`
- `AgroCrew-Step-27D1-List-UI-Hardening-Review-Evidence.md`

These untracked historical review files remained present:

- `AgroCrew-Step-27E1-Add-CropCycle-Final-Review-Evidence.md`
- `AgroCrew-Step-27F-CropCycle-Details-Review-Evidence.md`
- `AgroCrew-Step-27G-Edit-Delete-Review-Evidence.md`
- `AgroCrew-Step-27G1-Mutation-Safety-Review-Evidence.md`

Step 27H evidence is committed. The deletions were not assumed accidental; no historical evidence was restored, deleted, overwritten, staged, or committed during Step 27I. Cleanup remains a separate user decision.

## 13. Handover verdict

**PASS WITH WARNINGS:** documentation now reflects the implemented CropCycle phase and current automated evidence. Outstanding Android, isolated PostgreSQL, real-backend manual acceptance, and production-readiness gaps remain explicit.
