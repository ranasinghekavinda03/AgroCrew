# AgroCrew Step 27H — Automated Integration Review Evidence

Date: 2026-11-26 (Asia/Calcutta)

## 1. Executive Summary

Step 27H added one isolated, mock-backed Flutter integration test file and performed native, genuine-Web, Android-attempted, backend, and environment verification. No production application code, backend schema, dependency version, user account, Farm, CropCycle, Docker volume, or PostgreSQL record was changed.

Final verdict: **PASS WITH WARNINGS**. All feasible deterministic automation passed. Genuine Chrome Web execution passed both the existing model harness and the new production-widget CropCycle flow. Android build/install succeeded, but the emulator later became offline before a final passing device run could complete. PostgreSQL integration was safely skipped because an isolated database could not be confirmed and Docker was unavailable.

Manual real-backend CRUD testing remains postponed by user preference.

## 2. Initial Repository State

Initial HEAD:

`8681f5a465c331d7ed377846f02fd54d3349d291`

Initial `git status --short`:

```text
 D AgroCrew-Step-27D-CropCycle-List-Review-Evidence.md
 D AgroCrew-Step-27D1-List-UI-Hardening-Review-Evidence.md
?? AgroCrew-Step-27E1-Add-CropCycle-Final-Review-Evidence.md
?? AgroCrew-Step-27F-CropCycle-Details-Review-Evidence.md
?? AgroCrew-Step-27G-Edit-Delete-Review-Evidence.md
?? AgroCrew-Step-27G1-Mutation-Safety-Review-Evidence.md
```

The two tracked deletions and four untracked review documents were pre-existing. They were preserved without restoring, staging, deleting, committing, or pushing.

Initial `git diff --check`: exit 0, no whitespace errors.

Initial `git diff --stat`: only the two pre-existing evidence deletions, 3,906 deleted lines.

## 3. Existing Integration Infrastructure

- `mobile/integration_test/` already contained real-backend Android Farm/auth flows, logout/token-refresh flows, Web refresh/logout/Farm harnesses, and a genuine-Web CropCycle model harness.
- `mobile/test_driver/integration_test.dart` uses Flutter's standard `integration_test_driver`.
- Production constructors already support injection through `ApiClient`, `AuthService`, `AuthSession`, and `AuthenticatedProfileScreen.featureApiClient`.
- Existing CropCycle widget/service/model tests already cover pagination, filter races, session invalidation, token refresh, mutation ambiguity, authoritative inspection, Unicode, date-only values, status rendering, and responsive layouts.
- Backend ordinary API tests use isolated SQLite. PostgreSQL tests are explicitly opt-in through `RUN_POSTGRES_INTEGRATION=1`.
- The reliable Windows approaches were:
  - `flutter test` for unit/widget suites.
  - `flutter test -d flutter-tester` for the mock-backed integration file.
  - `flutter run -d chrome --target ...` for genuine `kIsWeb == true` execution.
  - Existing Android emulator for build/install and attempted runtime execution.

## 4. Environment and Device Availability

| Item | Result |
|---|---|
| Flutter | 3.47.6 stable, framework revision `5fc346839b` |
| Dart | 3.13.5 stable |
| Flutter doctor | Exit 0; no issues found |
| Windows device | Available, but project has no Windows desktop runner |
| Chrome | 158.0.8127.38, available |
| Edge | 158.0.4370.33, available |
| ChromeDriver | Not found; not installed |
| Android SDK | 37.0.0 |
| Android emulator | Pixel 8 / Android 17 API 37 installed |
| Docker | Command not found |
| Live FastAPI | Not listening at `127.0.0.1:8000` |
| Backend Python | Repository virtual environment available (Python 3.11 executable) |
| PostgreSQL state/migrations | Not inspected because Docker/live database isolation was unavailable |
| integration_test dependency | Present from Flutter SDK |
| test driver | Present at `mobile/test_driver/integration_test.dart` |

No SDK, driver, Android image, package, or dependency was installed or upgraded.

## 5. New or Modified Test Files

Created:

- `mobile/integration_test/crop_cycle_flow_test.dart`

No production source files were modified.

## 6. Automated CropCycle CRUD Integration

The new integration file uses production widgets, models, services, session handling, and `ApiClient`, with only the HTTP transport replaced by `MockClient`.

Verified scenario 1:

