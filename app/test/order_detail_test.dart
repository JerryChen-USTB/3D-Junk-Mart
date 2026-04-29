import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app/core/api/api_client.dart';
import 'package:app/core/commerce/commerce_repository.dart';
import 'package:app/core/session/app_session.dart';
import 'package:app/features/commerce/order_pages.dart';
import 'package:app/theme/app_theme.dart';

class _OrderDetailTestApiClient extends ApiClient {
  _OrderDetailTestApiClient()
    : super(httpClient: _NoopHttpClient(), baseUrl: 'http://example.invalid');

  String status = 'awaiting_shipment';
  bool sellerView = false;

  @override
  Future<ApiEnvelope<Map<String, dynamic>>> getJson(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/orders/order_demo') {
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: _detail(),
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
    if (path == '/orders/order_demo/cancel') {
      status = 'cancelled';
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: _detail(),
        meta: const <String, dynamic>{},
      );
    }
    if (path == '/orders/order_demo/refund-request') {
      status = 'refund_requested';
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: _detail(),
        meta: const <String, dynamic>{},
      );
    }
    if (path == '/orders/order_demo/approve-refund') {
      status = 'refunded';
      return ApiEnvelope<Map<String, dynamic>>(
        code: 0,
        message: 'ok',
        data: _detail(),
        meta: const <String, dynamic>{},
      );
    }
    return super.postJson(path, body: body, bearerToken: bearerToken);
  }

  Map<String, dynamic> _detail() {
    final pendingPayment = status == 'pending_payment';
    final shipped = status == 'shipped';
    final refunding = status == 'refund_requested';
    final refunded = status == 'refunded';
    final cancelled = status == 'cancelled';
    final statusLabel = switch (status) {
      'pending_payment' => '待支付',
      'shipped' => '已发货',
      'refund_requested' => '退款处理中',
      'refunded' => '已退款',
      'cancelled' => '已取消',
      _ => '待发货',
    };
    return <String, dynamic>{
      'order': <String, dynamic>{
        'id': 'order_demo',
        'order_no': 'ORD-DEMO',
        'status': status,
        'status_label': statusLabel,
        'payment_status': refunded
            ? 'refunded'
            : (refunding ? 'refunding' : (pendingPayment ? 'pending' : 'paid')),
        'shipping_status': refunded || cancelled
            ? 'cancelled'
            : (pendingPayment
                  ? 'pending'
                  : (shipped ? 'shipped' : 'awaiting_shipment')),
        'aftersale_status': refunded
            ? 'refunded'
            : (refunding ? 'refund_requested' : 'none'),
        'role': 'buyer',
        'buyer': const <String, dynamic>{
          'id': 'buyer_demo',
          'display_name': 'Demo Buyer',
        },
        'seller': const <String, dynamic>{
          'id': 'seller_demo',
          'display_name': 'Demo Seller',
        },
        'item_snapshot': const <String, dynamic>{
          'title': 'Demo 商品',
          'subtitle': '测试商品',
        },
        'totals': const <String, dynamic>{
          'subtotal': <String, dynamic>{
            'amount_minor': 1000,
            'currency': 'CNY',
          },
          'shipping': <String, dynamic>{'amount_minor': 0, 'currency': 'CNY'},
          'discount': <String, dynamic>{'amount_minor': 0, 'currency': 'CNY'},
          'total': <String, dynamic>{'amount_minor': 1000, 'currency': 'CNY'},
        },
        'address': const <String, dynamic>{
          'receiver_name': 'Tom',
          'phone': '13800000000',
          'region': '北京',
          'detail': '朝阳区',
        },
      },
      'receipt': const <String, dynamic>{
        'payment': <String, dynamic>{
          'payment_method': 'mock',
          'status': 'paid',
        },
        'shipment': <String, dynamic>{'id': null},
      },
      'status_card': <String, dynamic>{
        'title': statusLabel,
        'subtitle': refunded
            ? '退款已完成。'
            : (cancelled
                  ? '订单已取消。'
                  : (pendingPayment
                        ? '订单已提交，等待完成模拟支付。'
                        : (shipped
                              ? '卖家已发货，等待买家确认收货。'
                              : (refunding
                                    ? '退款申请已提交，等待卖家处理。'
                                    : '模拟支付已确认，等待卖家发货。')))),
        'tone': refunded ? 'success' : (refunding ? 'warning' : 'neutral'),
      },
      'aftersale': <String, dynamic>{
        'status': refunded
            ? 'refunded'
            : (refunding ? 'refund_requested' : 'none'),
        'reason': refunding || refunded ? '不想要了' : null,
        'resolution_note': refunded ? '卖家同意退款。' : null,
      },
      'timeline': <Map<String, dynamic>>[
        const <String, dynamic>{
          'status': 'pending_payment',
          'event_note': '订单已提交，等待完成模拟支付。',
          'occurred_at': '2026-04-28T01:37:51.067531+00:00',
        },
        if (refunding)
          const <String, dynamic>{
            'status': 'refund_requested',
            'event_note': '不想要了',
            'occurred_at': '2026-04-28T02:06:00.000000+00:00',
          },
        if (refunded) ...[
          const <String, dynamic>{
            'status': 'refund_requested',
            'event_note': '不想要了',
            'occurred_at': '2026-04-28T02:06:00.000000+00:00',
          },
          const <String, dynamic>{
            'status': 'refunded',
            'event_note': '卖家同意退款，款项已退回买家账户。',
            'occurred_at': '2026-04-28T02:07:00.000000+00:00',
          },
        ],
      ],
      'action_bar': refunded || cancelled
          ? const <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'contact_peer',
                'title': '联系对方',
                'enabled': true,
              },
            ]
          : refunding
          ? sellerView
                ? const <Map<String, dynamic>>[
                    <String, dynamic>{
                      'key': 'contact_peer',
                      'title': '联系对方',
                      'enabled': true,
                    },
                    <String, dynamic>{
                      'key': 'approve_refund',
                      'title': '同意退款',
                      'enabled': true,
                      'style': 'primary',
                    },
                    <String, dynamic>{
                      'key': 'reject_refund',
                      'title': '拒绝退款',
                      'enabled': true,
                    },
                  ]
                : const <Map<String, dynamic>>[
                    <String, dynamic>{
                      'key': 'contact_peer',
                      'title': '联系对方',
                      'enabled': true,
                    },
                    <String, dynamic>{
                      'key': 'open_dispute',
                      'title': '发起纠纷',
                      'enabled': true,
                    },
                  ]
          : pendingPayment
          ? const <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'contact_peer',
                'title': '联系对方',
                'enabled': true,
              },
              <String, dynamic>{
                'key': 'mock_pay',
                'title': '立即支付',
                'enabled': true,
                'style': 'primary',
              },
              <String, dynamic>{
                'key': 'cancel_order',
                'title': '取消订单',
                'enabled': true,
              },
            ]
          : shipped
          ? const <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'contact_peer',
                'title': '联系对方',
                'enabled': true,
              },
              <String, dynamic>{
                'key': 'track_shipment',
                'title': '查看物流',
                'enabled': true,
              },
              <String, dynamic>{
                'key': 'request_refund',
                'title': '申请退款',
                'enabled': true,
              },
              <String, dynamic>{
                'key': 'confirm_receipt',
                'title': '确认收货',
                'enabled': true,
                'style': 'primary',
              },
            ]
          : const <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'contact_peer',
                'title': '联系对方',
                'enabled': true,
              },
              <String, dynamic>{
                'key': 'request_refund',
                'title': '申请退款',
                'enabled': true,
              },
            ],
    };
  }
}

