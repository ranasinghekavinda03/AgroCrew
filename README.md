# AgroCrew

AgroCrew is a Flutter and FastAPI farming application. The current implemented product supports authenticated accounts, Farm management, and CropCycle management on Android and Flutter Web. Weather, disease detection, machine learning, recommendations, notifications, and multi-agent orchestration are future product areas; they are not implemented yet.

## Current capabilities

- Registration, login, current profile, access-token refresh, logout, and session restoration.
- Android secure token storage. Web sessions are memory-only and end on reload.
- Authenticated Farm list, details, create, edit, delete, and offset pagination.
- Authenticated CropCycle list, Farm filtering, Farm metadata pagination, create, details, edit, delete, refresh, and offset pagination.
- Server-side ownership enforcement for Farms and CropCycles.
- Date-only CropCycle fields and four statuses: `planned`, `active`, `harvested`, and `cancelled`.
- Full-replacement PUT behavior: omitted optional values are cleared, and a CropCycle cannot be moved to another Farm.
- Client safeguards for token refresh, account replacement, stale asynchronous responses, uncertain mutations, and authoritative post-mutation inspection.

The project is not production-ready. Live PostgreSQL acceptance, completed Android runtime integration, deployment, release signing, operational monitoring, and the future smart-farming features remain outstanding.

## Repository layout

| Path | Purpose |
|---|---|
| `backend/app/` | FastAPI routes, schemas, services, authentication, and SQLAlchemy models. |
| `backend/alembic/` | PostgreSQL schema migrations. |
| `backend/tests/` | Isolated API tests and opt-in PostgreSQL integration tests. |
| `mobile/lib/` | Flutter Android/Web application. |
| `mobile/test/` | Flutter unit and widget tests. |
| `mobile/integration_test/` | Mock-backed and runtime integration harnesses. |
| `docs/` | API notes and project handover documentation. |
| `ml/` | Reserved directory; no ML implementation is present. |

## Architecture

```text
Flutter Android/Web
  -> AuthSession and feature services
  -> JSON HTTP with Bearer access token
  -> FastAPI routes and authentication dependency
  -> Farm/CropCycle service layer
  -> SQLAlchemy
  -> PostgreSQL managed by Alembic
```

The backend derives ownership from the authenticated User. CropCycle ownership is resolved through its parent Farm; Flutter UI checks are not an authorization boundary.

## Local development commands

These commands are documented for future development. They are not a request to run manual testing now.

### Check and start PostgreSQL

```powershell
docker --version
docker compose ps
docker compose up -d postgres
```

Preserve the existing database volume. Do not use `docker compose down -v`, volume deletion, database drops, or destructive resets.

### Start the backend

The ignored `backend/.env` must be configured locally from `backend/.env.example`. Never commit or print its contents.

```powershell
Set-Location backend
& .\.venv\Scripts\Activate.ps1
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Run Flutter Web

```powershell
Set-Location mobile
flutter run -d chrome --web-port 58581 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

An Android emulator uses the host alias `http://10.0.2.2:8000` instead of `127.0.0.1`.

## Automated verification

### Flutter native unit/widget tests

```powershell
Set-Location mobile
flutter analyze
flutter test --reporter compact
```

Latest Step 27I result on 2026-11-26:

- Analysis: no issues.
- Native unit/widget suite: 474 passed, 0 failed, 0 skipped.

### Mock-backed CropCycle integration

```powershell
Set-Location mobile
flutter test -d flutter-tester integration_test/crop_cycle_flow_test.dart --reporter expanded
```

Latest Step 27I result: 2 passed. This uses production widgets and services with an isolated `MockClient`; it does not prove PostgreSQL persistence.

### Genuine Chrome Web integration

```powershell
Set-Location mobile
flutter run -d chrome --target integration_test/crop_cycle_flow_test.dart
flutter run -d chrome --target integration_test/crop_cycle_model_web_harness.dart
```

The production-widget Chrome flow passed in Step 27I. The model harness passed in Step 27H with `kIsWeb == true`.

### Backend API tests

```powershell
Set-Location backend
.\.venv\Scripts\python.exe -m pytest -q -rs
```

Latest Step 27I result: 199 passed, 4 skipped, 1 dependency deprecation warning. The four skipped modules require explicitly isolated PostgreSQL infrastructure.

### PostgreSQL integration tests

Run these only when the configured database is verified as disposable and isolated:

```powershell
Set-Location backend
$env:RUN_POSTGRES_INTEGRATION = '1'
try {
  .\.venv\Scripts\python.exe -m pytest -q -rs `
    tests\test_crop_cycle_api_postgres_integration.py `
    tests\test_crop_cycle_postgres_integration.py `
    tests\test_farm_api_postgres_integration.py `
    tests\test_farm_postgres_integration.py
}
finally {
  Remove-Item Env:RUN_POSTGRES_INTEGRATION -ErrorAction SilentlyContinue
}
```

These tests were not run in Steps 27H or 27I because isolated PostgreSQL could not be confirmed.

## Important limitations

- Offset pagination can duplicate or omit records when concurrent inserts/deletes shift page boundaries. The Flutter CropCycle list deduplicates IDs it receives, but it cannot provide snapshot consistency.
- Web authentication is intentionally memory-only; a browser reload requires login.
- Access JWTs remain valid until expiry after logout; logout revokes refresh tokens.
- Updates are last-writer-wins; no optimistic version field exists.
- FarmService protects one-shot mutations and stale sessions, but it does not provide the CropCycle UI's full authoritative inspection workflow for every uncertain Farm mutation.
- Android integration built and installed in Step 27H, but the emulator became offline before final completion.
- No current real-backend manual CropCycle acceptance result is claimed.
- Android release configuration uses debug signing.
- Python dependencies are broad requirements rather than a fully pinned lockfile.

See [`docs/AGROCREW_PROJECT_HANDOVER.md`](docs/AGROCREW_PROJECT_HANDOVER.md) for the feature inventory, API contract, security audit, manual acceptance plan, and next-phase readiness assessment.