- Authenticated Profile → My Crop Cycles.
- Initial list and owned Farm metadata.
- Farm filter selection and preservation.
- Add navigation with the active Farm preselected.
- Unicode and date-only create data.
- Exactly one authenticated POST with HTTP 201.
- First-page filtered refresh and created record visibility.
- Details navigation and authoritative GET.
- Farm name, Unicode, and date-only presentation.
- Authoritative details refresh.
- Edit navigation and prepopulation.
- Explicit clearing of nullable fields.
- Exactly one PUT; no `farm_id` reassignment.
- Authoritative updated details.
- Delete cancellation sends zero DELETEs.
- Confirmed deletion sends exactly one DELETE and accepts HTTP 204.
- Details closes, filtered list reloads, deleted record disappears.

Verified scenario 2:

- Full first page.
- Load More with overlapping server page.
- Duplicate ID is not rendered twice.
- Server offset advances to 20.
- Farm-specific filtering.
- Refresh preserves the filter.
- Returning to All Farms removes `farm_id`.

Synthetic account, token, Farm, and CropCycle fixtures were used. No user-owned record was contacted.

## 7. Authentication and Session Isolation

Existing passing suites verify:

- Proactive access-token refresh.
- GET 401 refresh and retry.
- Terminal 401 handling.
- Logout and protected-route clearing.
- Account replacement and stale response rejection.
- Concurrent refresh single-flight behavior.
- In-flight CropCycle reads and mutations invalidated by logout/account replacement.
- No prior-account data accepted under a replacement account.

Focused evidence:

- `automatic_token_refresh_test.dart`: 17 passed.
- `logout_session_test.dart`: 11 passed.
- `crop_cycle_service_test.dart`: 70 passed.
- Full native suite: 474 passed.

The new integration test additionally asserts that every CRUD request uses the synthetic authenticated access header.

## 8. Mutation Uncertainty Verification

Existing passing CropCycle service and screen tests cover:

- HTTP 500 after mutation.
- Lost response / connection error.
- Mutation timeout.
- Unexpected mutation success status.
- Malformed mutation success payload.
- Authoritative inspection success/failure after ambiguous update/delete.
- No automatic POST, PUT, or DELETE replay.
- Sanitized messages without raw response bodies or token values.
- Mutation controls blocked until required inspection.
- Stale-session precedence during logout/account replacement.

The new end-to-end flow confirms the normal confirmed path still sends one POST, one PUT, and one DELETE.

## 9. Backend API Contract Verification

Command:

`backend\.venv\Scripts\python.exe -m pytest -q -rs`

Result: exit 0 — **199 passed, 4 skipped, 1 warning** in 19.33 seconds.

Skipped tests were exactly the four opt-in PostgreSQL suites:

- `test_crop_cycle_api_postgres_integration.py`
- `test_crop_cycle_postgres_integration.py`
- `test_farm_api_postgres_integration.py`
- `test_farm_postgres_integration.py`

The ordinary API tests verified the CropCycle contract:

- POST `/api/v1/crops` → 201.
- GET collection/detail → 200.
- PUT replacement → 200.
- DELETE → 204 with empty response.
- Authentication required.
- Ownership-aware 404.
- Validation 422.
- Farm delete conflict 409 where related records exist.
- ISO date-only JSON.
- Nullable fields cleared by full replacement PUT.
- Status values: planned, active, harvested, cancelled.
- Limit/offset pagination and optional owned `farm_id`.

Contract comparison found no Flutter/backend mismatch. Flutter create includes `farm_id`; update omits it; nullable update fields serialize explicitly as null; date-only values remain `YYYY-MM-DD`; and HTTP 201/200/204 expectations match the backend.

The warning was a dependency deprecation warning from FastAPI/Starlette's TestClient import and did not fail tests.

## 10. Genuine Chrome Web Runtime Results

### Existing model harness

Command:

`flutter run -d chrome --target integration_test/crop_cycle_model_web_harness.dart`

Exit after controlled quit: successful PASS marker observed.

```text
STEP27B2_CROP_CYCLE_WEB_PASS_RUNTIME_1_NUMERIC_13_UNICODE_9_DATE_10_TIMESTAMP_9_PAYLOAD_7
```

This proves genuine `kIsWeb == true` execution and verifies model numeric validation, Unicode boundaries, date-only handling, timestamps, and request payloads.

### Production-widget integration flow

Command:

