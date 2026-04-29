import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app/core/api/api_client.dart';
import 'package:app/core/commerce/commerce_repository.dart';
import 'package:app/core/session/app_session.dart';
import 'package:app/features/chat/chat_pages.dart';
import 'package:app/theme/app_theme.dart';

class _ChatTestApiClient extends ApiClient {
  _ChatTestApiClient()
    : super(httpClient: _NoopHttpClient(), baseUrl: 'http://example.invalid');

  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  bool sellerView = false;
  bool hasAcceptedOffer = false;
  String? acceptedOfferOrderId;
  String? relatedOrderId;
  String? relatedOrderStatus;

  @override
  Future<ApiEnvelope<Map<String, dynamic>>> getJson(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/conversations/conversation_demo') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{
          'conversation': <String, dynamic>{
            'id': 'conversation_demo',
            'listing_title': '3D Camera Demo',
            'buyer_id': 'user_demo_buyer',
            'seller_id': 'user_demo_seller',
            'role': sellerView ? 'seller' : 'buyer',
            'other_user': <String, dynamic>{
              'id': sellerView ? 'user_demo_buyer' : 'user_demo_seller',
              'display_name': sellerView ? 'Demo Buyer' : 'Demo Seller',
            },
          },
          'item_preview': const <String, dynamic>{
            'id': 'listing_demo_3d_camera',
            'title': '3D Camera Demo',
            'price': <String, dynamic>{
              'amount_minor': 29900,
              'currency': 'CNY',
            },
            'seller': <String, dynamic>{'id': 'user_demo_seller'},
          },
          'safety_banner': const <String, dynamic>{
            'title': '平台安全提醒',
            'body': '请勿在站外转账，交易与售后尽量保留在平台内完成。',
          },
          'composer': const <String, dynamic>{
            'quick_actions': <String>['发起议价', '查看订单'],
          },
          'messages': List<Map<String, dynamic>>.from(_messages),
          'active_offer': const <String, dynamic>{},
          'accepted_offer': hasAcceptedOffer
              ? <String, dynamic>{
                  'id': 'offer_accepted',
                  'listing_id': 'listing_demo_3d_camera',
                  'proposer_id': 'user_demo_buyer',
                  'counterparty_id': 'user_demo_seller',
                  'status': 'accepted',
                  if (acceptedOfferOrderId != null)
                    'order_id': acceptedOfferOrderId,
                  'amount': const <String, dynamic>{
                    'amount_minor': 18800,
                    'currency': 'CNY',
                  },
                }
              : const <String, dynamic>{},
          'related_order': relatedOrderStatus == null
              ? const <String, dynamic>{}
              : <String, dynamic>{
                  'id': relatedOrderId ?? acceptedOfferOrderId ?? 'order_demo',
                  'offer_id': 'offer_accepted',
                  'status': relatedOrderStatus,
                },
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
  Future<ApiEnvelope<Map<String, dynamic>>> postJson(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    if (path == '/conversations/conversation_demo/read') {
      return const ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{},
        meta: <String, dynamic>{},
      );
    }

    if (path == '/conversations/conversation_demo/messages') {
      final payload =
          (body as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final message = <String, dynamic>{
        'id': 'message_${_messages.length + 1}',
        'sender_id': 'user_demo_buyer',
        'content_text': payload['content_text']?.toString() ?? '',
        'message_type': payload['message_type']?.toString() ?? 'text',
      };
      _messages.add(message);
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: message,
        meta: const <String, dynamic>{},
      );
    }

    if (path == '/conversations/conversation_demo/offers') {
      return const ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: <String, dynamic>{'id': 'offer_1'},
        meta: <String, dynamic>{},
      );
    }

    return super.postJson(path, body: body, bearerToken: bearerToken);
  }
}

void main() {
  testWidgets('聊天详情页保留消息输入并提供议价按钮', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = CommerceRepository(_ChatTestApiClient());
    const session = AppSession(
      user: <String, dynamic>{
        'id': 'user_demo_buyer',
        'display_name': 'Demo Buyer',
      },
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConversationDetailPage(
          repository: repository,
          session: session,
          conversationId: 'conversation_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('平台安全提醒'), findsNothing);
    expect(find.text('查看订单'), findsNothing);
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.text('还没有消息'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('议价'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('发起议价'), findsOneWidget);
    expect(find.text('出价金额（元）'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '还在吗？');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('还在吗？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卖家视角议价成交后不显示去下单', (tester) async {
    final apiClient = _ChatTestApiClient()
      ..sellerView = true
      ..hasAcceptedOffer = true;
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{
        'id': 'user_demo_seller',
        'display_name': 'Demo Seller',
      },
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConversationDetailPage(
          repository: repository,
          session: session,
          conversationId: 'conversation_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('议价已成交'), findsOneWidget);
    expect(find.text('等待买家下单'), findsOneWidget);
    expect(find.text('去下单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('议价成交卡按订单状态展示而不是固定显示已下单', (tester) async {
    final apiClient = _ChatTestApiClient()
      ..hasAcceptedOffer = true
      ..acceptedOfferOrderId = 'order_cancelled'
      ..relatedOrderStatus = 'cancelled';
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{
        'id': 'user_demo_buyer',
        'display_name': 'Demo Buyer',
      },
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConversationDetailPage(
          repository: repository,
          session: session,
          conversationId: 'conversation_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('议价已成交'), findsOneWidget);
    expect(find.text('订单已取消'), findsOneWidget);
    expect(find.text('已下单'), findsNothing);
    expect(find.text('去下单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('议价成交卡不会把其它订单状态误用到当前议价', (tester) async {
    final apiClient = _ChatTestApiClient()
      ..hasAcceptedOffer = true
      ..acceptedOfferOrderId = 'order_old'
      ..relatedOrderId = 'order_new'
      ..relatedOrderStatus = 'awaiting_shipment';
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{
        'id': 'user_demo_buyer',
        'display_name': 'Demo Buyer',
      },
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConversationDetailPage(
          repository: repository,
          session: session,
          conversationId: 'conversation_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已生成订单'), findsOneWidget);
    expect(find.text('待发货'), findsNothing);
    expect(find.text('去下单'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('Unexpected network call in chat widget test.');
  }
}
