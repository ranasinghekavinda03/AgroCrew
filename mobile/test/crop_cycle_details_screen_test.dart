import 'dart:async';
import 'dart:convert';

import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/auth/data/models/login_response.dart';
import 'package:agrocrew/features/auth/data/models/user_profile.dart';
import 'package:agrocrew/features/crops/data/crop_cycle_service.dart';
import 'package:agrocrew/features/crops/presentation/crop_cycle_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('loads authoritative details with bearer auth and all fields', (
    tester,
  ) async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      calls++;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/crops/12');
      expect(request.headers['authorization'], 'Bearer access');
      return _jsonResponse(
        _crop(
          12,
          farmId: 4,
          status: 'planned',
          cropType: 'Tomato',
          variety: 'Roma',
          plantingDate: '2024-02-29',
          expectedHarvestDate: '2024-12-31',
          plantCount: 120,
          notes: 'North bed',
        ),
      );
    });
    await _pumpDetails(
      tester,
      fixture,
      cropCycleId: 12,
      knownFarmId: 4,
      knownFarmName: 'Demo Farm',
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Crop Cycle Details'), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('Demo Farm (Farm #4)'), findsOneWidget);
    expect(find.text('Roma'), findsOneWidget);
    expect(find.text('2024-02-29'), findsOneWidget);
    expect(find.text('2024-12-31'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('North bed'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('2026-11-03 10:00:00 UTC'), findsOneWidget);
    expect(find.text('2026-11-03 11:30:00 UTC'), findsOneWidget);
  });

  for (final status in {
    'planned': 'Planned',
    'active': 'Active',
    'harvested': 'Harvested',
    'cancelled': 'Cancelled',
  }.entries) {
    testWidgets('renders ${status.key} and neutral optional values', (
      tester,
    ) async {
      final fixture = await _fixture(
        (_) async => _jsonResponse(_crop(3, status: status.key)),
      );
      await _pumpDetails(tester, fixture, cropCycleId: 3);
      await tester.pumpAndSettle();
      expect(find.text(status.value), findsOneWidget);
      expect(find.text('Farm #1'), findsOneWidget);
      expect(find.text('Not provided'), findsNWidgets(4));
      expect(find.text('null'), findsNothing);
    });
  }

  testWidgets('calendar dates do not shift and timestamps preserve instants', (
    tester,
  ) async {
    final fixture = await _fixture(
      (_) async => _jsonResponse(
        _crop(
          5,
          plantingDate: '2000-02-29',
          expectedHarvestDate: '2001-01-01',
          createdAt: '2026-12-31T23:45:00-05:00',
          updatedAt: '2027-01-01T05:00:00Z',
        ),
      ),
    );
    await _pumpDetails(tester, fixture, cropCycleId: 5);
    await tester.pumpAndSettle();
    expect(find.text('2000-02-29'), findsOneWidget);
    expect(find.text('2001-01-01'), findsOneWidget);
    expect(find.text('2027-01-01 04:45:00 UTC'), findsOneWidget);
    expect(find.text('2027-01-01 05:00:00 UTC'), findsOneWidget);
  });

  testWidgets('invalid ID is rejected without dispatch', (tester) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls++;
      return _jsonResponse(_crop(1));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 0);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('The crop cycle ID is invalid.'), findsOneWidget);
  });

  testWidgets('404 is safe and offers explicit return to list', (tester) async {
    final fixture = await _fixture(
      (_) async => http.Response('{"detail":"private"}', 404),
    );
    await _pumpDetails(tester, fixture, cropCycleId: 99);
    await tester.pumpAndSettle();
    expect(find.text('This crop cycle is unavailable.'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(
      find.byKey(const Key('return-to-crop-cycles-button')),
      findsOneWidget,
    );
  });

  testWidgets('network failure is sanitized and Retry recovers', (
    tester,
  ) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('private network detail');
      return _jsonResponse(_crop(7, cropType: 'Recovered'));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 7);
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.byKey(const Key('crop-cycle-details-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('timeout is recoverable without automatic retry', (tester) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final fixture = await _fixture((_) async {
      calls++;
      if (calls == 1) return pending.future;
      return _jsonResponse(_crop(8, cropType: 'After timeout'));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 8);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.textContaining('took too long'), findsOneWidget);
    expect(calls, 1);
    await tester.tap(find.byKey(const Key('crop-cycle-details-retry')));
    await tester.pumpAndSettle();
    expect(find.text('After timeout'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('server and invalid responses remain sanitized', (tester) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls++;
      return calls == 1
          ? http.Response('{"detail":"private"}', 500)
          : _jsonResponse({'id': 9});
    });
    await _pumpDetails(tester, fixture, cropCycleId: 9);
    await tester.pumpAndSettle();
    expect(find.textContaining('could not complete'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.byKey(const Key('crop-cycle-details-retry')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('invalid crop cycle information'),
      findsOneWidget,
    );
  });

  testWidgets('manual refresh uses newest response and ignores older result', (
    tester,
  ) async {
    final older = Completer<http.Response>();
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls++;
      if (calls == 1) return _jsonResponse(_crop(10, cropType: 'Initial'));
      if (calls == 2) return older.future;
      return _jsonResponse(_crop(10, cropType: 'Newest'));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 10);
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('crop-cycle-details-refresh'));
    await tester.tap(refresh);
    await tester.pump();
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
    older.complete(_jsonResponse(_crop(10, cropType: 'Older')));
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Older'), findsNothing);
  });

  testWidgets('record disappearing on refresh becomes unavailable', (
    tester,
  ) async {
    var calls = 0;
    final fixture = await _fixture((_) async {
      calls++;
      return calls == 1 ? _jsonResponse(_crop(11)) : http.Response('{}', 404);
    });
    await _pumpDetails(tester, fixture, cropCycleId: 11);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-cycle-details-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('This crop cycle is unavailable.'), findsOneWidget);
  });

  testWidgets('confirmed edit refreshes authoritative details', (tester) async {
    var gets = 0;
    var puts = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') {
        puts++;
        return _jsonResponse(_crop(12, cropType: 'Updated'));
      }
      gets++;
      return _jsonResponse(
        _crop(12, cropType: gets == 1 ? 'Original' : 'Updated'),
      );
    });
    await _pumpDetails(tester, fixture, cropCycleId: 12);
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('edit-crop-cycle-button'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-crop-type-field')),
      'Updated',
    );
    final save = find.byKey(const Key('save-crop-cycle-changes-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(puts, 1);
    expect(gets, 2);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Crop cycle updated successfully.'), findsOneWidget);
  });

  testWidgets(
    'uncertain edit stays locked after failed inspection then verifies current record',
    (tester) async {
      var gets = 0;
      var puts = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'PUT') {
          puts++;
          return http.Response('private', 500);
        }
        gets++;
        if (gets == 1) return _jsonResponse(_crop(12, cropType: 'Original'));
        if (gets == 2) return http.Response('private inspection', 500);
        return _jsonResponse(_crop(12, cropType: 'Verified'));
      });
      await _pumpDetails(tester, fixture, cropCycleId: 12);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-crop-cycle-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-crop-cycle-changes-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inspect-crop-cycle-button')));
      await tester.pumpAndSettle();

      expect(puts, 1);
      expect(gets, 2);
      expect(find.byKey(const Key('edit-crop-cycle-button')), findsNothing);
      expect(find.byKey(const Key('delete-crop-cycle-button')), findsNothing);
      expect(find.textContaining('private'), findsNothing);
      await tester.drag(
        find.byKey(const Key('crop-cycle-details-content')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('return-after-uncertain-delete-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('inspect-after-delete-button')));
      await tester.pumpAndSettle();
      expect(gets, 3);
      expect(puts, 1);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.byKey(const Key('edit-crop-cycle-button')), findsOneWidget);
      expect(find.byKey(const Key('delete-crop-cycle-button')), findsOneWidget);
    },
  );

  testWidgets('uncertain edit inspection 404 becomes unavailable', (
    tester,
  ) async {
    var gets = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'PUT') return http.Response('{}', 500);
      gets++;
      return gets == 1
          ? _jsonResponse(_crop(12, cropType: 'Original'))
          : http.Response('{}', 404);
    });
    await _pumpDetails(tester, fixture, cropCycleId: 12);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-crop-cycle-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-crop-cycle-changes-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspect-crop-cycle-button')));
    await tester.pumpAndSettle();

    expect(find.text('This crop cycle is unavailable.'), findsOneWidget);
    expect(
      find.byKey(const Key('return-to-crop-cycles-button')),
      findsOneWidget,
    );
  });

  testWidgets('delete confirmation Cancel dispatches zero DELETE requests', (
    tester,
  ) async {
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') deletes++;
      return _jsonResponse(_crop(13));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 13);
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('delete-crop-cycle-button'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Delete Crop Cycle?'), findsOneWidget);
    expect(find.textContaining('"Tomato"'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-crop-cycle-cancel')));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.byKey(const Key('crop-cycle-details-content')), findsOneWidget);
  });

  testWidgets('confirmed delete dispatches once and closes Details', (
    tester,
  ) async {
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        deletes++;
        expect(request.url.path, '/api/v1/crops/14');
        expect(request.headers['authorization'], 'Bearer access');
        return http.Response('', 204);
      }
      return _jsonResponse(_crop(14));
    });
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pumpAndSettle();
    await _confirmDelete(tester);
    expect(deletes, 1);
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
  });

  testWidgets('delete conflict keeps authoritative record visible', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.method == 'DELETE'
          ? http.Response('{"detail":"private"}', 409)
          : _jsonResponse(_crop(16)),
    );
    await _pumpDetails(tester, fixture, cropCycleId: 16);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);
    expect(
      find.text(
        'This crop cycle cannot be deleted because it has related records.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private'), findsNothing);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.byKey(const Key('delete-crop-cycle-button')), findsOneWidget);
  });

  testWidgets('delete validation rejection is safe and remains actionable', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.method == 'DELETE'
          ? http.Response('{"detail":"private"}', 422)
          : _jsonResponse(_crop(16)),
    );
    await _pumpDetails(tester, fixture, cropCycleId: 16);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);
    expect(
      find.text('Please review the crop cycle information and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private'), findsNothing);
    expect(find.byKey(const Key('delete-crop-cycle-button')), findsOneWidget);
  });

  testWidgets('delete 404 transitions to safe unavailable recovery', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.method == 'DELETE'
          ? http.Response('{}', 404)
          : _jsonResponse(_crop(17)),
    );
    await _pumpDetails(tester, fixture, cropCycleId: 17);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);
    expect(find.text('This crop cycle is unavailable.'), findsOneWidget);
    expect(
      find.byKey(const Key('return-to-crop-cycles-button')),
      findsOneWidget,
    );
  });

  for (final scenario in ['server', 'network', 'timeout', 'unexpected']) {
    testWidgets('$scenario delete is ambiguous and requires inspection', (
      tester,
    ) async {
      var deletes = 0;
      var gets = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'GET') {
          gets++;
          return _jsonResponse(_crop(18));
        }
        deletes++;
        if (scenario == 'server') return http.Response('private', 500);
        if (scenario == 'network') throw http.ClientException('private');
        if (scenario == 'timeout') return Completer<http.Response>().future;
        return http.Response('{}', 200);
      });
      await _pumpDetails(tester, fixture, cropCycleId: 18);
      await tester.pumpAndSettle();
      await _confirmDelete(tester);
      expect(deletes, 1);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(find.byKey(const Key('delete-crop-cycle-button')), findsNothing);
      await tester.tap(find.byKey(const Key('inspect-after-delete-button')));
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(find.byKey(const Key('delete-crop-cycle-button')), findsOneWidget);
      expect(deletes, 1);
    });
  }

  testWidgets('unexpected post-dispatch DELETE exception requires inspection', (
    tester,
  ) async {
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        deletes++;
        throw StateError('private transport detail');
      }
      return _jsonResponse(_crop(18));
    });
    await _pumpDetails(tester, fixture, cropCycleId: 18);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(deletes, 1);
    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(find.byKey(const Key('delete-crop-cycle-button')), findsNothing);
    expect(
      find.byKey(const Key('inspect-after-delete-button')),
      findsOneWidget,
    );
  });

  testWidgets('pending DELETE rejects conflicting refresh dispatch', (
    tester,
  ) async {
    final deletion = Completer<http.Response>();
    var gets = 0;
    var deletes = 0;
    final fixture = await _fixture((request) async {
      if (request.method == 'DELETE') {
        deletes++;
        return deletion.future;
      }
      gets++;
      return _jsonResponse(
        _crop(18, cropType: gets == 1 ? 'Original' : 'Verified'),
      );
    }, timeout: const Duration(seconds: 5));
    await _pumpDetails(tester, fixture, cropCycleId: 18);
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('delete-crop-cycle-button'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-confirm')));
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('crop-cycle-details-content')),
      const Offset(0, 500),
    );
    await tester.pump();
    expect(gets, 1);
    expect(deletes, 1);
    expect(find.text('Deleting...'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    deletion.complete(http.Response('private', 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('account replacement during DELETE ignores old completion', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture(
      (request) async => request.method == 'DELETE'
          ? pending.future
          : _jsonResponse(_crop(14)),
    );
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('delete-crop-cycle-button'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-crop-cycle-confirm')));
    await tester.pump();
    await fixture.session.establishVerified(
      _tokens('replacement'),
      _profile(8),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
    pending.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('account replacement closes route and ignores pending success', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((_) async => pending.future);
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pump();
    await fixture.session.establishVerified(
      _tokens('replacement'),
      _profile(8),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
    pending.complete(_jsonResponse(_crop(14, cropType: 'Old account')));
    await tester.pumpAndSettle();
    expect(find.text('Old account'), findsNothing);
  });

  testWidgets('logout during pending GET closes route and clears details', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      return pending.future;
    });
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pump();
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
    pending.complete(_jsonResponse(_crop(14, cropType: 'Logged out data')));
    await tester.pumpAndSettle();
    expect(find.text('Logged out data'), findsNothing);
  });

  testWidgets('unauthenticated session cannot keep a details route open', (
    tester,
  ) async {
    var detailGets = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      detailGets++;
      return _jsonResponse(_crop(14));
    });
    await fixture.session.logout(fixture.auth);
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pumpAndSettle();
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
    expect(detailGets, 0);
  });

  testWidgets('terminal unauthorized response closes protected details', (
    tester,
  ) async {
    var refreshes = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/auth/refresh') {
        refreshes++;
        return http.Response('{}', 401);
      }
      return http.Response('{}', 401);
    });
    await _pumpRoute(tester, fixture);
    await tester.tap(find.text('Open Details'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.byType(CropCycleDetailsScreen), findsNothing);
    expect(fixture.session.isVerified, isFalse);
  });

  testWidgets('delayed success and error after disposal are ignored', (
    tester,
  ) async {
    for (final succeeds in [true, false]) {
      final pending = Completer<http.Response>();
      final fixture = await _fixture((_) async => pending.future);
      await _pumpDetails(tester, fixture, cropCycleId: 15);
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      if (succeeds) {
        pending.complete(_jsonResponse(_crop(15)));
      } else {
        pending.complete(http.Response('{}', 500));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  for (final configuration in [
    (const Size(320, 700), 1.0),
    (const Size(1500, 1000), 1.0),
    (const Size(900, 1400), 1.8),
  ]) {
    testWidgets(
      'long multilingual details fit ${configuration.$1} scale ${configuration.$2}',
      (tester) async {
        final fixture = await _fixture(
          (_) async => _jsonResponse(
            _crop(
              20,
              cropType: 'மிக நீளமான காய்கறி பயிர் பெயர்',
              variety: 'විශේෂ දිගු ප්‍රභේදය with English',
              notes: ('தமிழ் සිංහල English notes ' * 30).trim(),
            ),
          ),
        );
        await _pumpDetails(
          tester,
          fixture,
          cropCycleId: 20,
          size: configuration.$1,
          textScale: configuration.$2,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('crop-cycle-details-content')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpDetails(
  WidgetTester tester,
  _Fixture fixture, {
  required int cropCycleId,
  int? knownFarmId,
  String? knownFarmName,
  Size size = const Size(900, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CropCycleDetailsScreen(
        cropCycleService: fixture.crops,
        session: fixture.session,
        cropCycleId: cropCycleId,
        knownFarmId: knownFarmId,
        knownFarmName: knownFarmName,
      ),
    ),
  );
}

Future<void> _pumpRoute(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: _DetailsHost(fixture: fixture)));
}

Future<void> _confirmDelete(WidgetTester tester) async {
  final delete = find.byKey(const Key('delete-crop-cycle-button'));
  await tester.ensureVisible(delete);
  await tester.tap(delete);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('delete-crop-cycle-confirm')));
  await tester.pumpAndSettle();
}

Future<_Fixture> _fixture(
  MockClientHandler handler, {
  Duration timeout = const Duration(milliseconds: 100),
}) async {
  final now = DateTime.utc(2026, 11, 24, 12);
  final client = ApiClient(client: MockClient(handler), timeout: timeout);
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(_tokens('access'), _profile(7));
  return _Fixture(
    auth: auth,
    session: session,
    crops: CropCycleService(
      apiClient: client,
      session: session,
      authService: auth,
    ),
  );
}

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'refresh-$access',
  issuedAt: DateTime.utc(2026, 11, 24, 12),
  expiresIn: const Duration(minutes: 30),
  refreshExpiresIn: const Duration(days: 7),
);

UserProfile _profile(int id) => UserProfile(
  id: id,
  name: 'Farmer $id',
  email: 'farmer$id@example.com',
  preferredLanguage: 'English',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

Map<String, Object?> _crop(
  int id, {
  int farmId = 1,
  String status = 'active',
  String cropType = 'Tomato',
  String? variety,
  String plantingDate = '2026-11-03',
  String? expectedHarvestDate,
  int? plantCount,
  String? notes,
  String createdAt = '2026-11-03T10:00:00Z',
  String updatedAt = '2026-11-03T11:30:00Z',
}) => {
  'id': id,
  'farm_id': farmId,
  'crop_type': cropType,
  'variety': variety,
  'planting_date': plantingDate,
  'expected_harvest_date': expectedHarvestDate,
  'status': status,
  'plant_count': plantCount,
  'notes': notes,
  'created_at': createdAt,
  'updated_at': updatedAt,
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _Fixture {
  const _Fixture({
    required this.auth,
    required this.session,
    required this.crops,
  });

  final AuthService auth;
  final AuthSession session;
  final CropCycleService crops;
}

class _DetailsHost extends StatelessWidget {
  const _DetailsHost({required this.fixture});

  final _Fixture fixture;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CropCycleDetailsScreen(
              cropCycleService: fixture.crops,
              session: fixture.session,
              cropCycleId: 14,
            ),
          ),
        ),
        child: const Text('Open Details'),
      ),
    ),
  );
}
