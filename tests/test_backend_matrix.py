from __future__ import annotations

import unittest
from unittest.mock import patch

import backend.app.routes.reconstructions as reconstructions_module
from shared.task_store import get_task, update_task
from tests.backend_test_support import backend_harness


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _assert_ok(testcase: unittest.TestCase, response, expected_status: int = 200):
    testcase.assertEqual(response.status_code, expected_status)
    payload = response.json()
    testcase.assertEqual(payload["code"], 0)
    testcase.assertEqual(payload["message"], "ok")
    testcase.assertIn("meta", payload)
    testcase.assertIn("request_id", payload["meta"])
    return payload["data"], payload


def _assert_error(
    testcase: unittest.TestCase,
    response,
    *,
    expected_status: int,
    expected_code: int,
) -> dict[str, object]:
    testcase.assertEqual(response.status_code, expected_status)
    payload = response.json()
    testcase.assertEqual(payload["code"], expected_code)
    testcase.assertIn("meta", payload)
    testcase.assertIn("request_id", payload["meta"])
    return payload


def _create_marketplace_fixture(harness):
    seller_id, seller_token, _ = harness.make_user_session(
        identifier="seller-case",
        display_name="Seller",
    )
    buyer_id, buyer_token, _ = harness.make_user_session(
        identifier="buyer-case",
        display_name="Buyer",
    )
    listing_id = harness.make_listing(
        title="Vintage Camera",
        seller_id=seller_id,
        preview_ready=True,
    )
    address_id = harness.make_address(user_id=buyer_id, is_default=True)
    return {
        "seller_id": seller_id,
        "seller_token": seller_token,
        "buyer_id": buyer_id,
        "buyer_token": buyer_token,
        "listing_id": listing_id,
        "address_id": address_id,
    }


def _create_paid_order(harness, fixture: dict[str, str]) -> str:
    response = harness.client.post(
        "/api/v1/orders",
        headers=_auth_headers(fixture["buyer_token"]),
        json={
            "listing_id": fixture["listing_id"],
            "address_id": fixture["address_id"],
        },
    )
    if response.status_code != 200:
        raise AssertionError(response.text)
    payload = response.json()
    if payload.get("code") != 0:
        raise AssertionError(payload)
    data = payload["data"]
    return str(data["order"]["id"])


def _prepare_ready_task(harness, *, task_id: str, seller_id: str) -> None:
    harness.make_task(
        task_id=task_id,
        title="Ready Task",
        status="ready",
        model_rel_path=f"/storage/models/{task_id}/model.ply",
    )
    model_dir = harness.storage_root / "models" / task_id
    model_dir.mkdir(parents=True, exist_ok=True)
    (model_dir / "model.ply").write_bytes(b"ply")
    update_task(task_id, seller_id=seller_id)


