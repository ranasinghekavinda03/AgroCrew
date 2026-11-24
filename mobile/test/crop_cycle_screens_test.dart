import 'dart:async';
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

void main() {
  testWidgets(
    'loads crops and farm metadata concurrently with exact defaults',
    (tester) async {
      final crops = Completer<http.Response>();
      var cropCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms') {
          return http.Response(jsonEncode([_farm(1, 'North Farm')]), 200);
        }
        cropCalls++;
        expect(request.url.queryParameters, {'limit': '20', 'offset': '0'});
        return crops.future;
      });
      await _pumpCrops(tester, fixture);
      expect(find.byKey(const Key('crop-cycles-loading')), findsOneWidget);
      expect(find.byKey(const Key('farm-metadata-loading')), findsOneWidget);
      crops.complete(http.Response(jsonEncode([_crop(1)]), 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
      expect(find.text('North Farm'), findsOneWidget);
      expect(cropCalls, 1);
    },
  );

  testWidgets('renders statuses and only present optional crop fields', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return _jsonResponse([_farm(1, 'மலை பண்ணை')]);
      }
      return _jsonResponse([
        _crop(1, status: 'planned', cropType: 'Tomato', variety: 'Roma'),
        _crop(2, status: 'active', cropType: 'கத்தரிக்காய்'),
        _crop(3, status: 'harvested', cropType: 'Rice', plantCount: 250),
        _crop(4, status: 'cancelled', cropType: 'Beans'),
      ]);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    for (final entry in {
      1: 'Planned',
      2: 'Active',
      3: 'Harvested',
      4: 'Cancelled',
    }.entries) {
      await tester.scrollUntilVisible(
        find.byKey(Key('crop-cycle-card-${entry.key}')),
        350,
        scrollable: _cropScrollable(),
      );
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 1) expect(find.text('Roma'), findsOneWidget);
      if (entry.key == 3) expect(find.text('Plant count: 250'), findsOneWidget);
    }
    expect(find.text('Planting: 2026-11-03'), findsWidgets);
    expect(find.text('Expected harvest: 2027-01-10'), findsWidgets);
    expect(find.textContaining('notes'), findsNothing);
  });

  testWidgets('shows empty, initial error, and successful retry states', (
    tester,
  ) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropCalls++;
      return cropCalls == 1
          ? http.Response('{"detail":"private"}', 500)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-error')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-empty')), findsOneWidget);
    expect(find.text('No crop cycles yet.'), findsOneWidget);
  });

  testWidgets('farm metadata failure does not hide crop cycles', (
    tester,
  ) async {
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        expect(request.url.queryParameters['offset'], '0');
        return farmCalls == 1
            ? http.Response('{}', 500)
            : http.Response(jsonEncode([_farm(77, 'Recovered Farm')]), 200);
      }
      return http.Response(jsonEncode([_crop(7, farmId: 77)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farm-metadata-error')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-7')), findsOneWidget);
    expect(find.text('Farm #77'), findsOneWidget);
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(farmCalls, 2);
    expect(find.text('Recovered Farm'), findsOneWidget);
  });

  testWidgets('farm selection sends farm_id and replaces the list', (
    tester,
  ) async {
    final seen = <Map<String, String>>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(2, 'South Farm')]), 200);
      }
      seen.add(request.url.queryParameters);
      return http.Response(
        jsonEncode([
          _crop(
            request.url.queryParameters['farm_id'] == '2' ? 2 : 1,
            farmId: 2,
          ),
        ]),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'South Farm (Farm #2)');
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    expect(seen.last, {'limit': '20', 'offset': '0', 'farm_id': '2'});
  });

  testWidgets('late result from an older farm filter is ignored', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode([_farm(1, 'One'), _farm(2, 'Two')]),
          200,
        );
      }
      final farmId = request.url.queryParameters['farm_id'];
      if (farmId == '1') return first.future;
      if (farmId == '2') return second.future;
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)', settle: false);
    await _selectFarm(tester, 'Two (Farm #2)', settle: false);
    second.complete(http.Response(jsonEncode([_crop(22, farmId: 2)]), 200));
    await tester.pump();
    first.complete(http.Response(jsonEncode([_crop(11, farmId: 1)]), 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-22')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-11')), findsNothing);
  });

  testWidgets('farm and crop pagination use independent offsets', (
    tester,
  ) async {
    final queries = <String>[];
    final fixture = await _fixture((request) async {
      queries.add('${request.url.path}?${request.url.query}');
      final offset = request.url.queryParameters['offset'];
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode(
            offset == '0'
                ? List.generate(20, (i) => _farm(i + 1, 'Farm ${i + 1}'))
                : [_farm(21, 'Farm 21')],
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode(
          offset == '0' ? List.generate(20, (i) => _crop(i + 1)) : [_crop(21)],
        ),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-load-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(queries, contains('/api/v1/farms?limit=20&offset=20'));
    expect(queries, contains('/api/v1/crops?limit=20&offset=20'));
  });

  testWidgets('load-more failure retains records and retry appends once', (
    tester,
  ) async {
    var laterCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      laterCalls++;
      return laterCalls == 1
          ? http.Response('{}', 500)
          : http.Response(jsonEncode([_crop(21), _crop(20)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    expect(
      find.byKey(const Key('crop-cycles-load-more-error')),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
  });

  testWidgets('refresh replaces records and refresh failure retains old data', (
    tester,
  ) async {
    var calls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      calls++;
      if (calls == 1) return http.Response(jsonEncode([_crop(1)]), 200);
      if (calls == 2) return http.Response(jsonEncode([_crop(2)]), 200);
      return http.Response('{}', 500);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-refresh-error')), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads offset zero', (tester) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropCalls++;
      expect(request.url.queryParameters['offset'], '0');
      return http.Response(jsonEncode([_crop(cropCalls)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('crop-cycles-list')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(cropCalls, 2);
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
  });

  testWidgets('stale load-more result cannot overwrite a refresh', (
    tester,
  ) async {
    final oldPage = Completer<http.Response>();
    var firstPages = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '20') return oldPage.future;
      firstPages++;
      return http.Response(
        jsonEncode(
          firstPages == 1
              ? List.generate(20, (i) => _crop(i + 1))
              : [_crop(50)],
        ),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('crop-cycles-load-more')),
      500,
      scrollable: _cropScrollable(),
    );
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    oldPage.complete(http.Response(jsonEncode([_crop(21)]), 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-50')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsNothing);
  });

  testWidgets('selected farm 404 offers a safe return to All Farms', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(4, 'Removed Farm')]), 200);
      }
      return request.url.queryParameters['farm_id'] == '4'
          ? http.Response('{}', 404)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Removed Farm (Farm #4)');
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    await tester.tap(find.text('All Farms').last);
    await tester.pumpAndSettle();
    expect(find.text('No crop cycles yet.'), findsOneWidget);
  });

  testWidgets('disposing with pending responses does not update state', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await _fixture((_) => pending.future);
    await _pumpCrops(tester, fixture);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session replacement clears protected data and closes the route',
    (tester) async {
      final fixture = await _fixture(
        (request) async => request.url.path == '/api/v1/farms'
            ? http.Response('[]', 200)
            : http.Response(jsonEncode([_crop(1)]), 200),
      );
      await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
      await fixture.session.establishVerified(
        _tokens('replacement'),
        _profile(8),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
    },
  );

  testWidgets('profile provides crop navigation and keeps My Farms entry', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      return http.Response('[]', 200);
    });
    await _pump(
      tester,
      AuthenticatedProfileScreen(
        authService: fixture.auth,
        session: fixture.session,
        featureApiClient: fixture.client,
      ),
    );
    expect(find.byKey(const Key('my-farms-button')), findsOneWidget);
    expect(find.byKey(const Key('my-crop-cycles-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-crop-cycles-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Crop Cycles'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-empty')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-farms-button')));
    await tester.pumpAndSettle();
    expect(find.text('My Farms'), findsOneWidget);
  });

  testWidgets('unauthenticated profile does not expose protected entries', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 19, 12);
    final client = ApiClient(
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    final session = AuthSession(
      tokenStore: MemoryAuthTokenStore(),
      clock: () => now,
    );
    await _pump(
      tester,
      AuthenticatedProfileScreen(
        authService: AuthService(client, clock: () => now),
        session: session,
        featureApiClient: client,
      ),
    );
    expect(find.byKey(const Key('my-crop-cycles-button')), findsNothing);
    expect(find.byKey(const Key('my-farms-button')), findsNothing);
  });

  testWidgets('pending refresh blocks pagination then uses refreshed offset', (
    tester,
  ) async {
    final refresh = Completer<http.Response>();
    final cropQueries = <Map<String, String>>[];
    var firstPages = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      cropQueries.add(request.url.queryParameters);
      if (request.url.queryParameters['offset'] == '20') {
        return http.Response(jsonEncode([_crop(121)]), 200);
      }
      firstPages++;
      if (firstPages == 2) return refresh.future;
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1))),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('crop-cycles-load-more')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    expect(cropQueries.length, 2);
    refresh.complete(
      http.Response(jsonEncode(List.generate(20, (i) => _crop(i + 101))), 200),
    );
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(cropQueries.last['offset'], '20');
    expect(find.byKey(const Key('crop-cycle-card-121')), findsOneWidget);
  });

  testWidgets('failed refresh preserves records and pagination recovery', (
    tester,
  ) async {
    final refresh = Completer<http.Response>();
    var calls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      if (calls == 2) return refresh.future;
      expect(request.url.queryParameters['offset'], '20');
      return http.Response(jsonEncode([_crop(21)]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    expect(calls, 2);
    refresh.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-20')), findsOneWidget);
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
  });

  testWidgets('farm refresh retry requests offset zero and replaces metadata', (
    tester,
  ) async {
    final offsets = <String?>[];
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      offsets.add(request.url.queryParameters['offset']);
      farmCalls++;
      if (farmCalls == 1) {
        return http.Response(jsonEncode([_farm(1, 'Old Farm')]), 200);
      }
      if (farmCalls == 2) return http.Response('{}', 500);
      return http.Response(jsonEncode([_farm(2, 'New Farm')]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets, ['0', '0', '0']);
    await tester.tap(find.byKey(const Key('crop-cycles-farm-filter')));
    await tester.pumpAndSettle();
    expect(find.text('New Farm (Farm #2)'), findsOneWidget);
    expect(find.text('Old Farm (Farm #1)'), findsNothing);
  });

  testWidgets('failed farm pagination retries the same offset', (tester) async {
    final offsets = <String?>[];
    var moreCalls = 0;
    final pending = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/crops') return http.Response('[]', 200);
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      if (offset == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _farm(i + 1, 'Farm ${i + 1}'))),
          200,
        );
      }
      moreCalls++;
      if (moreCalls == 1) return pending.future;
      if (moreCalls == 2) return http.Response('{}', 500);
      return http.Response(jsonEncode([_farm(21, 'Farm 21')]), 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-load-more')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('farm-metadata-refresh')))
          .onPressed,
      isNull,
    );
    pending.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets.where((offset) => offset == '20').length, 2);
    await tester.tap(find.byKey(const Key('farm-metadata-retry')));
    await tester.pumpAndSettle();
    expect(offsets.where((offset) => offset == '20').length, 3);
  });

  testWidgets('selected farm refresh 404 clears records and syncs All Farms', (
    tester,
  ) async {
    var filteredCalls = 0;
    final queries = <Map<String, String>>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(4, 'Farm Four')]), 200);
      }
      queries.add(request.url.queryParameters);
      if (request.url.queryParameters['farm_id'] == '4') {
        filteredCalls++;
        return filteredCalls == 1
            ? http.Response(jsonEncode([_crop(4, farmId: 4)]), 200)
            : http.Response('{}', 404);
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Farm Four (Farm #4)');
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycle-card-4')), findsNothing);
    expect(_filterValue(tester), 4);
    await tester.tap(find.text('All Farms').last);
    await tester.pumpAndSettle();
    expect(_filterValue(tester), -1);
    expect(queries.last.containsKey('farm_id'), isFalse);
  });

  testWidgets('selected farm load-more 404 invalidates cached pagination', (
    tester,
  ) async {
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(3, 'Farm Three')]), 200);
      }
      if (request.url.queryParameters['farm_id'] == '3' &&
          request.url.queryParameters['offset'] == '20') {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1, farmId: 3))),
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Farm Three (Farm #3)');
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('This farm is unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-load-more')), findsNothing);
    expect(_filterValue(tester), 3);
  });

  testWidgets(
    'full page empty final page and repeated taps stay single-flight',
    (tester) async {
      final finalPage = Completer<http.Response>();
      var moreCalls = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms') {
          return http.Response('[]', 200);
        }
        if (request.url.queryParameters['offset'] == '20') {
          moreCalls++;
          return finalPage.future;
        }
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      });
      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await _scrollToLoadMore(tester);
      await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
      await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
      expect(moreCalls, 1);
      finalPage.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crop-cycles-load-more')), findsNothing);
    },
  );

  testWidgets('deduplication advances with the server page offset', (
    tester,
  ) async {
    final offsets = <String?>[];
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      if (offset == '0') {
        return http.Response(
          jsonEncode(List.generate(20, (i) => _crop(i + 1))),
          200,
        );
      }
      if (offset == '20') {
        return http.Response(
          jsonEncode([_crop(20), ...List.generate(19, (i) => _crop(i + 21))]),
          200,
        );
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pumpAndSettle();
    expect(offsets, ['0', '20', '40']);
  });

  testWidgets('delayed error from superseded farm filter is ignored', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(
          jsonEncode([_farm(1, 'One'), _farm(2, 'Two')]),
          200,
        );
      }
      if (request.url.queryParameters['farm_id'] == '1') return old.future;
      if (request.url.queryParameters['farm_id'] == '2') {
        return http.Response(jsonEncode([_crop(2, farmId: 2)]), 200);
      }
      return http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'One (Farm #1)', settle: false);
    await _selectFarm(tester, 'Two (Farm #2)');
    old.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycle-card-2')), findsOneWidget);
    expect(find.byKey(const Key('crop-cycles-error')), findsNothing);
  });

  testWidgets('filtered empty state and refresh preserve the farm filter', (
    tester,
  ) async {
    final queries = <Map<String, String>>[];
    var filteredCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return http.Response(jsonEncode([_farm(5, 'Filter Farm')]), 200);
      }
      queries.add(request.url.queryParameters);
      if (request.url.queryParameters['farm_id'] == '5') filteredCalls++;
      return http.Response(
        filteredCalls > 1 ? jsonEncode([_crop(5, farmId: 5)]) : '[]',
        200,
      );
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Filter Farm (Farm #5)');
    expect(find.text('No crop cycles found for this farm.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crop-cycles-refresh')));
    await tester.pumpAndSettle();
    expect(queries.last['farm_id'], '5');
    expect(find.byKey(const Key('crop-cycle-card-5')), findsOneWidget);
  });

  testWidgets('missing selected farm metadata remains a valid selection', (
    tester,
  ) async {
    var farmCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        return http.Response(
          farmCalls == 1 ? jsonEncode([_farm(6, 'Known Farm')]) : '[]',
          200,
        );
      }
      return request.url.queryParameters['farm_id'] == '6'
          ? http.Response(jsonEncode([_crop(6, farmId: 6)]), 200)
          : http.Response('[]', 200);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await _selectFarm(tester, 'Known Farm (Farm #6)');
    await tester.tap(find.byKey(const Key('farm-metadata-refresh')));
    await tester.pumpAndSettle();
    expect(_filterValue(tester), 6);
    expect(find.text('Farm #6'), findsWidgets);
    expect(find.text('This farm is unavailable.'), findsNothing);
  });

  testWidgets('account replacement rejects pending crop and farm responses', (
    tester,
  ) async {
    final crops = Completer<http.Response>();
    final farms = Completer<http.Response>();
    final headers = <String?>[];
    var cropCalls = 0;
    var farmCalls = 0;
    final fixture = await _fixture((request) {
      headers.add(request.headers['authorization']);
      if (request.url.path == '/api/v1/farms') {
        farmCalls++;
        return farms.future;
      }
      cropCalls++;
      return crops.future;
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await fixture.session.establishVerified(
      _tokens('replacement'),
      _profile(88),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    crops.complete(http.Response(jsonEncode([_crop(1)]), 200));
    farms.complete(http.Response(jsonEncode([_farm(1, 'Old Farm')]), 200));
    await tester.pumpAndSettle();
    expect(cropCalls, 1);
    expect(farmCalls, 1);
    expect(headers, everyElement('Bearer access'));
    expect(find.byKey(const Key('crop-cycle-card-1')), findsNothing);
  });

  testWidgets('logout rejects pending initial crop and farm failures', (
    tester,
  ) async {
    final crops = Completer<http.Response>();
    final farms = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/auth/logout') {
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/farms') return farms.future;
      return crops.future;
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    crops.complete(http.Response('{}', 500));
    farms.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-error')), findsNothing);
    expect(find.byKey(const Key('farm-metadata-error')), findsNothing);
  });

  testWidgets('logout invalidates pending crop pagination and old route', (
    tester,
  ) async {
    final more = Completer<http.Response>();
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/auth/logout') {
        return http.Response('', 204);
      }
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.queryParameters['offset'] == '20') return more.future;
      return http.Response(
        jsonEncode(List.generate(20, (i) => _crop(i + 1))),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _scrollToLoadMore(tester);
    await tester.tap(find.byKey(const Key('crop-cycles-load-more')));
    await tester.pump();
    await fixture.session.logout(fixture.auth);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    more.complete(http.Response('{}', 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-cycles-load-more-error')), findsNothing);
  });

  testWidgets('terminal unauthorized response closes the protected route', (
    tester,
  ) async {
    var cropCalls = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') return http.Response('[]', 200);
      if (request.url.path == '/api/v1/auth/refresh') {
        return _jsonResponse({
          'access_token': 'refreshed',
          'refresh_token': 'refresh-refreshed',
          'token_type': 'bearer',
          'expires_in': 1800,
          'refresh_expires_in': 604800,
        });
      }
      cropCalls++;
      return http.Response('{}', 401);
    });
    await tester.pumpWidget(MaterialApp(home: _RouteHost(fixture: fixture)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(cropCalls, 2);
    expect(find.text('Open'), findsOneWidget);
    expect(fixture.session.profile?.id, 7);
  });

  testWidgets('wide and scaled layouts retain accessible controls', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = await _fixture(
      (request) async => request.url.path == '/api/v1/farms'
          ? _jsonResponse([_farm(1, 'Wide multilingual farm')])
          : _jsonResponse([
              _crop(
                1,
                cropType: 'Long English crop name · සිංහල බෝගය · தமிழ் பயிர்',
                variety: 'Accessible multilingual variety',
              ),
            ]),
    );
    await _pumpCrops(tester, fixture, size: const Size(1600, 1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byTooltip('Refresh crop cycles'), findsOneWidget);
    expect(find.byTooltip('Refresh farms'), findsOneWidget);
    expect(find.textContaining('සිංහල'), findsOneWidget);
    expect(find.textContaining('தமிழ்'), findsOneWidget);
  });

  testWidgets('narrow layout and long multilingual values do not overflow', (
    tester,
  ) async {
    final fixture = await _fixture(
      (request) async => request.url.path == '/api/v1/farms'
          ? _jsonResponse([_farm(1, 'மிக நீளமான பண்ணை பெயர்')])
          : _jsonResponse([
              _crop(
                1,
                cropType: 'மிக நீளமான காய்கறி பயிர் பெயர்',
                variety: 'විශේෂ දිගු ප්‍රභේදය',
              ),
            ]),
    );
    await _pumpCrops(tester, fixture, size: const Size(320, 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('crop-cycle-card-1')), findsOneWidget);
  });

  testWidgets(
    'Add Crop Cycle entry opens with filter and cancel does not POST',
    (tester) async {
      var posts = 0;
      final fixture = await _fixture((request) async {
        if (request.method == 'POST') posts++;
        if (request.url.path == '/api/v1/farms/2') {
          return _jsonResponse(_farm(2, 'South Farm'));
        }
        if (request.url.path == '/api/v1/farms') {
          return _jsonResponse([_farm(2, 'South Farm')]);
        }
        return _jsonResponse([]);
      });
      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await _selectFarm(tester, 'South Farm (Farm #2)');
      expect(find.byKey(const Key('add-crop-cycle-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
      await tester.pumpAndSettle();
      expect(find.text('Add Crop Cycle'), findsWidgets);
      final farmField = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const Key('crop-farm-field')),
      );
      expect(farmField.initialValue, 2);
      await tester.tap(find.byKey(const Key('cancel-crop-cycle-button')));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(find.text('My Crop Cycles'), findsOneWidget);
    },
  );

  testWidgets(
    'crop card opens authoritative details and Back preserves filter and list',
    (tester) async {
      var detailGets = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms') {
          return _jsonResponse([_farm(2, 'South Farm')]);
        }
        if (request.url.path == '/api/v1/crops/21') {
          detailGets++;
          expect(request.method, 'GET');
          expect(request.headers['authorization'], 'Bearer access');
          return _jsonResponse(
            _crop(21, farmId: 2, status: 'planned', cropType: 'Authoritative'),
          );
        }
        return _jsonResponse([
          _crop(21, farmId: 2, status: 'active', cropType: 'Cached'),
        ]);
      });
      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await _selectFarm(tester, 'South Farm (Farm #2)');
      await tester.tap(find.byKey(const Key('open-crop-cycle-21')));
      await tester.pumpAndSettle();

      expect(detailGets, 1);
      expect(find.text('Crop Cycle Details'), findsOneWidget);
      expect(find.text('Authoritative'), findsOneWidget);
      expect(find.text('South Farm (Farm #2)'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_filterValue(tester), 2);
      expect(find.byKey(const Key('crop-cycle-card-21')), findsOneWidget);
      expect(find.text('Cached'), findsOneWidget);
    },
  );

  testWidgets('unavailable details return refreshes the filtered parent list', (
    tester,
  ) async {
    var listGets = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return _jsonResponse([_farm(3, 'West Farm')]);
      }
      if (request.url.path == '/api/v1/crops/31') {
        return http.Response('{"detail":"private"}', 404);
      }
      listGets++;
      return _jsonResponse(listGets == 1 ? [_crop(31, farmId: 3)] : []);
    });
    await _pumpCrops(tester, fixture);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-crop-cycle-31')));
    await tester.pumpAndSettle();
    expect(find.text('This crop cycle is unavailable.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('return-to-crop-cycles-button')));
    await tester.pumpAndSettle();
    expect(listGets, 2);
    expect(find.byKey(const Key('crop-cycle-card-31')), findsNothing);
    expect(find.text('No crop cycles yet.'), findsOneWidget);
  });

  testWidgets(
    'confirmed create refreshes offset zero with active farm filter',
    (tester) async {
      var filteredGets = 0;
      var posts = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms/2') {
          return _jsonResponse(_farm(2, 'South Farm'));
        }
        if (request.url.path == '/api/v1/farms') {
          return _jsonResponse([_farm(2, 'South Farm')]);
        }
        if (request.method == 'POST') {
          posts++;
          return _jsonResponse(
            _crop(9, farmId: 2, status: 'planned'),
            status: 201,
          );
        }
        if (request.url.queryParameters['farm_id'] == '2') filteredGets++;
        expect(request.url.queryParameters['offset'], '0');
        return _jsonResponse(
          filteredGets >= 2 ? [_crop(9, farmId: 2, status: 'planned')] : [],
        );
      });
      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await _selectFarm(tester, 'South Farm (Farm #2)');
      await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crop-type-field')),
        'Tomato',
      );
      await tester.enterText(
        find.byKey(const Key('planting-date-field')),
        '2026-11-20',
      );
      final create = find.byKey(const Key('create-crop-cycle-button'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(filteredGets, 2);
      expect(find.byKey(const Key('crop-cycle-card-9')), findsOneWidget);
      expect(find.text('Crop cycle created successfully.'), findsOneWidget);
    },
  );

  testWidgets('create waits for a pending first page before refreshing', (
    tester,
  ) async {
    final pendingFirstPage = Completer<http.Response>();
    var cropGets = 0;
    final fixture = await _fixture((request) async {
      if (request.url.path == '/api/v1/farms') {
        return _jsonResponse([_farm(1, 'One')]);
      }
      if (request.url.path == '/api/v1/farms/1') {
        return _jsonResponse(_farm(1, 'One'));
      }
      if (request.method == 'POST') {
        return _jsonResponse(
          _crop(10, farmId: 1, status: 'planned'),
          status: 201,
        );
      }
      cropGets++;
      if (cropGets == 1) return pendingFirstPage.future;
      return _jsonResponse([_crop(10, farmId: 1, status: 'planned')]);
    });
    await _pumpCrops(tester, fixture);
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('crop-farm-field')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('One (Farm #1)').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const Key('crop-type-field')), 'Tomato');
    await tester.enterText(
      find.byKey(const Key('planting-date-field')),
      '2026-11-20',
    );
    final create = find.byKey(const Key('create-crop-cycle-button'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(cropGets, 1);
    pendingFirstPage.complete(_jsonResponse([]));
    await tester.pumpAndSettle();
    expect(cropGets, 2);
    expect(find.byKey(const Key('crop-cycle-card-10')), findsOneWidget);
  });

  testWidgets(
    'no-farm recovery refreshes parent farm names after crop creation',
    (tester) async {
      var farmCreated = false;
      var cropCreated = false;
      var farmPosts = 0;
      var cropPosts = 0;
      final fixture = await _fixture((request) async {
        if (request.url.path == '/api/v1/farms' && request.method == 'POST') {
          farmPosts++;
          farmCreated = true;
          return _jsonResponse(_farm(8, 'Recovery Farm'), status: 201);
        }
        if (request.url.path == '/api/v1/farms') {
          return _jsonResponse(farmCreated ? [_farm(8, 'Recovery Farm')] : []);
        }
        if (request.url.path == '/api/v1/crops' && request.method == 'POST') {
          cropPosts++;
          cropCreated = true;
          return _jsonResponse(
            _crop(18, farmId: 8, status: 'planned'),
            status: 201,
          );
        }
        if (request.url.path == '/api/v1/crops') {
          return _jsonResponse(
            cropCreated ? [_crop(18, farmId: 8, status: 'planned')] : [],
          );
        }
        return http.Response('{}', 404);
      });

      await _pumpCrops(tester, fixture);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-crop-cycle-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to My Farms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-farm-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('farm-name-field')),
        'Recovery Farm',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-farm-button')));
      await tester.pumpAndSettle();
      expect(farmPosts, 1);
      expect(find.byKey(const Key('farm-card-8')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crop-farm-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recovery Farm (Farm #8)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crop-type-field')),
        'Tomato',
      );
      await tester.enterText(
        find.byKey(const Key('planting-date-field')),
        '2026-11-20',
      );
      final create = find.byKey(const Key('create-crop-cycle-button'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(cropPosts, 1);
      expect(find.byKey(const Key('crop-cycle-card-18')), findsOneWidget);
      expect(find.text('Recovery Farm'), findsOneWidget);
      await tester.tap(find.byKey(const Key('crop-cycles-farm-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Recovery Farm (Farm #8)'), findsOneWidget);
    },
  );
}

Finder _cropScrollable() => find.descendant(
  of: find.byKey(const Key('crop-cycles-list')),
  matching: find.byType(Scrollable),
);

Future<void> _scrollToLoadMore(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('crop-cycles-load-more')),
    500,
    scrollable: _cropScrollable(),
  );
  await tester.drag(_cropScrollable(), const Offset(0, -120));
  await tester.pump();
}

int? _filterValue(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )
    .initialValue;

Future<void> _selectFarm(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(const Key('crop-cycles-farm-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpCrops(
  WidgetTester tester,
  _Fixture fixture, {
  Size size = const Size(900, 1400),
}) => _pump(
  tester,
  MyCropCyclesScreen(
    cropCycleService: fixture.crops,
    farmService: fixture.farms,
    session: fixture.session,
  ),
  size: size,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
}

Future<_Fixture> _fixture(MockClientHandler handler) async {
  final now = DateTime.utc(2026, 11, 19, 12);
  final client = ApiClient(
    client: MockClient(handler),
    timeout: const Duration(seconds: 1),
  );
  final auth = AuthService(client, clock: () => now);
  final session = AuthSession(
    tokenStore: MemoryAuthTokenStore(),
    clock: () => now,
  );
  await session.establishVerified(_tokens('access'), _profile(7));
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

LoginResponse _tokens(String access) => LoginResponse(
  accessToken: access,
  refreshToken: 'refresh-$access',
  issuedAt: DateTime.utc(2026, 11, 19, 12),
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
  int farmId = 1,
  String status = 'active',
  String cropType = 'Tomato',
  String? variety,
  int? plantCount,
}) => {
  'id': id,
  'farm_id': farmId,
  'crop_type': cropType,
  'variety': variety,
  'planting_date': '2026-11-03',
  'expected_harvest_date': '2027-01-10',
  'status': status,
  'plant_count': plantCount,
  'notes': 'must not render',
  'created_at': '2026-11-03T10:00:00Z',
  'updated_at': '2026-11-03T11:00:00Z',
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
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
}

class _RouteHost extends StatelessWidget {
  const _RouteHost({required this.fixture});
  final _Fixture fixture;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MyCropCyclesScreen(
              cropCycleService: fixture.crops,
              farmService: fixture.farms,
              session: fixture.session,
            ),
          ),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}