`flutter run -d chrome --target integration_test/crop_cycle_flow_test.dart`

Result:

```text
00:00 +0: authenticated CropCycle CRUD navigation uses one mutation each
03:02 +1: pagination deduplicates overlaps and preserves filtering
03:04 +2: (tearDownAll)
03:04 +3: All tests passed!
```

PASS. This was genuine compiled Flutter Web runtime, not merely compilation. It used the real production widgets/services with isolated mock HTTP and did not claim PostgreSQL persistence.

Non-failing lifecycle channel-buffer warnings appeared during Web startup.

## 11. Android Runtime Results

An existing Pixel 8 emulator was launched without installation or reconfiguration.

Observed:

- Android 17 / API 37 device became connected as `emulator-5554`.
- Gradle debug build completed.
- APK installed successfully.
- The first run reached authenticated create/details UI and exposed a lazy-list test-driver assumption.
- The test driver was adjusted to scroll controls into the widget tree without changing production code.
- During the bounded rerun the emulator became `offline`; Flutter reported `adb.exe: device offline` and could not finalize/uninstall the test package.

Final status:

**Android runtime integration: NOT COMPLETED — emulator became unavailable/offline.**

This is an environmental warning, not a demonstrated production defect. No real device was tested.

## 12. Isolated PostgreSQL Integration Results

**NOT EXECUTED.**

Docker was not available and no dedicated isolated PostgreSQL database could be confirmed. The opt-in tests were left skipped. No development database was reset, truncated, migrated, or mutated.

## 13. Focused Flutter Test Results

| Command target | Exit | Passed |
|---|---:|---:|
| New `integration_test/crop_cycle_flow_test.dart` on `flutter-tester` | 0 | 2 |
| `crop_cycle_screens_test.dart` | 0 | 42 |
| `add_crop_cycle_screen_test.dart` | 0 | 28 |
| `crop_cycle_details_screen_test.dart` | 0 | 36 |
| `edit_crop_cycle_screen_test.dart` | 0 | 25 |
| `crop_cycle_service_test.dart` | 0 | 70 |
| `crop_cycle_model_test.dart` | 0 | 95 |
| `automatic_token_refresh_test.dart` | 0 | 17 |
| `logout_session_test.dart` | 0 | 11 |
| Farm screen + service regression | 0 | 47 |

These are separate runner counts and are not added to the full-suite total.

## 14. Full Flutter Regression Results

### Initial baseline

- `flutter analyze`: exit 0, no issues.
- `flutter test --reporter compact`: exit 0, **474 passed, 0 failed, 0 skipped**.

### Final baseline

- `flutter analyze`: exit 0, no issues (35.8 seconds).
- `flutter test --reporter compact`: exit 0, **474 passed, 0 failed, 0 skipped**.

The integration test lives under `integration_test/` and is reported separately.

## 15. Exact Commands and Exit Codes

| Command | Exit/result |
|---|---|
| `git status --short` | 0 |
| `git rev-parse HEAD` | 0 |
| `git diff --check` | 0 |
| `git diff --stat` | 0 |
| `flutter --version` | 0 |
| `dart --version` | 0 |
| `flutter doctor -v` | 0 |
| `flutter devices` | 0 |
| `flutter emulators` | 0 |
| `docker version` | command unavailable |
| FastAPI health request | connection unavailable |
| `flutter analyze` | 0 |
| `flutter test --reporter compact` | 0; 474 passed |
| `flutter test -d flutter-tester integration_test/crop_cycle_flow_test.dart --reporter expanded` | 0; 2 passed |
| `backend\.venv\Scripts\python.exe -m pytest -q -rs` | 0; 199 passed, 4 skipped |
| `flutter run -d chrome --target integration_test/crop_cycle_model_web_harness.dart` | PASS marker |
| `flutter run -d chrome --target integration_test/crop_cycle_flow_test.dart` | All tests passed |
| Android integration command | build/install succeeded; runtime not completed after device went offline |

## 16. Verified vs Unverified Coverage

Verified:

- Flutter native unit/widget regression.
- Mock-backed production-widget CropCycle integration.
- Navigation, filter preservation, create/details/edit/delete.
- Pagination overlap deduplication.
- Authentication/session safety through existing deterministic suites.
- Mutation uncertainty through existing deterministic suites.
- Backend API contract through isolated ordinary API tests.
- Genuine Chrome Web model and production-widget execution.

