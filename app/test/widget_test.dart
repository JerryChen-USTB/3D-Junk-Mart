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
      'id': 'listing_demo_3d_camera',
      'category_id': 'camera',
      'title': '3D Camera Demo',
      'subtitle': '3D-ready second-hand camera',
      'price': <String, dynamic>{'amount_minor': 29900, 'currency': 'CNY'},
      'original_price': <String, dynamic>{
        'amount_minor': 49900,
        'currency': 'CNY',
      },
      'status': 'live',
      'cover_media': <String, dynamic>{
        'url': '/storage/seed/listings/3dgs_cover.jpg',
      },
      'location': 'Shanghai',
      'condition_level': 'excellent',
      'condition_label': '几乎全新',
      'shipping_fee': <String, dynamic>{'amount_minor': 0, 'currency': 'CNY'},
      'shipping_promise': '24小时内发货',
      'is_negotiable': true,
      'is_favorited': false,
      'favorite_count': 12,
      'has_3d_preview': true,
      'badges': <String>['3d-ready'],
      'seller_trust': <String, dynamic>{
        'sold_count': 5,
        'followers_count': 8,
        'sesame_credit_score': 712,
        'vip_level': 'gold',
      },
      'seller': <String, dynamic>{
        'id': 'user_demo_seller',
        'display_name': 'Demo Seller',
      },
      'viewer_url': '/viewer/index.html?task_id=demo',
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
          'follower_count': 4,
          'following_count': 7,
          'positive_rate': 98,
        },
        'session': <String, dynamic>{
          'id': 'session_demo_buyer',
          'user_id': 'user_demo_buyer',
          'access_token': 'demo-access-token',
          'refresh_token': 'demo-refresh-token',
          'device_name': 'Demo Device',
          'device_platform': 'android',
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

    if (path == '/users/me') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: _sessionEnvelope().data['profile'] as Map<String, dynamic>,
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/pages/home') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{
          'page_key': 'home',
          'resources': <String, dynamic>{
            'listings': _listings,
            'featured_3d': _listings,
            'banners': const <Map<String, dynamic>>[
              <String, dynamic>{
                'title': '3D 闲置好物',
                'subtitle': '用 3D 预览提升交易决策效率',
              },
            ],
            'categories': const <Map<String, dynamic>>[
              <String, dynamic>{'id': 'camera', 'name': '摄影器材'},
              <String, dynamic>{'id': 'phone', 'name': '手机数码'},
            ],
            'services': const <Map<String, dynamic>>[
              <String, dynamic>{'title': '猜你喜欢', 'subtitle': '推荐流'},
              <String, dynamic>{'title': '3D 专区', 'subtitle': '沉浸式逛商品'},
            ],
          },
        },
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/search/suggestions') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: const <String, dynamic>{
          'query': '',
          'suggestions': <String>['相机', '镜头', '3D 商品'],
          'recent_queries': <String>['相机'],
        },
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/search/facets') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: const <String, dynamic>{
          'price_buckets': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'lt_1000', 'label': '1000 元以下'},
          ],
          'condition_levels': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'excellent', 'label': '几乎全新'},
          ],
          'sort_options': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'latest', 'label': '最新上新'},
            <String, dynamic>{'id': 'popular', 'label': '人气优先'},
          ],
        },
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

    if (path == '/users/me/listings') {
      return ApiEnvelope<Object?>(
        code: 0,
        message: 'ok',
        data: _listings,
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/conversations') {
      return ApiEnvelope<Object?>(
        code: 0,
        message: 'ok',
        data: const <Map<String, dynamic>>[],
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/membership/plans') {
      return ApiEnvelope<Object?>(
        code: 0,
        message: 'ok',
        data: const <Map<String, dynamic>>[],
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
        data: const <String, dynamic>{},
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
  testWidgets('登录后可以进入我的页面并打开个人设置', (WidgetTester tester) async {
    final apiClient = FakeApiClient();
    final sessionStore = InMemorySessionStore();

    await tester.pumpWidget(
      JunkMartApp(apiClient: apiClient, sessionStore: sessionStore),
    );
    await tester.pumpAndSettle();

    expect(find.text('Junk Mart'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.drag(
      find.byKey(const PageStorageKey<String>('auth-login-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_rounded).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey<String>('profile-list')),
      findsOneWidget,
    );
    expect(find.text('我的'), findsWidgets);
    expect(find.text('我的商品'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('个人设置'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('年龄'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey<String>('profile-settings-list')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();

    expect(find.text('资料可见范围'), findsOneWidget);
  });
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('Unexpected network call in widget test.');
  }
}