void main() {
  testWidgets('订单详情申请退款后刷新为退款处理中且不红屏', (tester) async {
    final repository = CommerceRepository(_OrderDetailTestApiClient());
    const session = AppSession(
      user: <String, dynamic>{'id': 'buyer_demo', 'display_name': 'Demo Buyer'},
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OrderDetailPage(
          repository: repository,
          session: session,
          orderId: 'order_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('申请退款'), findsOneWidget);
    await tester.tap(find.text('申请退款'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '不想要了');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('退款处理中'), findsWidgets);
    expect(find.text('申请退款'), findsNothing);
    expect(find.text('发起纠纷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('订单详情取消未支付订单后刷新为已取消', (tester) async {
    final apiClient = _OrderDetailTestApiClient()..status = 'pending_payment';
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{'id': 'buyer_demo', 'display_name': 'Demo Buyer'},
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OrderDetailPage(
          repository: repository,
          session: session,
          orderId: 'order_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('取消订单'), findsOneWidget);
    await tester.tap(find.text('取消订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('已取消'), findsWidgets);
    expect(find.text('取消订单'), findsNothing);
    expect(find.text('订单已取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已发货订单可以申请退款', (tester) async {
    final apiClient = _OrderDetailTestApiClient()..status = 'shipped';
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{'id': 'buyer_demo', 'display_name': 'Demo Buyer'},
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OrderDetailPage(
          repository: repository,
          session: session,
          orderId: 'order_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已发货'), findsWidgets);
    expect(find.text('确认收货'), findsOneWidget);
    expect(find.text('申请退款'), findsOneWidget);

    await tester.tap(find.text('申请退款'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '收到后发现问题');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('退款处理中'), findsWidgets);
    expect(find.text('确认收货'), findsNothing);
    expect(find.text('发起纠纷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卖家同意退款后刷新为已退款且不提示失败', (tester) async {
    final apiClient = _OrderDetailTestApiClient()
      ..status = 'refund_requested'
      ..sellerView = true;
    final repository = CommerceRepository(apiClient);
    const session = AppSession(
      user: <String, dynamic>{
        'id': 'seller_demo',
        'display_name': 'Demo Seller',
      },
      session: <String, dynamic>{'access_token': 'demo-access-token'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OrderDetailPage(
          repository: repository,
          session: session,
          orderId: 'order_demo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('同意退款'), findsOneWidget);
    await tester.tap(find.text('同意退款'));
    await tester.pumpAndSettle();

    expect(find.text('已退款'), findsWidgets);
    expect(find.text('同意退款'), findsNothing);
    expect(find.text('操作失败，请稍后重试'), findsNothing);
    expect(find.text('已同意退款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('Unexpected network call in order detail test.');
  }
}