Unverified:

- Real PostgreSQL persistence/integrity in this environment.
- Live FastAPI-to-PostgreSQL runtime.
- Completed Android emulator flow after the emulator became offline.
- Physical Android device behavior.
- User-owned data behavior.
- Manual real-backend CRUD.

## 17. Known Risks and Limitations

- PostgreSQL-specific constraints and locking were not executed in Step 27H.
- Android completion remains pending because the existing emulator became unstable/offline.
- Chrome tests used isolated mock transport, so they do not verify real backend persistence.
- ChromeDriver was unavailable; the project-compatible `flutter run -d chrome` harness was used instead.
- The Web runner emitted non-fatal lifecycle buffer warnings.
- Backend TestClient emitted one deprecation warning.

## 18. Final Git State

Expected Step 27H additions:

```text
?? AgroCrew-Step-27H-Automated-Integration-Review-Evidence.md
?? mobile/integration_test/crop_cycle_flow_test.dart
```

The pre-existing two tracked deletions and four untracked evidence files remain preserved. Nothing was staged, committed, pushed, restored, or deleted.

Final HEAD remains:

`8681f5a465c331d7ed377846f02fd54d3349d291`

Final `git diff --check`: required to remain exit 0.

## 19. Complete Evidence Document Path

`AgroCrew-Step-27H-Automated-Integration-Review-Evidence.md`

## 20. Deferred Manual Verification

Manual testing was postponed by user preference, not forgotten.

Deferred until the user explicitly schedules it:

- Real backend login.
- Real PostgreSQL CropCycle create/edit/delete.
- User-owned Farm filtering.
- Manual browser interaction.
- Manual Android/physical-device interaction.

## 21. Final Verdict

**PASS WITH WARNINGS — All feasible automated verification passed. Genuine Chrome and native automation passed; Android completion and isolated PostgreSQL execution remain unavailable.**

Step 27H ends here. Step 27I was not started.

## Appendix A — Complete Source of Changed Test File

The following block is the complete normalized source of `mobile/integration_test/crop_cycle_flow_test.dart`.

