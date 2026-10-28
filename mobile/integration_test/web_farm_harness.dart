import 'package:agrocrew/core/network/api_client.dart';
import 'package:agrocrew/features/auth/data/auth_service.dart';
import 'package:agrocrew/features/auth/data/auth_session.dart';
import 'package:agrocrew/features/auth/data/auth_token_store.dart';
import 'package:agrocrew/features/farms/data/farm_service.dart';
import 'package:agrocrew/features/farms/data/models/farm.dart';
import 'package:flutter/material.dart';

const _emailA = String.fromEnvironment('INTEGRATION_EMAIL_A');
const _emailB = String.fromEnvironment('INTEGRATION_EMAIL_B');
const _password = 'DisposableStep24WebPassword123!';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _VerificationApp());
}

class _VerificationApp extends StatefulWidget {
  const _VerificationApp();

  @override
  State<_VerificationApp> createState() => _VerificationAppState();
}

class _VerificationAppState extends State<_VerificationApp> {
  String _result = 'STEP24_WEB_FARMS_RUNNING';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    var stage = 'start';
    final apiClient = ApiClient();
    final authService = AuthService(apiClient);
    try {
      if (_emailA.isEmpty || _emailB.isEmpty) {
        throw StateError('Missing integration emails.');
      }
      stage = 'register';
      final userA = await authService.register(
        name: 'Step 24 Chrome Farmer A',
        email: _emailA,
        password: _password,
      );
      final userB = await authService.register(
        name: 'Step 24 Chrome Farmer B',
        email: _emailB,
        password: _password,
      );

      stage = 'farmer-a';
      final a = await _fixture(apiClient, authService, _emailA);
      if ((await a.listFarms()).farms.isNotEmpty) {
        throw StateError('Farmer A did not start empty.');
      }
      final created = await a.createFarm(
        const FarmCreate(
          name: 'Green Valley Farm',
          latitude: 6.927079,
          longitude: 79.861244,
          areaValue: 2.5,
          areaUnit: 'acres',
          notes: 'Created by compiled Chrome integration',
        ),
      );
      if (created.userId != userA.id ||
          (await a.getFarm(created.id)).id != created.id) {
        throw StateError('Farmer A ownership failed.');
      }
      final updated = await a.updateFarm(
        created.id,
        const FarmUpdate(
          name: 'Green Valley Organic Farm',
          latitude: null,
          longitude: null,
          areaValue: 3.5,
          areaUnit: 'acres',
          notes: 'Updated by compiled Chrome integration',
        ),
      );
      if (updated.name != 'Green Valley Organic Farm' ||
          updated.latitude != null ||
          updated.longitude != null ||
          updated.createdAt != created.createdAt) {
        throw StateError('Full replacement failed.');
      }

      stage = 'farmer-b';
      final b = await _fixture(apiClient, authService, _emailB);
      final hill = await b.createFarm(const FarmCreate(name: 'Hill Farm'));
      final bFarms = (await b.listFarms()).farms;
      if (hill.userId != userB.id ||
          bFarms.length != 1 ||
          bFarms.single.id != hill.id) {
        throw StateError('Farmer B isolation failed.');
      }
      try {
        await b.getFarm(created.id);
        throw StateError('Cross-owner farm was visible.');
      } on FarmException catch (error) {
        if (error.type != FarmFailureType.notFound) rethrow;
      }

      stage = 'delete';
      await a.deleteFarm(created.id);
      if ((await a.listFarms()).farms.isNotEmpty ||
          (await b.listFarms()).farms.single.id != hill.id) {
        throw StateError('Deletion isolation failed.');
      }

      stage = 'web-storage';
      final reloaded = AuthSession(tokenStore: createAuthTokenStore());
      await reloaded.restore(authService);
      if (reloaded.state != AuthSessionState.unauthenticated) {
        throw StateError('Web session persisted unexpectedly.');
      }

      if (mounted) setState(() => _result = 'STEP24_WEB_FARMS_PASS');
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _result = 'STEP24_WEB_FARMS_FAIL_${stage}_${error.runtimeType}',
        );
      }
    } finally {
      authService.close();
    }
  }

  Future<FarmService> _fixture(
    ApiClient apiClient,
    AuthService authService,
    String email,
  ) async {
    final tokens = await authService.login(email: email, password: _password);
    final profile = await authService.getCurrentUser(tokens.accessToken);
    final session = AuthSession(tokenStore: MemoryAuthTokenStore());
    await session.establishVerified(tokens, profile);
    return FarmService(
      apiClient: apiClient,
      session: session,
      authService: authService,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: _result,
    home: Title(
      title: _result,
      color: Colors.white,
      child: Scaffold(body: Center(child: Text(_result))),
    ),
  );
}
