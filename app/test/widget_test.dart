import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app/app/app.dart';
import 'package:app/core/api/api_client.dart';
import 'package:app/core/session/app_session.dart';
import 'package:app/core/session/session_store.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient()
    : super(httpClient: _NoopHttpClient(), baseUrl: 'http://example.invalid');

  final List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'listing_3dgs_demo',
      'title': '3DGS Demo Listing',
      'subtitle': '3D-ready sample product',
      'price': <String, dynamic>{'amount_minor': 29900, 'currency': 'CNY'},
      'original_price': <String, dynamic>{
        'amount_minor': 49900,
        'currency': 'CNY',
      },
      'status': 'draft',
      'cover_media': <String, dynamic>{
        'url': '/storage/seed/listings/3dgs_cover.jpg',
      },
      'location': 'Remote',
      'badges': <String>['3d-ready'],
      'seller': <String, dynamic>{'display_name': 'Demo Seller'},
    },
  ];

  ApiEnvelope<Map<String, dynamic>> _sessionEnvelope({bool isNewUser = false}) {
    return ApiEnvelope<Map<String, dynamic>>(
      code: 0,
      message: 'ok',
      data: <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'user_demo_buyer',
          'display_name': 'Demo Buyer',
          'avatar_url': '/storage/seed/avatars/buyer.png',
          'bio': 'demo buyer',
          'location': 'Beijing',
          'sesame_credit_score': 712,
          'vip_level': 'gold',
          'follower_count': 0,
          'following_count': 0,
          'positive_rate': 1.0,
        },
        'session': <String, dynamic>{
          'id': 'session_demo_buyer',
          'user_id': 'user_demo_buyer',
          'access_token': 'demo-access-token',
          'refresh_token': 'demo-refresh-token',
          'device_name': 'Demo Device',
          'device_platform': 'web',
          'access_token_expires_at': '2026-04-14T21:52:04.091655+00:00',
          'refresh_token_expires_at': '2026-04-14T21:52:04.091655+00:00',
          'is_new_user': isNewUser,
        },
        'profile': <String, dynamic>{
          'id': 'user_demo_buyer',
          'display_name': 'Demo Buyer',
          'avatar_url': '/storage/seed/avatars/buyer.png',
          'birth_date': '1996-08-12',
          'age_years': 30,
          'bio': 'demo buyer',
          'location': 'Beijing',
          'sesame_credit_score': 712,
          'vip_level': 'gold',
          'profile_visibility': 'public',
          'updated_at': '2026-04-14T21:52:04.091655+00:00',
        },
      },
      meta: const <String, dynamic>{},
    );
  }

  @override
  Future<ApiEnvelope<Map<String, dynamic>>> getJson(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/auth/session') {
      return _sessionEnvelope();
    }

    if (path == '/auth/logout') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{},
        meta: const <String, dynamic>{},
      );
    }

    return super.getJson(
      path,
      bearerToken: bearerToken,
      queryParameters: queryParameters,
    );
  }

  @override
  Future<ApiEnvelope<Object?>> getObject(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/listings') {
      return ApiEnvelope<Object?>(
        code: 0,
        message: 'ok',
        data: _listings,
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/pages/listings/listing_3dgs_demo') {
      return ApiEnvelope<Object?>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{
          'page_key': 'listing_detail',
          'resources': <String, dynamic>{
            'listing': _listings.first,
            'seller': <String, dynamic>{
              'display_name': 'Demo Seller',
              'location': 'Shanghai',
              'bio': 'Trusted demo seller',
              'sesame_credit_score': 756,
            },
            'preview_3d': <String, dynamic>{
              'preview_status': 'ready',
              'is_ready': true,
              'viewer_url':
                  'http://example.invalid/viewer/index.html?model=http://example.invalid/storage/models/demo/model.ply',
              'placeholder': <String, dynamic>{
                'title': '3DGS Demo Listing',
                'subtitle': '3D-ready sample product',
                'badges': <String>['3d-ready'],
              },
            },
            'specs': <Map<String, dynamic>>[
              <String, dynamic>{
                'spec_key': 'Model Status',
                'spec_value': 'Ready',
              },
            ],
            'actions': <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'chat',
                'title': 'Contact seller',
                'enabled': true,
              },
            ],
            'listing_payload': <String, dynamic>{
              'description': 'Demo description for the 3D listing.',
            },
          },
        },
        meta: const <String, dynamic>{},
      );
    }

    return super.getObject(
      path,
      bearerToken: bearerToken,
      queryParameters: queryParameters,
    );
  }

  @override
  Future<ApiEnvelope<Map<String, dynamic>>> postJson(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    if (path == '/auth/login') {
      return _sessionEnvelope();
    }

    if (path == '/auth/register') {
      return _sessionEnvelope(isNewUser: true);
    }

    if (path == '/auth/logout') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{},
        meta: const <String, dynamic>{},
      );
    }

    return super.postJson(path, body: body, bearerToken: bearerToken);
  }
}

class InMemorySessionStore extends SessionStore {
  AppSession? _session;

  @override
  Future<AppSession?> read() async => _session;

  @override
  Future<void> write(AppSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

void main() {
  testWidgets('auth settings and shell flow work', (WidgetTester tester) async {
    final apiClient = FakeApiClient();
    final sessionStore = InMemorySessionStore();

    await tester.pumpWidget(
      JunkMartApp(apiClient: apiClient, sessionStore: sessionStore),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.drag(
      find.byKey(const PageStorageKey<String>('auth-login-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profile settings'), findsOneWidget);
    expect(find.text('NICKNAME'), findsOneWidget);
    expect(find.text('BIRTH DATE'), findsOneWidget);
    expect(find.text('AGE'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey<String>('profile-settings-list')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile visibility'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey<String>('profile-settings-list')),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);
  });
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('Unexpected network call in widget test.');
  }
}