<!-- BEGIN SOURCE: mobile/integration_test/crop_cycle_flow_test.dart -->
```dart
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/auth/presentation/authenticated_profile_screen.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/presentation/my_crop_cycles_screen.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('authenticated CropCycle CRUD navigation uses one mutation each', (
    tester,
  ) async {
    final transport = _CrudTransport();
    final fixture = await _fixture(transport.handle);
    addTearDown(fixture.close);
    await _pumpProfile(tester, fixture);

    expect(find.byKey(const Key('authenticated-profile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-crop-cycles-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(
      find.byKey(const Key('crop-cycle-card-21')),
      findsOneWidget,
      reason:
          'requests=${transport.requests}; '
          'texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
    );

    await _select(
      tester,
      const Key('crop-cycles-farm-filter'),
      'South Farm (Farm #2)',
    );
    expect(transport.lastCropQuery['farm_id'], '2');
    await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
    await tester.pumpAndSettle();
    expect(find.text('Add Crop Cycle'), findsWidgets);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const Key('crop-farm-field')),
          )
          .initialValue,
      2,
    );
    await _enter(tester, const Key('crop-type-field'), 'Chilli · மிளகாய் 🌱');
    await _enter(tester, const Key('crop-variety-field'), 'Kochchi');
    await _enter(tester, const Key('planting-date-field'), '2026-11-26');
    await _enter(
      tester,
      const Key('expected-harvest-date-field'),
      '2027-02-01',
    );
    await _enter(tester, const Key('plant-count-field'), '40');
    await _enter(tester, const Key('crop-notes-field'), 'සිංහල Tamil English');
    await _tapVisible(tester, const Key('create-crop-cycle-button'));
    await tester.pumpAndSettle();

    expect(transport.posts, 1);
    expect(transport.authorizations, everyElement('Bearer synthetic-access'));
    expect(transport.postBodies.single['farm_id'], 2);
    expect(transport.postBodies.single['planting_date'], '2026-11-26');
    expect(find.byKey(const Key('crop-cycle-card-22')), findsOneWidget);
    expect(_farmFilterValue(tester), 2);

    await tester.tap(find.byKey(const Key('open-crop-cycle-22')));
    await tester.pumpAndSettle();
    expect(find.text('Crop Cycle Details'), findsOneWidget);
    expect(find.text('Chilli · மிளகாய் 🌱'), findsOneWidget);
    expect(find.text('South Farm (Farm #2)'), findsOneWidget);
    await _assertVisibleText(tester, '2026-11-26');
    final detailGetsBeforeRefresh = transport.detailGets;
    await tester.tap(find.byKey(const Key('crop-cycle-details-refresh')));
    await tester.pumpAndSettle();
    expect(transport.detailGets, detailGetsBeforeRefresh + 1);

    await _tapVisible(tester, const Key('edit-crop-cycle-button'));
    await tester.pumpAndSettle();
    expect(
      _fieldText(tester, const Key('edit-crop-type-field')),
      contains('Chilli'),
    );
    expect(find.text('South Farm (Farm #2)'), findsOneWidget);
    await _enter(tester, const Key('edit-crop-type-field'), 'Updated Chilli');
    await _enter(tester, const Key('edit-crop-variety-field'), '');
    await _enter(tester, const Key('edit-expected-harvest-date-field'), '');
    await _enter(tester, const Key('edit-plant-count-field'), '');
    await _enter(tester, const Key('edit-crop-notes-field'), '');
    await _tapVisible(tester, const Key('save-crop-cycle-changes-button'));
    await tester.pumpAndSettle();

    expect(transport.puts, 1);
    final update = transport.putBodies.single;
    expect(update['variety'], isNull);
    expect(update['expected_harvest_date'], isNull);
    expect(update['plant_count'], isNull);
    expect(update['notes'], isNull);
    expect(update, isNot(contains('farm_id')));
    expect(find.text('Updated Chilli'), findsOneWidget);

    await _tapVisible(tester, const Key('delete-crop-cycle-button'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-cancel')));
    await tester.pumpAndSettle();
    expect(transport.deletes, 0);
    await _tapVisible(tester, const Key('delete-crop-cycle-button'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-confirm')));
    await tester.pumpAndSettle();

    expect(transport.deletes, 1);
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(_farmFilterValue(tester), 2);
    expect(find.byKey(const Key('crop-cycle-card-22')), findsNothing);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination deduplicates overlaps and preserves filtering', (
    tester,
  ) async {
    final transport = _PaginationTransport();
    final fixture = await _fixture(transport.handle);
    addTearDown(fixture.close);
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
    final cropScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: cropScrollable,
    );
    await tester.drag(cropScrollable, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(transport.cropOffsets, containsAllInOrder(['0', '20']));

    await _select(
      tester,
      const Key('crop-cycles-farm-filter'),
      'South Farm (Farm #2)',
    );
    expect(transport.lastFarmId, '2');
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(transport.lastFarmId, '2');
    await _select(tester, const Key('crop-cycles-farm-filter'), 'All Farms');
    expect(transport.lastFarmId, isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpProfile(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AuthenticatedProfileScreen(
        authService: fixture.auth,
        session: fixture.session,
        featureApiClient: fixture.client,
      ),
    ),
  );
}

Future<void> _pumpCrops(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MyCropCyclesScreen(
        cropCycleService: fixture.crops,
        farmService: fixture.farms,
        session: fixture.session,
      ),
    ),
  );
}

Future<void> _select(WidgetTester tester, Key key, String label) async {
  final field = find.byKey(key);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key);
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
}

Future<void> _assertVisibleText(WidgetTester tester, String value) async {
  final text = find.text(value);
  if (text.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      text,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  expect(text, findsOneWidget);
}

String _fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextFormField>(find.byKey(key)).controller!.text;

int? _farmFilterValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )
    .initialValue;

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 26, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(seconds: 2),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(
    LoginResponse(
      accessToken: 'synthetic-access',
      refreshToken: 'synthetic-refresh',
      issuedAt: now,
      expiresIn: const Duration(minutes: 30),
      refreshExpiresIn: const Duration(days: 7),
    ),
    UserProfile(
      id: 7,
      name: 'Integration Farmer',
      email: 'integration@example.test',
      preferredLanguage: 'English',
      isActive: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return _Fixture(
    client: client,
    auth: auth,
    session: session,
    crops: CropCycleService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
    farms: FarmService(apiClient: client, session: session, authService: auth),
  );
}

class _CrudTransport {
  final List<String> requests = [];
  final List<String?> authorizations = [];
  final List<Map<String, Object?>> postBodies = [];
  final List<Map<String, Object?>> putBodies = [];
  final List<Map<String, Object?>> crops = [
    _crop(21, cropType: 'Tomato', variety: 'Roma'),
  ];
  Map<String, String> lastCropQuery = const {};
  int posts = 0;
  int puts = 0;
  int deletes = 0;
  int detailGets = 0;

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url}');
    authorizations.add(
      request.headers['authorization'] ?? request.headers['Authorization'],
    );
    final path = request.url.path;
    if (path == '/api/v1/farms') return _json([_farm(2, 'South Farm')]);
    if (path == '/api/v1/farms/2') return _json(_farm(2, 'South Farm'));
    if (path == '/api/v1/crops' && request.method == 'GET') {
      lastCropQuery = request.url.queryParameters;
      final farmId = int.tryParse(request.url.queryParameters['farm_id'] ?? '');
      return _json(
        crops
            .where((crop) => farmId == null || crop['farm_id'] == farmId)
            .toList(),
      );
    }
    if (path == '/api/v1/crops' && request.method == 'POST') {
      posts++;
      final body = _body(request);
      postBodies.add(body);
      final created = _cropFromBody(22, body);
      crops.add(created);
      return _json(created, status: 201);
    }
    if (path == '/api/v1/crops/22' && request.method == 'GET') {
      detailGets++;
      return _json(crops.singleWhere((crop) => crop['id'] == 22));
    }
    if (path == '/api/v1/crops/22' && request.method == 'PUT') {
      puts++;
      final body = _body(request);
      putBodies.add(body);
      final index = crops.indexWhere((crop) => crop['id'] == 22);
      crops[index] = {
        ...crops[index],
        ...body,
        'id': 22,
        'farm_id': 2,
        'updated_at': '2026-11-26T13:00:00Z',
      };
      return _json(crops[index]);
    }
    if (path == '/api/v1/crops/22' && request.method == 'DELETE') {
      deletes++;
      crops.removeWhere((crop) => crop['id'] == 22);
      return http.Response('', 204);
    }
    return http.Response('{}', 404);
  }
}

class _PaginationTransport {
  final List<String> cropOffsets = [];
  String? lastFarmId;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/api/v1/farms') {
      return _json([_farm(2, 'South Farm')]);
    }
    if (request.url.path == '/api/v1/crops') {
      final offset = request.url.queryParameters['offset']!;
      cropOffsets.add(offset);
      lastFarmId = request.url.queryParameters['farm_id'];
      if (lastFarmId != null) return _json([_crop(2)]);
      if (offset == '0') {
        return _json(List.generate(20, (index) => _crop(index + 1)));
      }
      if (offset == '20') return _json([_crop(20), _crop(21)]);
      return _json([]);
    }
    return http.Response('{}', 404);
  }
}

Map<String, Object?> _body(http.Request request) =>
    (jsonDecode(request.body) as Map<String, dynamic>).cast<String, Object?>();

Map<String, Object?> _farm(int id, String name) => {
  'id': id,
  'user_id': 7,
  'name': name,
  'latitude': null,
  'longitude': null,
  'area_value': null,
  'area_unit': null,
  'notes': null,
  'created_at': '2026-10-24T10:00:00Z',
  'updated_at': '2026-10-24T11:00:00Z',
};

Map<String, Object?> _crop(
  int id, {
  String cropType = 'Crop',
  String? variety,
}) => {
  'id': id,
  'farm_id': 2,
  'crop_type': '$cropType $id',
  'variety': variety,
  'planting_date': '2026-11-03',
  'expected_harvest_date': '2027-01-10',
  'status': 'active',
  'plant_count': 25,
  'notes': 'Synthetic integration fixture',
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:00:00Z',
};

Map<String, Object?> _cropFromBody(int id, Map<String, Object?> body) => {
  'id': id,
  ...body,
  'created_at': '2026-11-26T12:00:00Z',
  'updated_at': '2026-11-26T12:00:00Z',
};

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  const _Fixture({
    required this.client,
    required this.auth,
    required this.session,
    required this.crops,
    required this.farms,
  });

  final ApiClient client;
  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
  final FarmService farms;

  void close() {
    session.dispose();
    client.close();
  }
}
```
<!-- END SOURCE: mobile/integration_test/crop_cycle_flow_test.dart -->