class BackendMatrixTestCase(unittest.TestCase):
    def test_empty_market_bootstrap_and_guest_session(self) -> None:
        with backend_harness("empty_market") as harness:
            health = harness.client.get("/health")
            self.assertEqual(health.status_code, 200)
            health_payload = health.json()
            self.assertEqual(health_payload["seeded_users"], 0)
            self.assertIsNone(health_payload["demo_user_id"])

            api_health, _ = _assert_ok(self, harness.client.get("/api/v1/health"))
            self.assertEqual(api_health["seeded_users"], 0)
            self.assertIsNone(api_health["demo_user_id"])

            config, _ = _assert_ok(self, harness.client.get("/api/v1/config/public"))
            self.assertEqual(config["base_currency"], "CNY")
            self.assertTrue(config["guest_entry_enabled"])

            categories, _ = _assert_ok(self, harness.client.get("/api/v1/categories"))
            self.assertGreaterEqual(len(categories), 1)

            review_tags, _ = _assert_ok(self, harness.client.get("/api/v1/reviews/tags"))
            self.assertGreaterEqual(len(review_tags), 1)

            home_page, _ = _assert_ok(self, harness.client.get("/api/v1/pages/home"))
            self.assertEqual(home_page["page_key"], "home")

            home_feed, home_feed_payload = _assert_ok(
                self,
                harness.client.get("/api/v1/home/feed"),
            )
            self.assertEqual(home_feed, [])
            self.assertEqual(home_feed_payload["meta"]["page"]["total"], 0)

            guest_session, _ = _assert_ok(self, harness.client.get("/api/v1/auth/session"))
            self.assertEqual(guest_session["user"]["id"], "guest")
            self.assertTrue(guest_session["session"]["guest_mode"])
            self.assertEqual(guest_session["session"]["access_token"], "")

            invalid_session, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/auth/session",
                    headers=_auth_headers("invalid-token"),
                ),
            )
            self.assertEqual(invalid_session["user"]["id"], "guest")
            self.assertTrue(invalid_session["session"]["guest_mode"])

            listings, _ = _assert_ok(self, harness.client.get("/api/v1/listings"))
            self.assertEqual(listings, [])

    def test_register_logout_and_guest_fallback(self) -> None:
        with backend_harness("auth_flow") as harness:
            register, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/auth/register",
                    json={
                        "display_name": "Matrix User",
                        "identifier": "matrix-user",
                        "password": "MatrixPass123!",
                        "consent_version": "v1",
                    },
                ),
            )
            access_token = str(register["session"]["access_token"])

            session, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/auth/session",
                    headers=_auth_headers(access_token),
                ),
            )
            self.assertEqual(session["user"]["display_name"], "Matrix User")
            self.assertIsNot(session["session"].get("guest_mode"), True)

            _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/auth/logout",
                    headers=_auth_headers(access_token),
                ),
            )

            fallback_session, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/auth/session",
                    headers=_auth_headers(access_token),
                ),
            )
            self.assertEqual(fallback_session["user"]["id"], "guest")
            self.assertTrue(fallback_session["session"]["guest_mode"])

    def test_conversation_flow_and_page_bootstrap(self) -> None:
        with backend_harness("conversation_flow") as harness:
            fixture = _create_marketplace_fixture(harness)

            _assert_error(
                self,
                harness.client.post(
                    "/api/v1/conversations",
                    json={"listing_id": fixture["listing_id"]},
                ),
                expected_status=401,
                expected_code=1001,
            )

            conversation_detail, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/conversations",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={
                        "listing_id": fixture["listing_id"],
                        "content_text": "Is this still available?",
                    },
                ),
            )
            conversation_id = str(conversation_detail["conversation"]["id"])
            self.assertEqual(len(conversation_detail["messages"]), 1)

            conversation_page, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/pages/conversations/{conversation_id}",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(conversation_page["page_key"], "conversation_detail")

            seller_messages, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/conversations/{conversation_id}/messages",
                    headers=_auth_headers(fixture["seller_token"]),
                ),
            )
            self.assertEqual(len(seller_messages), 1)
            self.assertEqual(seller_messages[0]["content_text"], "Is this still available?")

            reply, _ = _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/conversations/{conversation_id}/messages",
                    headers=_auth_headers(fixture["seller_token"]),
                    json={"message_type": "text", "content_text": "Yes, it is."},
                ),
            )
            self.assertEqual(reply["content_text"], "Yes, it is.")

            buyer_conversations, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/conversations",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(len(buyer_conversations), 1)
            self.assertEqual(buyer_conversations[0]["last_message_preview"], "Yes, it is.")
            self.assertEqual(buyer_conversations[0]["unread_count"], 1)

            read_result, _ = _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/conversations/{conversation_id}/read",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={},
                ),
            )
            self.assertEqual(read_result["conversation_id"], conversation_id)

    def test_order_cancel_restores_listing_state(self) -> None:
        with backend_harness("order_cancel") as harness:
            fixture = _create_marketplace_fixture(harness)

            order_payload, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/orders",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={
                        "listing_id": fixture["listing_id"],
                        "address_id": fixture["address_id"],
                    },
                ),
            )
            order_id = str(order_payload["order"]["id"])
            listing_record = harness.store.get_record("listing", fixture["listing_id"])
            self.assertEqual(listing_record["payload"]["status"], "reserved")

            cancelled, _ = _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/orders/{order_id}/cancel",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={},
                ),
            )
            self.assertEqual(cancelled["order"]["status"], "cancelled")

            listing_record = harness.store.get_record("listing", fixture["listing_id"])
            self.assertEqual(listing_record["payload"]["status"], "live")

            order_detail, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/orders/{order_id}",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(order_detail["order"]["status"], "cancelled")

    def test_order_dispute_flow(self) -> None:
        with backend_harness("order_dispute") as harness:
            fixture = _create_marketplace_fixture(harness)
            order_id = _create_paid_order(harness, fixture)

            _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/orders/{order_id}/ship",
                    headers=_auth_headers(fixture["seller_token"]),
                    json={"carrier_name": "SF", "tracking_no": "SF123456"},
                ),
            )

            disputed, _ = _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/orders/{order_id}/dispute",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={"reason": "Package arrived damaged."},
                ),
            )
            self.assertEqual(disputed["order"]["status"], "disputed")

            receipt, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/orders/{order_id}/receipt",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(receipt["shipment"]["status"], "shipped")

    def test_order_completion_review_wallet_membership_and_notifications(self) -> None:
        with backend_harness("order_complete") as harness:
            fixture = _create_marketplace_fixture(harness)

            order_payload, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/orders",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={
                        "listing_id": fixture["listing_id"],
                        "address_id": fixture["address_id"],
                    },
                ),
            )
            order_id = str(order_payload["order"]["id"])

            success_page, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/pages/orders/{order_id}/success",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(success_page["page_key"], "order_success")

            _assert_error(
                self,
                harness.client.get(
                    f"/api/v1/pages/reviews/{order_id}",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
                expected_status=409,
                expected_code=3002,
            )

            _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/orders/{order_id}/ship",
                    headers=_auth_headers(fixture["seller_token"]),
                    json={"carrier_name": "SF", "tracking_no": "SF123456"},
                ),
            )

            receipt, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/orders/{order_id}/receipt",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(receipt["shipment"]["status"], "shipped")

            completed, _ = _assert_ok(
                self,
                harness.client.post(
                    f"/api/v1/orders/{order_id}/confirm-receipt",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={},
                ),
            )
            self.assertEqual(completed["order"]["status"], "completed")

            listing_record = harness.store.get_record("listing", fixture["listing_id"])
            self.assertEqual(listing_record["payload"]["status"], "sold")

            review_page, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/pages/reviews/{order_id}",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(review_page["page_key"], "review_order")

            review_tags, _ = _assert_ok(self, harness.client.get("/api/v1/reviews/tags"))
            self.assertGreaterEqual(len(review_tags), 1)

            review_draft, _ = _assert_ok(
                self,
                harness.client.get(
                    f"/api/v1/orders/{order_id}/review-draft",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(review_draft["order_id"], order_id)
            self.assertIsNone(review_draft["rating"])

            updated_draft, _ = _assert_ok(
                self,
                harness.client.patch(
                    f"/api/v1/orders/{order_id}/review-draft",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={
                        "rating": 5,
                        "content": "Exactly as described.",
                        "tags": ["as_described"],
                    },
                ),
            )
            self.assertEqual(updated_draft["rating"], 5)
            self.assertEqual(updated_draft["content"], "Exactly as described.")

            review, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/reviews",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={
                        "order_id": order_id,
                        "rating": 5,
                        "content": "Exactly as described.",
                        "tags": ["as_described"],
                        "media_asset_ids": [],
                        "anonymity_enabled": False,
                    },
                ),
            )
            self.assertEqual(review["order_id"], order_id)
            self.assertEqual(review["rating"], 5)

            listing_reviews, _ = _assert_ok(
                self,
                harness.client.get(f"/api/v1/listings/{fixture['listing_id']}/reviews"),
            )
            self.assertEqual(len(listing_reviews), 1)
            self.assertEqual(listing_reviews[0]["id"], review["id"])

            seller_wallet, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/wallet/summary",
                    headers=_auth_headers(fixture["seller_token"]),
                ),
            )
            transaction_types = {
                item["transaction_type"] for item in seller_wallet["transactions"]
            }
            self.assertIn("sale_income", transaction_types)

            upgraded, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/membership/upgrade",
                    headers=_auth_headers(fixture["buyer_token"]),
                    json={"plan_key": "pro"},
                ),
            )
            self.assertEqual(upgraded["status"], "active")

            membership_current, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/memberships/current",
                    headers=_auth_headers(fixture["buyer_token"]),
                ),
            )
            self.assertEqual(membership_current["plan"]["plan_key"], "pro")

            seller_notifications, _ = _assert_ok(
                self,
                harness.client.get(
                    "/api/v1/notifications",
                    headers=_auth_headers(fixture["seller_token"]),
                ),
            )
            self.assertGreaterEqual(len(seller_notifications), 1)

            read_all, _ = _assert_ok(
                self,
                harness.client.post(
                    "/api/v1/notifications/read-all",
                    headers=_auth_headers(fixture["seller_token"]),
                    json={},
                ),
            )
            self.assertGreaterEqual(read_all["read_count"], 1)

    def test_reconstruction_auth_and_ownership(self) -> None:
        with backend_harness("reconstruction_security") as harness:
            seller_id, seller_token, _ = harness.make_user_session(
                identifier="seller-recon",
                display_name="Seller",
            )
            other_id, other_token, _ = harness.make_user_session(
                identifier="other-recon",
                display_name="Other",
            )

            _assert_error(
                self,
                harness.client.get("/api/v1/reconstructions"),
                expected_status=401,
                expected_code=1001,
            )

            with patch.object(
                reconstructions_module,
                "_validate_uploaded_video",
                return_value={
                    "streams": [{"codec_type": "video"}],
                    "format": {"duration": 1.0},
                },
            ):
                unauthenticated_create = harness.client.post(
                    "/api/v1/reconstructions",
                    data={
                        "title": "Unauthenticated Task",
                        "description": "Should fail",
                        "price": "99.00",
                    },
                    files={"video": ("clip.mp4", b"video-bytes", "video/mp4")},
                )
                _assert_error(
                    self,
                    unauthenticated_create,
                    expected_status=401,
                    expected_code=1001,
                )

                created = harness.client.post(
                    "/api/v1/reconstructions",
                    headers=_auth_headers(seller_token),
                    data={
                        "title": "Seller Task",
                        "description": "Owned by seller",
                        "price": "99.00",
                    },
                    files={"video": ("clip.mp4", b"video-bytes", "video/mp4")},
                )

            self.assertEqual(created.status_code, 201)
            created_payload = created.json()
            created_task_id = str(created_payload["task_id"])
            created_task = get_task(created_task_id)
            self.assertEqual(created_task["seller_id"], seller_id)

            seller_tasks = harness.client.get(
                "/api/v1/reconstructions",
                headers=_auth_headers(seller_token),
            )
            self.assertEqual(seller_tasks.status_code, 200)
            self.assertEqual(len(seller_tasks.json()), 1)
            self.assertEqual(seller_tasks.json()[0]["task_id"], created_task_id)

            other_tasks = harness.client.get(
                "/api/v1/reconstructions",
                headers=_auth_headers(other_token),
            )
            self.assertEqual(other_tasks.status_code, 200)
            self.assertEqual(other_tasks.json(), [])

            other_detail = harness.client.get(
                f"/api/v1/reconstructions/{created_task_id}",
                headers=_auth_headers(other_token),
            )
            self.assertEqual(other_detail.status_code, 404)

            other_start = harness.client.post(
                f"/api/v1/reconstructions/{created_task_id}/pipeline/start",
                headers=_auth_headers(other_token),
                json={
                    "quality_profile": "balanced",
                    "train_max_steps": 7000,
                    "object_masking": False,
                },
            )
            self.assertEqual(other_start.status_code, 404)

            with patch.object(
                reconstructions_module,
                "_start_pipeline_subprocess",
                return_value=4321,
            ):
                started = harness.client.post(
                    f"/api/v1/reconstructions/{created_task_id}/pipeline/start",
                    headers=_auth_headers(seller_token),
                    json={
                        "quality_profile": "balanced",
                        "train_max_steps": 7000,
                        "object_masking": False,
                    },
                )
            self.assertEqual(started.status_code, 200)
            self.assertEqual(started.json()["status"], "queued")

            publish_task_id = "ready_publish_task"
            _prepare_ready_task(
                harness,
                task_id=publish_task_id,
                seller_id=seller_id,
            )

            publish_without_viewer = harness.client.post(
                f"/api/v1/reconstructions/{publish_task_id}/publish",
                headers=_auth_headers(seller_token),
            )
            _assert_error(
                self,
                publish_without_viewer,
                expected_status=409,
                expected_code=3002,
            )

            update_task(
                publish_task_id,
                viewer_rotation_done=True,
                viewer_translation_done=True,
                viewer_initial_view_done=True,
                viewer_animation_approved=True,
            )
            published = harness.client.post(
                f"/api/v1/reconstructions/{publish_task_id}/publish",
                headers=_auth_headers(seller_token),
            )
            self.assertEqual(published.status_code, 200)
            self.assertTrue(published.json()["is_published"])

            other_publish = harness.client.post(
                f"/api/v1/reconstructions/{publish_task_id}/publish",
                headers=_auth_headers(other_token),
            )
            self.assertEqual(other_publish.status_code, 404)


if __name__ == "__main__":
    unittest.main()
