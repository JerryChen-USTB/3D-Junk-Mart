from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, UploadFile, File, status

from backend.app.http import ok
from backend.app.schemas import (
    ConversationReadRequest,
    ConversationCreateRequest,
    ConversationOfferCreateRequest,
    AuthLoginRequest,
    AuthRefreshRequest,
    AuthRegisterRequest,
    MembershipUpgradeRequest,
    NotificationReadRequest,
    OrderCreateRequest,
    OrderDisputeRequest,
    OrderRefundRequest,
    OrderShipRequest,
    ReviewCreateRequest,
    ReviewDraftUpdateRequest,
    SendMessageRequest,
    ListingDraftCreateRequest,
    ListingDraftUpdateRequest,
    LogoutRequest,
    TypingIndicatorRequest,
    UploadPresignRequest,
    UploadPresignResponse,
    ListingUpdateRequest,
    UserAddressCreateRequest,
    UserAddressUpdateRequest,
    UserProfileUpdate,
)
from backend.app.services.marketplace_store import MarketplaceStore, get_store

router = APIRouter(prefix="/api/v1", tags=["marketplace"])

BASE_CURRENCY = "CNY"
DEFAULT_PAGE_SIZE = 20
ORDER_STATUS_LABELS = {
    "pending_payment": "待付款",
    "awaiting_shipment": "待发货",
    "shipped": "待收货",
    "completed": "交易成功",
    "cancelled": "已取消",
    "refund_requested": "退款处理中",
    "refunded": "已退款",
    "disputed": "纠纷中",
}
CONDITION_LABELS = {
    "new": "全新",
    "excellent": "几乎全新",
    "good": "成色良好",
    "fair": "正常使用痕迹",
    "parts": "瑕疵明显",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _bearer_token(request: Request) -> str | None:
    header = request.headers.get("authorization") or request.headers.get("Authorization")
    if not header:
        return None
    if not header.lower().startswith("bearer "):
        return None
    token = header.split(" ", 1)[1].strip()
    return token or None


def _money(amount_minor: int | None, currency: str | None = None) -> dict[str, Any]:
    return {"amount_minor": int(amount_minor or 0), "currency": currency or BASE_CURRENCY}


def _media_asset(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not payload:
        return None
    asset = payload.get("asset") if isinstance(payload.get("asset"), dict) else payload
    return {
        "id": asset.get("id") or asset.get("asset_id") or asset.get("entity_id") or "",
        "kind": asset.get("kind") or "image",
        "url": asset.get("url") or asset.get("public_url") or "",
        "thumbnail_url": asset.get("thumbnail_url"),
        "width": asset.get("width"),
        "height": asset.get("height"),
        "mime_type": asset.get("mime_type"),
        "sort_order": int(asset.get("sort_order") or 0),
    }


def _current_user(store: MarketplaceStore, request: Request) -> dict[str, Any]:
    token = _bearer_token(request)
    return store.current_user(token)


def _current_user_id(store: MarketplaceStore, request: Request) -> str:
    return _current_user(store, request)["entity_id"]


def _require_current_user(store: MarketplaceStore, request: Request) -> dict[str, Any]:
    token = _bearer_token(request)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="请先登录。")
    session = store.session_by_token(token)
    if session is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录状态已失效，请重新登录。")
    user = store.user_record(session["payload"].get("user_id") or "")
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录状态已失效，请重新登录。")
    return user


def _require_current_user_id(store: MarketplaceStore, request: Request) -> str:
    return _require_current_user(store, request)["entity_id"]


def _optional_current_user_id(store: MarketplaceStore, request: Request) -> str | None:
    token = _bearer_token(request)
    if not token:
        return None
    session = store.session_by_token(token)
    if session is None:
        return None
    return session["payload"].get("user_id") or None


def _guest_auth_payload() -> dict[str, Any]:
    return {
        "user": {
            "id": "guest",
            "display_name": "Guest",
            "avatar_url": None,
            "bio": "Browse the marketplace in read-only mode.",
            "location": None,
            "sesame_credit_score": 0,
            "vip_level": "guest",
            "follower_count": 0,
            "following_count": 0,
            "positive_rate": None,
        },
        "session": {
            "id": "guest-session",
            "access_token": "",
            "refresh_token": None,
            "access_token_expires_at": _now(),
            "refresh_token_expires_at": _now(),
            "device_name": "guest",
            "device_platform": "guest",
            "is_new_user": False,
            "guest_mode": True,
        },
        "profile": {
            "id": "guest",
            "display_name": "Guest",
            "avatar_url": None,
            "birth_date": None,
            "age_years": None,
            "bio": "Browse items, 3D previews, and search results before signing in.",
            "location": None,
            "sesame_credit_score": 0,
            "vip_level": "guest",
            "profile_visibility": "public",
            "updated_at": _now(),
        },
    }


def _member_record(store: MarketplaceStore, conversation_id: str, user_id: str) -> dict[str, Any] | None:
    return store.find_first(
        "conversation_member",
        predicate=lambda item: item["payload"].get("conversation_id") == conversation_id and item["payload"].get("user_id") == user_id,
    )


def _set_conversation_member_unread(
    store: MarketplaceStore,
    conversation_id: str,
    user_id: str,
    *,
    unread_count: int,
    last_read_message_id: str | None = None,
) -> None:
    member = _member_record(store, conversation_id, user_id)
    if member is None:
        return
    payload = dict(member["payload"])
    payload["unread_count"] = max(unread_count, 0)
    if last_read_message_id is not None:
        payload["last_read_message_id"] = last_read_message_id
    store.upsert_record("conversation_member", member["entity_id"], payload, parent_id=conversation_id)


def _ensure_listing_exists(store: MarketplaceStore, listing_id: str) -> dict[str, Any]:
    listing = store.get_record("listing", listing_id)
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found.")
    return listing


def _ensure_order_exists(store: MarketplaceStore, order_id: str) -> dict[str, Any]:
    order = store.get_record("order", order_id)
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found.")
    return order


def _update_listing_status(store: MarketplaceStore, listing_id: str, status_name: str) -> dict[str, Any]:
    listing = _ensure_listing_exists(store, listing_id)
    payload = dict(listing["payload"])
    payload["status"] = status_name
    payload["updated_at"] = _now()
    return store.upsert_record("listing", listing_id, payload)


def _ensure_owned_listing(store: MarketplaceStore, listing_id: str, user_id: str) -> dict[str, Any]:
    listing = _ensure_listing_exists(store, listing_id)
    if listing["payload"].get("seller_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found.")
    return listing


def _upload_extension(filename: str | None, content_type: str | None) -> str:
    content_type = (content_type or "").lower()
    if content_type == "image/png":
        return ".png"
    if content_type == "image/webp":
        return ".webp"
    if content_type in {"image/jpg", "image/jpeg"}:
        return ".jpg"

    suffix = (filename or "").lower()
    for candidate in (".png", ".webp", ".jpg", ".jpeg"):
        if suffix.endswith(candidate):
            return ".jpg" if candidate == ".jpeg" else candidate
    return ".jpg"


async def _store_uploaded_cover(file: UploadFile, *, namespace: str) -> dict[str, Any]:
    content_type = (file.content_type or "").lower()
    if content_type and not content_type.startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image files are supported.")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded image is empty.")
    if len(content) > 4 * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cover image must be 4MB or smaller.")

    from shared.config import STORAGE_ROOT

    ext = _upload_extension(file.filename, content_type)
    asset_id = _new_id(f"{namespace}_cover")
    relative_dir = "listing_covers"
    storage_dir = STORAGE_ROOT / relative_dir
    storage_dir.mkdir(parents=True, exist_ok=True)
    relative_name = f"{asset_id}{ext}"
    storage_path = storage_dir / relative_name
    storage_path.write_bytes(content)
    public_url = f"/storage/{relative_dir}/{relative_name}"
    return {
        "id": asset_id,
        "kind": "image",
        "url": public_url,
        "thumbnail_url": public_url,
        "mime_type": content_type or None,
        "sort_order": 0,
    }


def _address_snapshot(record: dict[str, Any] | None) -> dict[str, Any] | None:
    if record is None:
        return None
    payload = dict(record["payload"])
    return {
        "receiver_name": payload.get("recipient_name") or "",
        "phone": payload.get("phone") or "",
        "region": payload.get("region_code") or "",
        "detail": payload.get("address_line1") or "",
        "detail2": payload.get("address_line2"),
    }


def _listing_snapshot(store: MarketplaceStore, listing: dict[str, Any]) -> dict[str, Any]:
    payload = dict(listing["payload"])
    seller = _user_summary(store, store.user_record(payload.get("seller_id") or ""))
    cover = payload.get("cover_media_json") if isinstance(payload.get("cover_media_json"), dict) else None
    return {
        "listing_id": listing["entity_id"],
        "title": payload.get("title") or "",
        "subtitle": payload.get("subtitle"),
        "price_minor": int(payload.get("price_minor") or 0),
        "currency": payload.get("currency") or BASE_CURRENCY,
        "cover_asset_id": (cover or {}).get("id"),
        "cover_url": (cover or {}).get("url"),
        "seller_display_name": (seller or {}).get("display_name"),
        "viewer_url": payload.get("viewer_url"),
    }


def _find_conversation(store: MarketplaceStore, listing_id: str, buyer_id: str, seller_id: str) -> dict[str, Any] | None:
    return store.find_first(
        "conversation",
        predicate=lambda item: item["payload"].get("listing_id") == listing_id
        and item["payload"].get("buyer_id") == buyer_id
        and item["payload"].get("seller_id") == seller_id,
    )


def _cancel_active_offers(store: MarketplaceStore, conversation_id: str, *, except_offer_id: str | None = None) -> None:
    for offer in store.list_records("conversation_offer", parent_id=conversation_id):
        if offer["entity_id"] == except_offer_id:
            continue
        payload = dict(offer["payload"])
        if payload.get("status") == "active":
            payload["status"] = "cancelled"
            payload["updated_at"] = _now()
            store.upsert_record("conversation_offer", offer["entity_id"], payload, parent_id=conversation_id)


def _append_conversation_message(
    store: MarketplaceStore,
    conversation: dict[str, Any],
    *,
    sender_id: str,
    message_type: str,
    content_text: str = "",
    asset: dict[str, Any] | None = None,
    offer_id: str | None = None,
    recipient_notification: bool = True,
) -> dict[str, Any]:
    conversation_id = conversation["entity_id"]
    now = _now()
    message_id = _new_id("message")
    message_payload = {
        "id": message_id,
        "conversation_id": conversation_id,
        "sender_id": sender_id,
        "message_type": message_type,
        "content_text": content_text,
        "asset": asset,
        "offer_id": offer_id,
        "created_at": now,
        "read_at": None,
    }
    store.upsert_record("message", message_id, message_payload, parent_id=conversation_id)

    conversation_payload = dict(conversation["payload"])
    conversation_payload["last_message_preview"] = content_text or ("新的议价请求" if offer_id else "新消息")
    conversation_payload["last_message_type"] = message_type
    conversation_payload["updated_at"] = now
    conversation_payload["last_message_at"] = now
    store.upsert_record("conversation", conversation_id, conversation_payload)

    recipient_id = (
        conversation_payload.get("seller_id")
        if sender_id == conversation_payload.get("buyer_id")
        else conversation_payload.get("buyer_id")
    )
    _set_conversation_member_unread(store, conversation_id, sender_id, unread_count=0, last_read_message_id=message_id)
    if recipient_id:
        recipient_member = _member_record(store, conversation_id, recipient_id)
        next_unread = int((recipient_member or {"payload": {}})["payload"].get("unread_count") or 0) + 1
        _set_conversation_member_unread(store, conversation_id, recipient_id, unread_count=next_unread)
        if recipient_notification:
            store.create_notification(
                recipient_id,
                notification_type="message",
                category="message",
                icon_key="chat",
                title="New message",
                body=content_text or "You received a new message.",
                entity_type="conversation",
                entity_id=conversation_id,
            )
    return message_payload


def _user_summary(store: MarketplaceStore, user_record: dict[str, Any] | None) -> dict[str, Any] | None:
    if user_record is None:
        return None
    payload = dict(user_record["payload"])
    profile = store.profile_record(user_record["entity_id"])
    profile_payload = dict(profile["payload"]) if profile else {}
    follower_count = sum(
        1
        for item in store.list_records("user_follow")
        if item["payload"].get("following_user_id") == user_record["entity_id"]
    )
    following_count = sum(
        1
        for item in store.list_records("user_follow")
        if item["payload"].get("follower_user_id") == user_record["entity_id"]
    )
    return {
        "id": user_record["entity_id"],
        "display_name": profile_payload.get("display_name") or payload.get("display_name") or "",
        "avatar_url": profile_payload.get("avatar_url") or payload.get("avatar_url"),
        "bio": profile_payload.get("bio") or payload.get("bio"),
        "location": profile_payload.get("location") or payload.get("location"),
        "sesame_credit_score": int(profile_payload.get("sesame_credit_score") or payload.get("sesame_credit_score") or 0),
        "vip_level": profile_payload.get("vip_level") or payload.get("vip_level") or "none",
        "follower_count": follower_count,
        "following_count": following_count,
        "positive_rate": profile_payload.get("positive_rate"),
    }


def _profile_detail(store: MarketplaceStore, user_record: dict[str, Any] | None) -> dict[str, Any] | None:
    if user_record is None:
        return None
    payload = dict(user_record["payload"])
    profile = store.profile_record(user_record["entity_id"])
    profile_payload = dict(profile["payload"]) if profile else {}
    birth_date = profile_payload.get("birth_date") or payload.get("birth_date")
    age_years = profile_payload.get("age_years")
    if age_years is None and birth_date:
        try:
            age_years = max(0, datetime.now().year - int(str(birth_date).split("-")[0]))
        except Exception:
            age_years = None
    return {
        "id": user_record["entity_id"],
        "display_name": profile_payload.get("display_name") or payload.get("display_name") or "",
        "avatar_url": profile_payload.get("avatar_url") or payload.get("avatar_url"),
        "birth_date": birth_date,
        "age_years": age_years,
        "bio": profile_payload.get("bio") or payload.get("bio"),
        "location": profile_payload.get("location") or payload.get("location"),
        "sesame_credit_score": int(profile_payload.get("sesame_credit_score") or payload.get("sesame_credit_score") or 0),
        "vip_level": profile_payload.get("vip_level") or payload.get("vip_level") or "none",
        "profile_visibility": profile_payload.get("profile_visibility") or payload.get("profile_visibility") or "public",
        "updated_at": profile_payload.get("updated_at") or payload.get("updated_at"),
    }


def _address_summary(record: dict[str, Any] | None) -> dict[str, Any] | None:
    if record is None:
        return None
    payload = dict(record["payload"])
    full_address = " ".join(
        part
        for part in [
            str(payload.get("region_code") or "").strip(),
            str(payload.get("address_line1") or "").strip(),
            str(payload.get("address_line2") or "").strip(),
        ]
        if part
    ).strip()
    return {
        "id": record["entity_id"],
        "user_id": payload.get("user_id") or "",
        "label": payload.get("label"),
        "recipient_name": payload.get("recipient_name") or "",
        "phone": payload.get("phone") or "",
        "region_code": payload.get("region_code") or "",
        "address_line1": payload.get("address_line1") or "",
        "address_line2": payload.get("address_line2"),
        "full_address": full_address,
        "is_default": bool(payload.get("is_default")),
        "created_at": payload.get("created_at") or record["created_at"],
        "updated_at": payload.get("updated_at") or record["updated_at"],
    }


def _validated_address_payload(payload: dict[str, Any], *, partial: bool = False) -> dict[str, Any]:
    cleaned = {
        key: value.strip() if isinstance(value, str) else value
        for key, value in payload.items()
    }
    required_keys = ("recipient_name", "phone", "region_code", "address_line1")
    for key in required_keys:
        if (not partial or key in cleaned) and not str(cleaned.get(key) or "").strip():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="收货人、手机号、地区和详细地址不能为空。")
    return cleaned


def _favorite_count(store: MarketplaceStore, listing_id: str) -> int:
    return sum(1 for item in store.list_records("listing_favorite") if item["payload"].get("listing_id") == listing_id)


def _is_favorited(store: MarketplaceStore, listing_id: str, user_id: str | None) -> bool:
    if not user_id:
        return False
    return store.get_record("listing_favorite", f"favorite_{user_id}_{listing_id}") is not None


def _seller_trust_summary(store: MarketplaceStore, seller_id: str | None) -> dict[str, Any]:
    if not seller_id:
        return {}
    stats = store.user_stats_payload(seller_id)
    return {
        "seller_id": seller_id,
        "sold_count": int(stats.get("sold_count") or 0),
        "followers_count": int(stats.get("followers_count") or 0),
        "positive_rate": stats.get("positive_rate"),
        "sesame_credit_score": int(stats.get("sesame_credit_score") or 0),
        "vip_level": stats.get("vip_level") or "none",
    }


def _shipping_promise(payload: dict[str, Any]) -> str:
    explicit = (payload.get("shipping_promise") or "").strip()
    if explicit:
        return explicit
    if int(payload.get("shipping_fee_minor") or 0) == 0:
        return "24小时内发货 · 包邮"
    return "24小时内发货"


def _listing_summary(
    store: MarketplaceStore,
    listing_record: dict[str, Any],
    *,
    viewer_user_id: str | None = None,
) -> dict[str, Any]:
    payload = dict(listing_record["payload"])
    seller_id = payload.get("seller_id") or ""
    seller = _user_summary(store, store.user_record(seller_id))
    location = payload.get("location_city") or (seller or {}).get("location")
    listing_id = listing_record["entity_id"]
    condition_level = payload.get("condition_level")
    return {
        "id": listing_id,
        "category_id": payload.get("category_id"),
        "title": payload.get("title") or "",
        "subtitle": payload.get("subtitle"),
        "price": _money(payload.get("price_minor"), payload.get("currency")),
        "original_price": _money(payload.get("original_price_minor"), payload.get("currency")) if payload.get("original_price_minor") is not None else None,
        "status": payload.get("status") or "draft",
        "cover_media": _media_asset(payload.get("cover_media_json")),
        "location": location,
        "location_city": location,
        "condition_level": condition_level,
        "condition_label": CONDITION_LABELS.get(str(condition_level).lower(), condition_level),
        "shipping_fee": _money(payload.get("shipping_fee_minor"), payload.get("currency")),
        "shipping_promise": _shipping_promise(payload),
        "is_negotiable": bool(payload.get("is_negotiable", True)),
        "is_favorited": _is_favorited(store, listing_id, viewer_user_id),
        "favorite_count": _favorite_count(store, listing_id),
        "has_3d_preview": bool(payload.get("viewer_url") or payload.get("model_url")),
        "badges": list(payload.get("badges_json") or []),
        "seller_trust": _seller_trust_summary(store, seller_id),
        "seller": seller,
        "viewer_url": payload.get("viewer_url"),
        "published_at": payload.get("published_at"),
        "updated_at": payload.get("updated_at") or listing_record["updated_at"],
    }


def _review_summary(store: MarketplaceStore, review_record: dict[str, Any]) -> dict[str, Any]:
    payload = dict(review_record["payload"])
    media = [
        _media_asset(item["payload"].get("asset"))
        for item in store.list_records("review_media", parent_id=review_record["entity_id"])
    ]
    media = [item for item in media if item is not None]
    tags: list[str] = []
    for link in store.list_records("review_tag_link", parent_id=review_record["entity_id"]):
        tag_id = link["payload"].get("tag_id")
        tag = store.get_record("review_tag", tag_id) if tag_id else None
        if tag:
            tags.append(tag["payload"].get("display_name") or tag["payload"].get("tag_key") or tag_id)
    return {
        "id": review_record["entity_id"],
        "order_id": payload.get("order_id"),
        "listing_id": payload.get("listing_id"),
        "rating": int(payload.get("rating") or 0),
        "tags": tags,
        "content": payload.get("content") or "",
        "media": media,
        "anonymity_enabled": bool(payload.get("is_anonymous")),
    }


def _listing_detail(
    store: MarketplaceStore,
    listing_record: dict[str, Any],
    *,
    viewer_user_id: str | None = None,
) -> dict[str, Any]:
    summary = _listing_summary(store, listing_record, viewer_user_id=viewer_user_id)
    listing_id = listing_record["entity_id"]
    payload = dict(listing_record["payload"])
    return {
        "listing": summary,
        "media": [_media_asset(item["payload"]) for item in store.list_records("listing_media", parent_id=listing_id) if _media_asset(item["payload"]) is not None],
        "seller": summary["seller"],
        "preview_3d": store.listing_preview_payload(listing_id),
        "specs": [
            {
                "spec_key": item["payload"].get("spec_key") or "",
                "spec_value": item["payload"].get("spec_value") or "",
                "sort_order": int(item["payload"].get("sort_order") or 0),
            }
            for item in store.list_records("listing_spec", parent_id=listing_id)
        ],
        "similar": [
            _listing_summary(store, item, viewer_user_id=viewer_user_id)
            for item in store.list_records("listing")
            if item["entity_id"] != listing_id and item["payload"].get("category_id") == payload.get("category_id") and item["payload"].get("status") == "live"
        ][:6],
        "inquiries": [],
        "reviews": [_review_summary(store, item) for item in store.list_records("review") if item["payload"].get("listing_id") == listing_id],
        "actions": [
            {"key": "favorite", "title": "收藏", "enabled": True, "active": summary["is_favorited"]},
            {"key": "chat", "title": "联系卖家", "enabled": True},
            {"key": "offer", "title": "出价议价", "enabled": summary["status"] == "live" and summary["is_negotiable"]},
            {"key": "buy", "title": "立即购买", "enabled": summary["status"] == "live"},
        ],
        "service_promises": [
            "平台担保交易",
            _shipping_promise(payload),
            "支持 3D 预览验货",
        ],
        "transaction_info": {
            "condition_level": payload.get("condition_level"),
            "condition_label": CONDITION_LABELS.get(str(payload.get("condition_level")).lower(), payload.get("condition_level")),
            "defect_notes": payload.get("defect_notes") or "卖家未补充瑕疵描述。",
            "shipping_fee": _money(payload.get("shipping_fee_minor"), payload.get("currency")),
            "shipping_promise": _shipping_promise(payload),
            "is_negotiable": bool(payload.get("is_negotiable", True)),
            "favorite_count": _favorite_count(store, listing_id),
        },
        "listing_payload": payload,
    }


def _matches_price_bucket(amount_minor: int, price_bucket: str | None) -> bool:
    if not price_bucket:
        return True
    if price_bucket == "lt_1000":
        return amount_minor < 100000
    if price_bucket == "1000_5000":
        return 100000 <= amount_minor < 500000
    if price_bucket == "gte_5000":
        return amount_minor >= 500000
    return True


def _apply_listing_filters(
    items: list[dict[str, Any]],
    *,
    query: str = "",
    category_id: str | None = None,
    status_name: str | None = None,
    seller_id: str | None = None,
    price_bucket: str | None = None,
    location: str | None = None,
    condition_level: str | None = None,
    only_3d: bool = False,
    only_negotiable: bool = False,
) -> list[dict[str, Any]]:
    results = list(items)
    if query:
        lowered = query.strip().lower()
        results = [
            item
            for item in results
            if lowered in (item.get("title") or "").lower()
            or lowered in (item.get("subtitle") or "").lower()
            or lowered in (item.get("location") or "").lower()
            or lowered in (item.get("seller", {}) or {}).get("display_name", "").lower()
        ]
    if category_id:
        results = [item for item in results if item.get("category_id") == category_id]
    if status_name:
        results = [item for item in results if item.get("status") == status_name]
    if seller_id:
        results = [item for item in results if ((item.get("seller") or {}).get("id") == seller_id)]
    if price_bucket:
        results = [
            item
            for item in results
            if _matches_price_bucket(int(((item.get("price") or {}).get("amount_minor") or 0)), price_bucket)
        ]
    if location:
        lowered_location = location.strip().lower()
        results = [item for item in results if lowered_location in (item.get("location") or "").lower()]
    if condition_level:
        lowered_condition = condition_level.strip().lower()
        results = [item for item in results if str(item.get("condition_level") or "").lower() == lowered_condition]
    if only_3d:
        results = [item for item in results if bool(item.get("has_3d_preview"))]
    if only_negotiable:
        results = [item for item in results if bool(item.get("is_negotiable"))]
    return results


def _sort_listing_items(items: list[dict[str, Any]], sort_key: str | None) -> list[dict[str, Any]]:
    key = (sort_key or "latest").strip().lower()
    results = list(items)
    if key == "price_asc":
        results.sort(key=lambda item: int(((item.get("price") or {}).get("amount_minor") or 0)))
        return results
    if key == "price_desc":
        results.sort(key=lambda item: int(((item.get("price") or {}).get("amount_minor") or 0)), reverse=True)
        return results
    if key == "popular":
        results.sort(
            key=lambda item: (
                int(item.get("favorite_count") or 0),
                bool(item.get("has_3d_preview")),
                item.get("updated_at") or "",
            ),
            reverse=True,
        )
        return results
    results.sort(
        key=lambda item: (
            item.get("published_at") or item.get("updated_at") or "",
            int(item.get("favorite_count") or 0),
        ),
        reverse=True,
    )
    return results


def _serialize_offer(record: dict[str, Any] | None) -> dict[str, Any] | None:
    if record is None:
        return None
    payload = dict(record["payload"])
    return {
        "id": record["entity_id"],
        "conversation_id": payload.get("conversation_id"),
        "listing_id": payload.get("listing_id"),
        "proposer_id": payload.get("proposer_id"),
        "counterparty_id": payload.get("counterparty_id"),
        "amount": _money(payload.get("amount_minor"), payload.get("currency")),
        "status": payload.get("status") or "active",
        "note": payload.get("note") or "",
        "order_id": payload.get("order_id"),
        "created_at": payload.get("created_at"),
        "updated_at": payload.get("updated_at"),
        "accepted_at": payload.get("accepted_at"),
    }


def _active_offer_record(store: MarketplaceStore, conversation_id: str) -> dict[str, Any] | None:
    offers = sorted(
        store.list_records("conversation_offer", parent_id=conversation_id),
        key=lambda item: item["payload"].get("created_at") or "",
        reverse=True,
    )
    for record in offers:
        if (record["payload"].get("status") or "") == "active":
            return record
    return offers[0] if offers else None


def _accepted_offer_record(store: MarketplaceStore, conversation_id: str) -> dict[str, Any] | None:
    offers = sorted(
        store.list_records("conversation_offer", parent_id=conversation_id),
        key=lambda item: item["payload"].get("accepted_at")
        or item["payload"].get("updated_at")
        or item["payload"].get("created_at")
        or "",
        reverse=True,
    )
    for record in offers:
        if (record["payload"].get("status") or "") == "accepted":
            return record
    return None


def _related_order_for_conversation(store: MarketplaceStore, conversation_record: dict[str, Any]) -> dict[str, Any] | None:
    payload = dict(conversation_record["payload"])
    records = [
        item
        for item in store.list_records("order")
        if item["payload"].get("listing_id") == payload.get("listing_id")
        and item["payload"].get("buyer_id") == payload.get("buyer_id")
        and item["payload"].get("seller_id") == payload.get("seller_id")
    ]
    if not records:
        return None
    records.sort(key=lambda item: item["payload"].get("created_at") or "", reverse=True)
    return records[0]


def _conversation_summary(store: MarketplaceStore, conversation_record: dict[str, Any], *, current_user_id: str | None = None) -> dict[str, Any]:
    payload = dict(conversation_record["payload"])
    buyer = store.user_record(payload.get("buyer_id") or "")
    seller = store.user_record(payload.get("seller_id") or "")
    member = _member_record(store, conversation_record["entity_id"], current_user_id) if current_user_id else None
    listing = store.get_record("listing", payload.get("listing_id") or "")
    if current_user_id and current_user_id == payload.get("buyer_id"):
        other = seller
    elif current_user_id and current_user_id == payload.get("seller_id"):
        other = buyer
    else:
        other = seller or buyer
    return {
        "id": conversation_record["entity_id"],
        "listing_id": payload.get("listing_id"),
        "buyer_id": payload.get("buyer_id"),
        "seller_id": payload.get("seller_id"),
        "role": (
            "buyer"
            if current_user_id and current_user_id == payload.get("buyer_id")
            else "seller"
            if current_user_id and current_user_id == payload.get("seller_id")
            else None
        ),
        "other_user": _user_summary(store, other),
        "last_message_preview": payload.get("last_message_preview"),
        "listing_title": (listing["payload"].get("title") if listing else None),
        "last_message_type": payload.get("last_message_type") or "text",
        "unread_count": int((member or {"payload": payload})["payload"].get("unread_count") or 0),
        "updated_at": payload.get("updated_at"),
    }


def _conversation_detail(store: MarketplaceStore, conversation_record: dict[str, Any], *, current_user_id: str | None = None) -> dict[str, Any]:
    payload = dict(conversation_record["payload"])
    conversation_id = conversation_record["entity_id"]
    messages = sorted(
        store.list_records("message", parent_id=conversation_id),
        key=lambda item: item["payload"].get("created_at") or "",
    )
    listing = store.get_record("listing", payload.get("listing_id") or "")
    active_offer = _serialize_offer(_active_offer_record(store, conversation_id))
    accepted_offer = _serialize_offer(_accepted_offer_record(store, conversation_id))
    related_order = _related_order_for_conversation(store, conversation_record)
    return {
        "conversation": _conversation_summary(store, conversation_record, current_user_id=current_user_id),
        "item_preview": _listing_summary(store, listing, viewer_user_id=current_user_id) if listing else None,
        "safety_banner": {
            "title": "平台安全提醒",
            "body": "请勿在站外转账，交易与售后尽量保留在平台内完成。",
            "level": "info",
        },
        "messages": [
            {
                "id": item["entity_id"],
                "conversation_id": conversation_id,
                "sender_id": item["payload"].get("sender_id"),
                "message_type": item["payload"].get("message_type") or "text",
                "content_text": item["payload"].get("content_text") or "",
                "asset": _media_asset(item["payload"].get("asset")),
                "offer": _serialize_offer(
                    store.get_record("conversation_offer", item["payload"].get("offer_id") or "")
                    if item["payload"].get("offer_id")
                    else None
                ),
                "created_at": item["payload"].get("created_at"),
                "read_at": item["payload"].get("read_at"),
            }
            for item in messages
        ],
        "composer": {
            "placeholder": "发送消息",
            "allowed_message_types": ["text", "image", "video", "system", "offer"],
            "quick_actions": ["发送图片", "发送视频", "发起议价", "查看订单"],
        },
        "active_offer": active_offer,
        "accepted_offer": accepted_offer,
        "related_order": _order_summary(store, related_order, current_user_id=current_user_id) if related_order else None,
    }


def _order_summary(
    store: MarketplaceStore,
    order_record: dict[str, Any],
    *,
    current_user_id: str | None = None,
) -> dict[str, Any]:
    payload = dict(order_record["payload"])
    item_snapshot = dict(payload.get("item_snapshot_json") or {})
    logistics = dict(payload.get("logistics_json") or {})
    role = "buyer" if current_user_id and current_user_id == payload.get("buyer_id") else "seller" if current_user_id and current_user_id == payload.get("seller_id") else None
    address = dict(logistics.get("address") or {})
    return {
        "id": order_record["entity_id"],
        "order_no": payload.get("order_no"),
        "offer_id": payload.get("offer_id"),
        "conversation_id": payload.get("conversation_id"),
        "status": payload.get("status") or "pending",
        "status_label": ORDER_STATUS_LABELS.get(payload.get("status") or "", payload.get("status") or "pending"),
        "payment_status": payload.get("payment_status") or "pending",
        "shipping_status": payload.get("shipping_status") or "pending",
        "aftersale_status": payload.get("aftersale_status") or "none",
        "role": role,
        "buyer": _user_summary(store, store.user_record(payload.get("buyer_id") or "")),
        "seller": _user_summary(store, store.user_record(payload.get("seller_id") or "")),
        "item_snapshot": item_snapshot,
        "totals": {
            "subtotal": _money(payload.get("subtotal_minor"), payload.get("currency")),
            "shipping": _money(payload.get("shipping_minor"), payload.get("currency")),
            "discount": _money(payload.get("discount_minor"), payload.get("currency")),
            "total": _money(payload.get("total_minor"), payload.get("currency")),
        },
        "logistics": logistics,
        "address": address,
        "can_confirm_receipt": bool(payload.get("can_confirm_receipt")),
    }


def _order_action_bar(payload: dict[str, Any], *, current_user_id: str | None = None, shipment_ready: bool = False) -> list[dict[str, Any]]:
    role = "buyer" if current_user_id and current_user_id == payload.get("buyer_id") else "seller" if current_user_id and current_user_id == payload.get("seller_id") else None
    status_name = payload.get("status") or ""
    actions = [{"key": "contact_peer", "title": "联系对方", "enabled": True}]
    if role == "buyer":
        if status_name == "pending_payment":
            actions.extend(
                [
                    {"key": "mock_pay", "title": "立即支付", "enabled": True, "style": "primary"},
                    {"key": "cancel_order", "title": "取消订单", "enabled": True},
                ]
            )
        elif status_name == "awaiting_shipment":
            actions.extend(
                [
                    {"key": "request_refund", "title": "申请退款", "enabled": True},
                ]
            )
        elif status_name == "shipped":
            actions.extend(
                [
                    {"key": "track_shipment", "title": "查看物流", "enabled": shipment_ready},
                    {"key": "request_refund", "title": "申请退款", "enabled": True},
                    {"key": "confirm_receipt", "title": "确认收货", "enabled": True, "style": "primary"},
                ]
            )
        elif status_name == "completed":
            actions.append({"key": "review", "title": "去评价", "enabled": True, "style": "primary"})
        elif status_name == "refund_requested":
            actions.append({"key": "open_dispute", "title": "发起纠纷", "enabled": True})
    if role == "seller":
        if status_name == "awaiting_shipment":
            actions.extend(
                [
                    {"key": "ship_order", "title": "立即发货", "enabled": True, "style": "primary"},
                ]
            )
        elif status_name == "refund_requested":
            actions.extend(
                [
                    {"key": "approve_refund", "title": "同意退款", "enabled": True, "style": "primary"},
                    {"key": "reject_refund", "title": "拒绝退款", "enabled": True},
                ]
            )
        elif status_name == "shipped":
            actions.append({"key": "track_shipment", "title": "查看物流", "enabled": shipment_ready})
    if status_name == "disputed":
        actions.append({"key": "platform_help", "title": "平台介入中", "enabled": False})
    return actions


def _order_detail(store: MarketplaceStore, order_record: dict[str, Any], *, current_user_id: str | None = None) -> dict[str, Any]:
    payload = dict(order_record["payload"])
    order_id = order_record["entity_id"]
    timeline = sorted(
        store.list_records("order_event", parent_id=order_id),
        key=lambda item: item["payload"].get("occurred_at") or "",
    )
    shipment = store.find_first("shipment", predicate=lambda item: item["payload"].get("order_id") == order_id)
    shipment_events = []
    if shipment is not None:
        shipment_events = [
            {
                "id": item["entity_id"],
                "shipment_id": item["payload"].get("shipment_id"),
                "event_code": item["payload"].get("event_code") or "",
                "event_text": item["payload"].get("event_text") or "",
                "event_city": item["payload"].get("event_city"),
                "occurred_at": item["payload"].get("occurred_at"),
            }
            for item in store.list_records("shipment_event", parent_id=shipment["entity_id"])
        ]
    summary = _order_summary(store, order_record, current_user_id=current_user_id)
    payment_status = payload.get("payment_status") or "pending"
    aftersale_status = payload.get("aftersale_status") or "none"
    return {
        "order": summary,
        "timeline": [
            {
                "id": item["entity_id"],
                "order_id": order_id,
                "status": item["payload"].get("status") or "",
                "event_note": item["payload"].get("event_note") or "",
                "actor_user_id": item["payload"].get("actor_user_id"),
                "occurred_at": item["payload"].get("occurred_at"),
            }
            for item in timeline
        ],
        "receipt": {
            "payment": {
                "id": f"payment_{order_id}",
                "order_id": order_id,
                "payment_method": payload.get("payment_method") or "wechat_pay",
                "status": payload.get("payment_status") or "paid",
                "amount": _money(payload.get("total_minor"), payload.get("currency")),
                "provider_ref": payload.get("provider_ref"),
            },
            "shipment": {
                "id": shipment["entity_id"] if shipment else None,
                "order_id": order_id,
                "carrier_name": shipment["payload"].get("carrier_name") if shipment else None,
                "tracking_no": shipment["payload"].get("tracking_no") if shipment else None,
                "status": shipment["payload"].get("status") if shipment else None,
                "shipped_at": shipment["payload"].get("shipped_at") if shipment else None,
                "estimated_delivery_at": shipment["payload"].get("estimated_delivery_at") if shipment else None,
                "events": shipment_events,
            },
        },
        "status_card": {
            "title": ORDER_STATUS_LABELS.get(payload.get("status") or "", payload.get("status") or ""),
            "subtitle": payload.get("status_message")
            or (
                "请先完成模拟支付，订单将转入待发货。"
                if payload.get("status") == "pending_payment"
                else "订单正在按当前状态推进。"
            ),
            "tone": (
                "warning"
                if payload.get("status") in {"pending_payment", "refund_requested"}
                else "success"
                if payload.get("status") in {"completed", "refunded"}
                else "neutral"
            ),
        },
        "aftersale": {
            "status": aftersale_status,
            "reason": payload.get("aftersale_reason"),
            "requested_at": payload.get("aftersale_requested_at"),
            "resolved_at": payload.get("aftersale_resolved_at"),
            "resolution_note": payload.get("aftersale_resolution_note"),
        },
        "action_bar": _order_action_bar(payload, current_user_id=current_user_id, shipment_ready=shipment is not None),
    }


def _notification_summary(record: dict[str, Any]) -> dict[str, Any]:
    payload = dict(record["payload"])
    return {
        "id": record["entity_id"],
        "user_id": payload.get("user_id"),
        "notification_type": payload.get("notification_type") or "system",
        "category": payload.get("category") or payload.get("notification_type") or "system",
        "icon_key": payload.get("icon_key") or payload.get("notification_type") or "system",
        "title": payload.get("title") or "",
        "body": payload.get("body") or "",
        "entity_type": payload.get("entity_type"),
        "entity_id": payload.get("entity_id"),
        "read_at": payload.get("read_at"),
        "cta_action": payload.get("cta_action"),
        "cta_target": payload.get("cta_target"),
        "read_state": "read" if payload.get("read_at") else "unread",
        "created_at": payload.get("created_at"),
    }


def _wallet_summary(record: dict[str, Any]) -> dict[str, Any]:
    payload = dict(record["payload"])
    return {
        "available_minor": int(payload.get("available_minor") or 0),
        "held_minor": int(payload.get("held_minor") or 0),
        "currency": payload.get("currency") or BASE_CURRENCY,
        "status": payload.get("status") or "active",
    }


def _page(page_key: str, *, title: str | None = None, subtitle: str | None = None, sections: list[dict[str, Any]] | None = None, resources: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "page_key": page_key,
        "title": title,
        "subtitle": subtitle,
        "sections": sections or [],
        "resources": resources or {},
    }


def _listings_by_status(store: MarketplaceStore, status_name: str | None = None) -> list[dict[str, Any]]:
    items = store.list_records("listing")
    if status_name:
        items = [item for item in items if item["payload"].get("status") == status_name]
    return items


def _write_order_event(
    store: MarketplaceStore,
    order_id: str,
    *,
    status_name: str,
    event_note: str,
    actor_user_id: str | None,
) -> dict[str, Any]:
    event_id = _new_id("order_event")
    payload = {
        "id": event_id,
        "order_id": order_id,
        "status": status_name,
        "event_note": event_note,
        "actor_user_id": actor_user_id,
        "occurred_at": _now(),
    }
    return store.upsert_record("order_event", event_id, payload, parent_id=order_id)


def _upsert_shipment(
    store: MarketplaceStore,
    order_id: str,
    *,
    carrier_name: str,
    tracking_no: str,
    status_name: str,
    shipped_at: str | None = None,
    estimated_delivery_at: str | None = None,
) -> dict[str, Any]:
    shipment = store.find_first("shipment", predicate=lambda item: item["payload"].get("order_id") == order_id)
    shipment_id = shipment["entity_id"] if shipment else _new_id("shipment")
    payload = dict(shipment["payload"]) if shipment else {"id": shipment_id, "order_id": order_id}
    payload.update(
        {
            "id": shipment_id,
            "order_id": order_id,
            "carrier_name": carrier_name,
            "tracking_no": tracking_no,
            "status": status_name,
            "shipped_at": shipped_at,
            "estimated_delivery_at": estimated_delivery_at,
        }
    )
    return store.upsert_record("shipment", shipment_id, payload, parent_id=order_id)


def _write_shipment_event(
    store: MarketplaceStore,
    shipment_id: str,
    *,
    event_code: str,
    event_text: str,
    event_city: str | None = None,
) -> dict[str, Any]:
    event_id = _new_id("shipment_event")
    payload = {
        "id": event_id,
        "shipment_id": shipment_id,
        "event_code": event_code,
        "event_text": event_text,
        "event_city": event_city,
        "occurred_at": _now(),
    }
    return store.upsert_record("shipment_event", event_id, payload, parent_id=shipment_id)


@router.get("/health")
def health(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return ok(request, store.health_snapshot())


@router.get("/version")
def version(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return ok(request, store.version_snapshot())


@router.get("/config/public")
def public_config(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return ok(request, store.public_config_snapshot())


@router.get("/pages/auth/login")
def page_auth_login(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return ok(request, _page(
        "auth_login",
        title="欢迎登录",
        subtitle="登录后即可管理你的商品、订单和消息。",
        sections=[
            {
                "section_type": "form",
                "section_id": "login_form",
                "title": "登录",
                "items": [
                    {"field": "identifier", "label": "账号"},
                    {"field": "password", "label": "密码"},
                ],
                "actions": [
                    {"key": "login", "title": "登录"},
                    {"key": "guest", "title": "游客进入", "enabled": True},
                ],
            }
        ],
        resources={"public_config": store.public_config_snapshot()},
    ))


@router.get("/pages/auth/register")
def page_auth_register(request: Request) -> dict[str, Any]:
    return ok(request, _page(
        "auth_register",
        title="创建账号",
        subtitle="注册后即可发布商品、查看订单与聊天记录。",
        sections=[
            {
                "section_type": "form",
                "section_id": "register_form",
                "title": "注册",
                "items": [
                    {"field": "display_name", "label": "昵称"},
                    {"field": "identifier", "label": "账号"},
                    {"field": "password", "label": "密码"},
                    {"field": "consent_version", "label": "同意版本"},
                ],
                "actions": [{"key": "register", "title": "注册"}],
            }
        ],
    ))


@router.get("/pages/me/settings")
def page_me_settings(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    addresses = [item for item in (_address_summary(record) for record in store.list_user_addresses(user["entity_id"])) if item is not None]
    default_address = _address_summary(store.default_user_address(user["entity_id"]))
    return ok(request, _page(
        "me_settings",
        title="个人资料设置",
        subtitle="管理头像、昵称、生日和隐私可见性。",
        sections=[
            {
                "section_type": "form",
                "section_id": "profile_settings",
                "title": "资料编辑",
                "items": [
                    {"field": "avatar_url", "label": "头像"},
                    {"field": "display_name", "label": "昵称"},
                    {"field": "birth_date", "label": "生日"},
                    {"field": "bio", "label": "简介"},
                    {"field": "location", "label": "所在地"},
                    {"field": "profile_visibility", "label": "可见性"},
                ],
                "actions": [{"key": "save", "title": "保存"}],
            },
            {
                "section_type": "list",
                "section_id": "shipping_addresses",
                "title": "收货地址",
                "items": addresses,
                "actions": [{"key": "add_address", "title": "新增地址"}],
            }
        ],
        resources={"profile": _profile_detail(store, user), "addresses": addresses, "default_address": default_address},
    ))


@router.post("/auth/register")
def auth_register(request: Request, payload: AuthRegisterRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    if store.user_by_identifier(payload.identifier) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该账号已存在。")

    now = _now()
    user_id = _new_id("user")
    password_hash = hashlib.sha256(payload.password.encode("utf-8")).hexdigest()
    user_record = {
        "id": user_id,
        "identifier": payload.identifier.strip(),
        "password_hash": password_hash,
        "display_name": payload.display_name.strip(),
        "avatar_url": None,
        "bio": None,
        "location": None,
        "sesame_credit_score": 600,
        "vip_level": "none",
        "profile_visibility": "public",
        "birth_date": None,
        "status": "active",
        "registered_at": now,
        "last_login_at": now,
        "password_updated_at": now,
        "account_locked_until": None,
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("user", user_id, user_record)
    store.upsert_record(
        "user_profile",
        user_id,
        {
            "id": user_id,
            "display_name": payload.display_name.strip(),
            "avatar_url": None,
            "birth_date": None,
            "age_years": None,
            "bio": None,
            "location": None,
            "sesame_credit_score": 600,
            "vip_level": "none",
            "profile_visibility": "public",
            "updated_at": now,
        },
    )
    store.upsert_record(
        "user_consent",
        consent_id := _new_id("consent"),
        {
            "id": consent_id,
            "user_id": user_id,
            "consent_type": "terms_and_privacy",
            "consent_version": payload.consent_version,
            "accepted_at": now,
            "metadata_json": {"source": "register"},
        },
        parent_id=user_id,
    )
    session = store.create_session(user_id, device_name=payload.device_name, device_platform=payload.device_platform, is_new_user=True)
    store.upsert_record(
        "login_attempt",
        _new_id("attempt"),
        {
            "id": _new_id("attempt"),
            "login_identifier": payload.identifier,
            "user_id": user_id,
            "success": True,
            "failure_reason": None,
            "ip_address": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent"),
            "occurred_at": now,
        },
    )
    user_record = store.user_record(user_id)
    return ok(request, {"user": _user_summary(store, user_record), "session": session, "profile": _profile_detail(store, user_record)})


@router.post("/auth/login")
def auth_login(request: Request, payload: AuthLoginRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_record = store.user_by_identifier(payload.identifier)
    now = _now()
    if user_record is None or not store.verify_password(user_record, payload.password):
        store.upsert_record(
            "login_attempt",
            _new_id("attempt"),
            {
                "id": _new_id("attempt"),
                "login_identifier": payload.identifier,
                "user_id": user_record["entity_id"] if user_record else None,
                "success": False,
                "failure_reason": "invalid_credentials",
                "ip_address": request.client.host if request.client else None,
                "user_agent": request.headers.get("user-agent"),
                "occurred_at": now,
            },
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="账号或密码不正确。")

    user_payload = dict(user_record["payload"])
    user_payload["last_login_at"] = now
    user_payload["updated_at"] = now
    store.upsert_record("user", user_record["entity_id"], user_payload)
    session = store.create_session(user_record["entity_id"], device_name=payload.device_name, device_platform=payload.device_platform, is_new_user=False)
    store.upsert_record(
        "login_attempt",
        _new_id("attempt"),
        {
            "id": _new_id("attempt"),
            "login_identifier": payload.identifier,
            "user_id": user_record["entity_id"],
            "success": True,
            "failure_reason": None,
            "ip_address": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent"),
            "occurred_at": now,
        },
    )
    return ok(request, {"user": _user_summary(store, user_record), "session": session, "profile": _profile_detail(store, user_record)})


@router.post("/auth/refresh")
def auth_refresh(request: Request, payload: AuthRefreshRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    session_record = store.find_first("auth_session", predicate=lambda item: item["payload"].get("refresh_token") == payload.refresh_token)
    if session_record is None or session_record["payload"].get("revoked_at"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="刷新令牌无效或已失效。")
    user_record = store.user_record(session_record["payload"]["user_id"])
    if user_record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="用户不存在。")
    store.revoke_session(session_record["payload"].get("access_token"))
    session = store.create_session(user_record["entity_id"], device_name=session_record["payload"].get("device_name"), device_platform=session_record["payload"].get("device_platform"), is_new_user=False)
    return ok(request, {"user": _user_summary(store, user_record), "session": session, "profile": _profile_detail(store, user_record)})


@router.post("/auth/logout")
def auth_logout(request: Request, payload: LogoutRequest | None = None, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    token = (payload.access_token if payload else None) or _bearer_token(request)
    session = store.revoke_session(token)
    return ok(request, {"revoked": session is not None})


@router.get("/auth/session")
def auth_session(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    token = _bearer_token(request)
    session = store.session_by_token(token)
    if session is None:
        return ok(request, _guest_auth_payload())
    user_id = session["payload"]["user_id"]
    user_record = store.user_record(user_id)
    if user_record is None:
        return ok(request, _guest_auth_payload())
    session_payload = dict(session["payload"])
    session_payload["guest_mode"] = False
    return ok(request, {"user": _user_summary(store, user_record), "session": session_payload, "profile": _profile_detail(store, user_record)})


@router.get("/users/me")
def users_me(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    return ok(request, _profile_detail(store, user))


@router.patch("/users/me")
def users_me_patch(request: Request, payload: UserProfileUpdate, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    profile = store.update_user_profile(user["entity_id"], payload.model_dump(exclude_none=True))
    return ok(request, _profile_detail(store, store.user_record(user["entity_id"])))


@router.post("/users/me/avatar")
async def users_me_avatar_upload(request: Request, file: UploadFile = File(...), store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    user_id = user["entity_id"]

    # Validate content type.
    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image files are allowed.")

    # Determine extension from content type.
    ext_map = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/gif": ".gif"}
    ext = ext_map.get(content_type, ".jpg")

    # Save file to storage/avatars/{user_id}{ext}.
    from shared.config import STORAGE_ROOT
    avatar_dir = STORAGE_ROOT / "avatars"
    avatar_dir.mkdir(parents=True, exist_ok=True)
    avatar_path = avatar_dir / f"{user_id}{ext}"
    content = await file.read()
    avatar_path.write_bytes(content)

    # Build the URL path.
    avatar_url = f"/storage/avatars/{user_id}{ext}"

    # Update user profile with the new avatar_url.
    store.update_user_profile(user_id, {"avatar_url": avatar_url})

    return ok(request, _profile_detail(store, store.user_record(user_id)))


@router.get("/users/me/stats")
def users_me_stats(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    return ok(request, store.user_stats_payload(user["entity_id"]))


@router.get("/users/me/listings")
def users_me_listings(request: Request, store: MarketplaceStore = Depends(get_store), page: int = Query(1, ge=1), page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    items = [
        _listing_summary(store, item, viewer_user_id=user_id)
        for item in store.list_records("listing")
        if item["payload"].get("seller_id") == user_id and item["payload"].get("status") != "deleted"
    ]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/users/me/favorites")
def users_me_favorites(request: Request, store: MarketplaceStore = Depends(get_store), page: int = Query(1, ge=1), page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    favorite_ids = {item["payload"].get("listing_id") for item in store.list_records("listing_favorite") if item["payload"].get("user_id") == user_id}
    items = [
        _listing_summary(store, item, viewer_user_id=user_id)
        for item in store.list_records("listing")
        if item["entity_id"] in favorite_ids and item["payload"].get("status") != "deleted"
    ]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/users/me/addresses")
def users_me_addresses(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    items = [item for item in (_address_summary(record) for record in store.list_user_addresses(user["entity_id"])) if item is not None]
    return ok(request, items)


@router.post("/users/me/addresses")
def users_me_address_create(request: Request, payload: UserAddressCreateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    address_payload = _validated_address_payload(payload.model_dump(exclude_none=True))
    address = store.create_user_address(user["entity_id"], address_payload)
    return ok(request, _address_summary(address))


@router.get("/users/me/addresses/{address_id}")
def users_me_address_detail(request: Request, address_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    address = store.get_user_address(address_id)
    if address is None or address["payload"].get("user_id") != user["entity_id"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="地址不存在。")
    return ok(request, _address_summary(address))


@router.patch("/users/me/addresses/{address_id}")
def users_me_address_update(request: Request, address_id: str, payload: UserAddressUpdateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    address = store.get_user_address(address_id)
    if address is None or address["payload"].get("user_id") != user["entity_id"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="地址不存在。")
    address_payload = _validated_address_payload(payload.model_dump(exclude_none=True), partial=True)
    updated = store.update_user_address(address_id, address_payload)
    return ok(request, _address_summary(updated))


@router.delete("/users/me/addresses/{address_id}")
def users_me_address_delete(request: Request, address_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    address = store.get_user_address(address_id)
    if address is None or address["payload"].get("user_id") != user["entity_id"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="地址不存在。")
    store.delete_user_address(address_id)
    return ok(request, {"address_id": address_id, "deleted": True})


@router.get("/users/{user_id}")
def users_detail(user_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = store.user_record(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="用户不存在。")
    return ok(None, _profile_detail(store, user))


@router.get("/users/{user_id}/followers")
def users_followers(user_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    followers = [_user_summary(store, store.user_record(item["payload"].get("follower_user_id") or "")) for item in store.list_records("user_follow") if item["payload"].get("following_user_id") == user_id]
    return ok(None, [item for item in followers if item is not None])


@router.get("/users/{user_id}/following")
def users_following(user_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    following = [_user_summary(store, store.user_record(item["payload"].get("following_user_id") or "")) for item in store.list_records("user_follow") if item["payload"].get("follower_user_id") == user_id]
    return ok(None, [item for item in following if item is not None])


@router.get("/pages/me")
def page_me(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    profile = _profile_detail(store, user)
    listings = [_listing_summary(store, item, viewer_user_id=user["entity_id"]) for item in store.list_records("listing") if item["payload"].get("seller_id") == user["entity_id"]]
    addresses = [item for item in (_address_summary(record) for record in store.list_user_addresses(user["entity_id"])) if item is not None]
    stats = store.user_stats_payload(user["entity_id"])
    return ok(request, _page(
        "me",
        title="我的",
        subtitle="查看个人资料、统计、收藏和快捷入口。",
        sections=[
            {"section_type": "profile", "section_id": "profile_card", "items": [profile]},
            {"section_type": "grid", "section_id": "services", "items": [item["payload"] for item in store.list_records("service_card")]},
            {"section_type": "list", "section_id": "my_listings", "title": "我发布的商品", "items": listings},
            {"section_type": "list", "section_id": "my_addresses", "title": "收货地址", "items": addresses},
        ],
        resources={"profile": profile, "stats": stats, "listings": listings, "addresses": addresses, "badge_summary": store.badge_summary_payload(user["entity_id"])},
    ))


@router.get("/categories")
def categories(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = [item["payload"] for item in store.list_records("category")]
    items.sort(key=lambda item: item.get("sort_order", 0))
    return ok(request, items)


@router.get("/service-catalog")
def service_catalog(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = [item["payload"] for item in store.list_records("service_card")]
    items.sort(key=lambda item: item.get("sort_order", 0))
    return ok(request, items)


@router.get("/banners")
def banners(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = [item["payload"] for item in store.list_records("banner") if item["payload"].get("active", True)]
    items.sort(key=lambda item: item.get("sort_order", 0))
    return ok(request, items)


@router.get("/pages/home")
def page_home(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    viewer_user_id = _optional_current_user_id(store, request)
    listings = [_listing_summary(store, item, viewer_user_id=viewer_user_id) for item in _listings_by_status(store, "live")]
    listings = _sort_listing_items(listings, "popular")
    banners = [item["payload"] for item in store.list_records("banner") if item["payload"].get("active", True)]
    categories = [item["payload"] for item in store.list_records("category")]
    services = [item["payload"] for item in store.list_records("service_card")]
    sections = [
        {"section_type": "hero", "section_id": "home_hero", "title": "3D 闲置好物", "subtitle": "从二手商品到 3D 展示，一站式体验。", "items": banners},
        {"section_type": "grid", "section_id": "home_categories", "title": "分类浏览", "items": categories},
        {"section_type": "list", "section_id": "home_recommendations", "title": "推荐商品", "items": listings[:6]},
        {"section_type": "list", "section_id": "home_3d_spotlight", "title": "3D 专区", "items": [item for item in listings if item.get("has_3d_preview")][:6]},
        {"section_type": "grid", "section_id": "home_services", "title": "快捷入口", "items": services},
    ]
    return ok(request, _page("home", title="首页", sections=sections, resources={"listings": listings[:10], "featured_3d": [item for item in listings if item.get("has_3d_preview")][:10], "categories": categories, "banners": banners, "services": services}))


@router.get("/home/feed")
def home_feed(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    query: str = Query(""),
    category_id: str | None = None,
    sort: str = Query("latest"),
    price_bucket: str | None = None,
    location: str | None = None,
    condition_level: str | None = None,
    only_3d: bool = False,
    only_negotiable: bool = False,
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    viewer_user_id = _optional_current_user_id(store, request)
    items = [_listing_summary(store, item, viewer_user_id=viewer_user_id) for item in _listings_by_status(store, "live")]
    items = _apply_listing_filters(
        items,
        query=query,
        category_id=category_id,
        price_bucket=price_bucket,
        location=location,
        condition_level=condition_level,
        only_3d=only_3d,
        only_negotiable=only_negotiable,
    )
    items = _sort_listing_items(items, sort)
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/pages/search")
def page_search(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    documents = store.search_documents()
    suggestions_record = store.find_first("search_suggestion")
    hot_items = [item["payload"] for item in store.list_records("search_suggestion")]
    return ok(request, _page(
        "search",
        title="搜索",
        subtitle="按分类、价格和地点筛选商品。",
        sections=[
            {"section_type": "notice", "section_id": "search_notice", "title": "搜索建议", "items": ["输入关键词即可快速找到商品"]},
            {"section_type": "list", "section_id": "search_hot", "title": "热搜", "items": hot_items},
        ],
        resources={"documents": documents, "hot_searches": hot_items, "recent_queries": list((suggestions_record or {"payload": {}})["payload"].get("recent_queries") or []), "facets": search_facets(request, store)["data"]},
    ))


@router.get("/search/suggestions")
def search_suggestions(request: Request, query: str = Query(""), store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    record = store.find_first("search_suggestion")
    suggestions = list(record["payload"].get("suggestions") or []) if record else []
    recent = list(record["payload"].get("recent_queries") or []) if record else []
    if query:
        lowered = query.lower()
        suggestions = [item for item in suggestions if lowered in item.lower() or item.startswith(query)] or suggestions
    return ok(request, {"query": query, "suggestions": suggestions, "recent_queries": recent})


@router.get("/search/facets")
def search_facets(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    listings = [_listing_summary(store, item) for item in store.list_records("listing") if item["payload"].get("status") != "deleted"]
    category_counts: dict[str, int] = {}
    location_counts: dict[str, int] = {}
    status_counts: dict[str, int] = {}
    condition_counts: dict[str, int] = {}
    prices = [listing["price"]["amount_minor"] for listing in listings]
    for listing in listings:
        category_id = listing.get("category_id")
        if category_id:
            category_counts[category_id] = category_counts.get(category_id, 0) + 1
        status_counts[listing["status"]] = status_counts.get(listing["status"], 0) + 1
        if listing.get("location"):
            location_counts[listing["location"]] = location_counts.get(listing["location"], 0) + 1
        if listing.get("condition_level"):
            key = str(listing["condition_level"])
            condition_counts[key] = condition_counts.get(key, 0) + 1
    categories = []
    for item in store.list_records("category"):
        categories.append({"id": item["entity_id"], "name": item["payload"].get("name"), "count": category_counts.get(item["entity_id"], 0)})
    facets = {
        "categories": categories,
        "locations": [{"id": name, "name": name, "count": count} for name, count in location_counts.items()],
        "price_buckets": [
            {"id": "lt_1000", "label": "1000 元以下", "count": sum(1 for price in prices if price < 100000)},
            {"id": "1000_5000", "label": "1000-5000 元", "count": sum(1 for price in prices if 100000 <= price < 500000)},
            {"id": "gte_5000", "label": "5000 元以上", "count": sum(1 for price in prices if price >= 500000)},
        ],
        "condition_levels": [{"id": key, "label": CONDITION_LABELS.get(key, key), "count": count} for key, count in condition_counts.items()],
        "toggles": [
            {"id": "only_3d", "label": "只看 3D 商品", "count": sum(1 for item in listings if item.get("has_3d_preview"))},
            {"id": "only_negotiable", "label": "只看可议价", "count": sum(1 for item in listings if item.get("is_negotiable"))},
        ],
        "sort_options": [
            {"id": "latest", "label": "最新上新"},
            {"id": "popular", "label": "人气优先"},
            {"id": "price_asc", "label": "价格从低到高"},
            {"id": "price_desc", "label": "价格从高到低"},
        ],
        "status_counts": status_counts,
    }
    return ok(request, facets)


@router.get("/listings")
def listings(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    query: str = Query(""),
    status_name: str | None = Query(None, alias="status"),
    category_id: str | None = None,
    seller_id: str | None = None,
    sort: str = Query("latest"),
    price_bucket: str | None = None,
    location: str | None = None,
    condition_level: str | None = None,
    only_3d: bool = False,
    only_negotiable: bool = False,
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    viewer_user_id = _optional_current_user_id(store, request)
    items = [
        _listing_summary(store, item, viewer_user_id=viewer_user_id)
        for item in store.list_records("listing")
        if item["payload"].get("status") != "deleted"
    ]
    if not status_name and not seller_id:
        items = [item for item in items if item["status"] == "live"]
    items = _apply_listing_filters(
        items,
        query=query,
        category_id=category_id,
        status_name=status_name,
        seller_id=seller_id,
        price_bucket=price_bucket,
        location=location,
        condition_level=condition_level,
        only_3d=only_3d,
        only_negotiable=only_negotiable,
    )
    items = _sort_listing_items(items, sort)
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/categories/{category_id}/listings")
def category_listings(request: Request, category_id: str, store: MarketplaceStore = Depends(get_store), page: int = Query(1, ge=1), page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100)) -> dict[str, Any]:
    viewer_user_id = _optional_current_user_id(store, request)
    items = [
        _listing_summary(store, item, viewer_user_id=viewer_user_id)
        for item in store.list_records("listing")
        if item["payload"].get("category_id") == category_id and item["payload"].get("status") == "live"
    ]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/pages/listings/{listing_id}")
def page_listing(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    listing = store.get_record("listing", listing_id)
    if listing is None or listing["payload"].get("status") == "deleted":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="商品不存在。")
    viewer_user_id = _optional_current_user_id(store, request)
    return ok(request, _page("listing_detail", title="商品详情", resources=_listing_detail(store, listing, viewer_user_id=viewer_user_id)))


@router.get("/listings/{listing_id}")
def listing_detail(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    listing = store.get_record("listing", listing_id)
    if listing is None or listing["payload"].get("status") == "deleted":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="商品不存在。")
    viewer_user_id = _optional_current_user_id(store, request)
    return ok(request, _listing_detail(store, listing, viewer_user_id=viewer_user_id))


@router.get("/listings/{listing_id}/media")
def listing_media(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = [_media_asset(item["payload"]) for item in store.list_records("listing_media", parent_id=listing_id)]
    return ok(request, [item for item in items if item is not None])


@router.get("/listings/{listing_id}/seller")
def listing_seller(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    listing = store.get_record("listing", listing_id)
    if listing is None or listing["payload"].get("status") == "deleted":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="商品不存在。")
    seller = _user_summary(store, store.user_record(listing["payload"].get("seller_id") or ""))
    return ok(request, seller)


@router.get("/listings/{listing_id}/specs")
def listing_specs(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = [
        {"spec_key": item["payload"].get("spec_key"), "spec_value": item["payload"].get("spec_value"), "sort_order": item["payload"].get("sort_order")}
        for item in store.list_records("listing_spec", parent_id=listing_id)
    ]
    return ok(request, items)


@router.get("/listings/{listing_id}/similar")
def listing_similar(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    listing = store.get_record("listing", listing_id)
    if listing is None or listing["payload"].get("status") == "deleted":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="商品不存在。")
    category_id = listing["payload"].get("category_id")
    viewer_user_id = _optional_current_user_id(store, request)
    items = [
        _listing_summary(store, item, viewer_user_id=viewer_user_id)
        for item in store.list_records("listing")
        if item["entity_id"] != listing_id
        and item["payload"].get("category_id") == category_id
        and item["payload"].get("status") == "live"
    ]
    return ok(request, items[:6])


@router.get("/listings/{listing_id}/inquiries")
def listing_inquiries(request: Request, listing_id: str) -> dict[str, Any]:
    return ok(request, [])


@router.get("/listings/{listing_id}/reviews")
def listing_reviews(
    request: Request,
    listing_id: str,
    store: MarketplaceStore = Depends(get_store),
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    items = [_review_summary(store, item) for item in store.list_records("review") if item["payload"].get("listing_id") == listing_id]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.post("/listings/{listing_id}/cover")
async def listing_cover_upload(
    request: Request,
    listing_id: str,
    file: UploadFile = File(...),
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    listing = _ensure_owned_listing(store, listing_id, user_id)
    payload = dict(listing["payload"])
    payload["cover_media_json"] = await _store_uploaded_cover(file, namespace=listing_id)
    payload["updated_at"] = _now()
    store.upsert_record("listing", listing_id, payload)
    return ok(request, _listing_summary(store, store.get_record("listing", listing_id)))


@router.patch("/listings/{listing_id}")
def listing_update(
    request: Request,
    listing_id: str,
    payload: ListingUpdateRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    listing = _ensure_owned_listing(store, listing_id, user_id)
    changes = payload.model_dump(exclude_none=True)
    if "title" in changes and not str(changes["title"]).strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Listing title cannot be empty.")
    if "price_minor" in changes and int(changes["price_minor"]) < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Listing price cannot be negative.")
    if "cover_media_json" in changes:
        changes["cover_media_json"] = _media_asset(changes["cover_media_json"])
    updated = dict(listing["payload"])
    updated.update(changes)
    updated["updated_at"] = _now()
    store.upsert_record("listing", listing_id, updated)
    return ok(request, _listing_summary(store, store.get_record("listing", listing_id)))


@router.delete("/listings/{listing_id}")
def listing_delete(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    listing = _ensure_owned_listing(store, listing_id, user_id)
    active_order = store.find_first(
        "order",
        predicate=lambda item: item["payload"].get("listing_id") == listing_id
        and item["payload"].get("status") not in {"completed", "cancelled"},
    )
    if active_order is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Listing cannot be deleted while it has an active order.",
        )
    payload = dict(listing["payload"])
    payload["status"] = "deleted"
    payload["updated_at"] = _now()
    store.upsert_record("listing", listing_id, payload)
    return ok(request, {"listing_id": listing_id, "deleted": True})


@router.post("/listings/{listing_id}/favorite")
def favorite_listing(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    favorite_id = f"favorite_{user_id}_{listing_id}"
    if store.get_record("listing_favorite", favorite_id) is None:
        store.upsert_record("listing_favorite", favorite_id, {"user_id": user_id, "listing_id": listing_id, "created_at": _now()}, parent_id=listing_id)
    return ok(request, {"listing_id": listing_id, "favorite": True})


@router.delete("/listings/{listing_id}/favorite")
def unfavorite_listing(request: Request, listing_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    store.delete_record("listing_favorite", f"favorite_{user_id}_{listing_id}")
    return ok(request, {"listing_id": listing_id, "favorite": False})


@router.post("/listings/drafts")
def create_listing_draft(request: Request, payload: ListingDraftCreateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    draft_id = _new_id("draft")
    record = {
        "id": draft_id,
        "seller_id": user_id,
        "category_id": payload.category_id,
        "title": payload.title,
        "subtitle": payload.subtitle,
        "description": payload.description,
        "price_minor": payload.price_minor,
        "original_price_minor": payload.original_price_minor,
        "currency": payload.currency,
        "status": "draft",
        "condition_level": payload.condition_level,
        "location_city": payload.location_city,
        "draft_payload_json": payload.draft_payload_json,
        "created_at": _now(),
        "updated_at": _now(),
    }
    store.upsert_record("listing_draft", draft_id, record, parent_id=user_id)
    return ok(request, record)


@router.get("/listings/drafts/{draft_id}")
def get_listing_draft(request: Request, draft_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    draft = store.get_record("listing_draft", draft_id)
    if draft is None or draft["payload"].get("seller_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="草稿不存在。")
    return ok(request, draft["payload"])


@router.patch("/listings/drafts/{draft_id}")
def update_listing_draft(request: Request, draft_id: str, payload: ListingDraftUpdateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    draft = store.get_record("listing_draft", draft_id)
    if draft is None or draft["payload"].get("seller_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="草稿不存在。")
    changes = payload.model_dump(exclude_none=True)
    updated = dict(draft["payload"])
    updated.update(changes)
    updated["updated_at"] = _now()
    store.upsert_record("listing_draft", draft_id, updated, parent_id=updated.get("seller_id"))
    return ok(request, updated)


@router.post("/listings/drafts/{draft_id}/publish")
def publish_listing_draft(request: Request, draft_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    draft = store.get_record("listing_draft", draft_id)
    if draft is None or draft["payload"].get("seller_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="草稿不存在。")
    draft_payload = dict(draft["payload"])
    listing_id = draft_payload.get("listing_id") or _new_id("listing")
    listing_payload = {
        "id": listing_id,
        "seller_id": draft_payload.get("seller_id"),
        "category_id": draft_payload.get("category_id"),
        "title": draft_payload.get("title") or "",
        "subtitle": draft_payload.get("subtitle"),
        "description": draft_payload.get("description") or "",
        "price_minor": draft_payload.get("price_minor") or 0,
        "original_price_minor": draft_payload.get("original_price_minor"),
        "currency": draft_payload.get("currency") or BASE_CURRENCY,
        "status": "live",
        "condition_level": draft_payload.get("condition_level"),
        "location_city": draft_payload.get("location_city"),
        "cover_media_json": draft_payload.get("cover_media_json"),
        "badges_json": draft_payload.get("badges_json") or [],
        "model_url": draft_payload.get("model_url"),
        "model_ply_url": draft_payload.get("model_ply_url"),
        "model_sog_url": draft_payload.get("model_sog_url"),
        "model_format": draft_payload.get("model_format"),
        "viewer_url": draft_payload.get("viewer_url"),
        "log_url": draft_payload.get("log_url"),
        "remote_task_id": draft_payload.get("remote_task_id"),
        "object_masking": bool(draft_payload.get("object_masking", False)),
        "quality_profile": draft_payload.get("quality_profile"),
        "published_at": _now(),
        "created_at": draft_payload.get("created_at") or _now(),
        "updated_at": _now(),
    }
    store.upsert_record("listing", listing_id, listing_payload)
    return ok(request, _listing_summary(store, store.get_record("listing", listing_id)))


@router.post("/uploads/presign")
def upload_presign(request: Request, payload: UploadPresignRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    filename = payload.filename or "upload.bin"
    kind = payload.kind or "image"
    asset_id = _new_id("asset")
    relative_url = f"/storage/uploads/{asset_id}/{filename}"
    response = UploadPresignResponse(
        asset_id=asset_id,
        upload_url=relative_url,
        public_url=relative_url,
        expires_at=_now(),
        kind=kind,
    )
    return ok(request, response.model_dump(mode="json"))


@router.post("/conversations")
def create_conversation(
    request: Request,
    payload: ConversationCreateRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    listing = _ensure_listing_exists(store, payload.listing_id)
    seller_id = listing["payload"].get("seller_id") or ""
    buyer_id = user["entity_id"]
    if not seller_id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Listing seller is missing.")
    if seller_id == buyer_id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="You cannot create a conversation for your own listing.")

    existing = _find_conversation(store, payload.listing_id, buyer_id, seller_id)
    if existing is not None:
        if payload.content_text and payload.content_text.strip():
            send_conversation_message(
                request,
                existing["entity_id"],
                SendMessageRequest(content_text=payload.content_text.strip()),
                store,
            )
        return ok(request, _conversation_detail(store, store.get_record("conversation", existing["entity_id"]) or existing, current_user_id=buyer_id))

    conversation_id = _new_id("conversation")
    now = _now()
    conversation_payload = {
        "id": conversation_id,
        "listing_id": payload.listing_id,
        "buyer_id": buyer_id,
        "seller_id": seller_id,
        "status": "active",
        "last_message_preview": None,
        "unread_count": 0,
        "updated_at": now,
        "last_message_at": None,
        "created_at": now,
    }
    store.upsert_record("conversation", conversation_id, conversation_payload)
    store.upsert_record(
        "conversation_member",
        f"member_{conversation_id}_{buyer_id}",
        {
            "id": f"member_{conversation_id}_{buyer_id}",
            "conversation_id": conversation_id,
            "user_id": buyer_id,
            "role": "buyer",
            "last_read_message_id": None,
            "unread_count": 0,
        },
        parent_id=conversation_id,
    )
    store.upsert_record(
        "conversation_member",
        f"member_{conversation_id}_{seller_id}",
        {
            "id": f"member_{conversation_id}_{seller_id}",
            "conversation_id": conversation_id,
            "user_id": seller_id,
            "role": "seller",
            "last_read_message_id": None,
            "unread_count": 0,
        },
        parent_id=conversation_id,
    )
    if payload.content_text and payload.content_text.strip():
        send_conversation_message(
            request,
            conversation_id,
            SendMessageRequest(content_text=payload.content_text.strip()),
            store,
        )
    detail = _conversation_detail(store, store.get_record("conversation", conversation_id) or {"entity_id": conversation_id, "payload": conversation_payload}, current_user_id=buyer_id)
    return ok(request, detail)


@router.get("/conversations")
def conversations(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    items = []
    for record in store.list_records("conversation"):
        payload = record["payload"]
        if user_id not in {payload.get("buyer_id"), payload.get("seller_id")}:
            continue
        items.append(_conversation_summary(store, record, current_user_id=user_id))
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/conversations/{conversation_id}")
def conversation_detail(request: Request, conversation_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="会话不存在。")
    return ok(request, _conversation_detail(store, conversation, current_user_id=user["entity_id"]))


@router.get("/conversations/{conversation_id}/messages")
def conversation_messages(
    request: Request,
    conversation_id: str,
    store: MarketplaceStore = Depends(get_store),
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")
    items = _conversation_detail(store, conversation, current_user_id=user["entity_id"])["messages"]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/pages/conversations/{conversation_id}")
def page_conversation_detail(request: Request, conversation_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    detail = conversation_detail(request, conversation_id, store)["data"]
    return ok(request, _page("conversation_detail", title="Conversation", subtitle="View message history and related item details.", resources=detail))


@router.post("/_legacy/conversations/{conversation_id}/messages")
def send_conversation_message(
    request: Request,
    conversation_id: str,
    payload: SendMessageRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="会话不存在。")
    asset = None
    if payload.asset_id:
        asset = {
            "id": payload.asset_id,
            "kind": payload.message_type if payload.message_type in {"image", "video"} else "image",
            "url": f"/storage/uploads/{payload.asset_id}",
            "thumbnail_url": None,
            "width": None,
            "height": None,
            "mime_type": None,
            "sort_order": 0,
        }
    message_payload = _append_conversation_message(
        store,
        conversation,
        sender_id=user["entity_id"],
        message_type=payload.message_type,
        content_text=payload.content_text,
        asset=asset,
        offer_id=payload.offer_id,
    )
    return ok(request, message_payload)


@router.post("/_legacy/conversations/{conversation_id}/read")
def read_conversation(
    request: Request,
    conversation_id: str,
    payload: ConversationReadRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="会话不存在。")
    user_id = user["entity_id"]
    member = store.find_first(
        "conversation_member",
        predicate=lambda item: item["payload"].get("conversation_id") == conversation_id and item["payload"].get("user_id") == user_id,
    )
    if member is not None:
        member_payload = dict(member["payload"])
        member_payload["last_read_message_id"] = payload.last_read_message_id
        member_payload["unread_count"] = 0
        store.upsert_record("conversation_member", member["entity_id"], member_payload, parent_id=conversation_id)
    conversation_payload = dict(conversation["payload"])
    conversation_payload["unread_count"] = 0
    store.upsert_record("conversation", conversation_id, conversation_payload)
    return ok(request, {"conversation_id": conversation_id, "last_read_message_id": payload.last_read_message_id, "read_at": _now()})


@router.post("/conversations/{conversation_id}/typing")
def conversation_typing(
    request: Request,
    conversation_id: str,
    payload: TypingIndicatorRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, {"conversation_id": conversation_id, "is_typing": payload.is_typing})


@router.post("/conversations/{conversation_id}/offers")
def create_conversation_offer(
    request: Request,
    conversation_id: str,
    payload: ConversationOfferCreateRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")

    conversation_payload = dict(conversation["payload"])
    listing = _ensure_listing_exists(store, conversation_payload.get("listing_id") or "")
    listing_payload = dict(listing["payload"])
    if listing_payload.get("status") != "live":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only live listings can receive offers.")
    if listing_payload.get("is_negotiable") is False:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This listing does not support offers.")
    listing_currency = listing["payload"].get("currency") or BASE_CURRENCY
    counterparty_id = (
        conversation_payload.get("seller_id")
        if user["entity_id"] == conversation_payload.get("buyer_id")
        else conversation_payload.get("buyer_id")
    )
    _cancel_active_offers(store, conversation_id)
    offer_id = _new_id("offer")
    offer_payload = {
        "id": offer_id,
        "conversation_id": conversation_id,
        "listing_id": conversation_payload.get("listing_id"),
        "proposer_id": user["entity_id"],
        "counterparty_id": counterparty_id,
        "amount_minor": payload.amount_minor,
        "currency": payload.currency or listing_currency,
        "note": payload.note.strip(),
        "status": "active",
        "created_at": _now(),
        "updated_at": _now(),
        "accepted_at": None,
    }
    store.upsert_record("conversation_offer", offer_id, offer_payload, parent_id=conversation_id)
    amount_label = f"{payload.amount_minor / 100:.2f}".rstrip("0").rstrip(".")
    _append_conversation_message(
        store,
        conversation,
        sender_id=user["entity_id"],
        message_type="offer",
        content_text=payload.note.strip() or f"出价 ￥{amount_label}",
        offer_id=offer_id,
    )
    return ok(request, {"conversation_id": conversation_id, "offer": _serialize_offer(store.get_record("conversation_offer", offer_id))})


@router.post("/conversations/{conversation_id}/offers/{offer_id}/accept")
def accept_conversation_offer(
    request: Request,
    conversation_id: str,
    offer_id: str,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    offer = store.get_record("conversation_offer", offer_id)
    if conversation is None or offer is None or offer["payload"].get("conversation_id") != conversation_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Offer not found.")
    offer_payload = dict(offer["payload"])
    if user["entity_id"] != offer_payload.get("counterparty_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the counterparty can accept this offer.")
    if offer_payload.get("status") != "active":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only active offers can be accepted.")
    offer_payload["status"] = "accepted"
    offer_payload["accepted_at"] = _now()
    offer_payload["updated_at"] = _now()
    store.upsert_record("conversation_offer", offer_id, offer_payload, parent_id=conversation_id)
    _append_conversation_message(
        store,
        conversation,
        sender_id=user["entity_id"],
        message_type="system",
        content_text="已接受本次报价，可按成交价直接下单。",
        recipient_notification=False,
    )
    return ok(request, {"conversation_id": conversation_id, "offer": _serialize_offer(store.get_record("conversation_offer", offer_id))})


@router.post("/conversations/{conversation_id}/offers/{offer_id}/reject")
def reject_conversation_offer(
    request: Request,
    conversation_id: str,
    offer_id: str,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    offer = store.get_record("conversation_offer", offer_id)
    if conversation is None or offer is None or offer["payload"].get("conversation_id") != conversation_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Offer not found.")
    offer_payload = dict(offer["payload"])
    if user["entity_id"] != offer_payload.get("counterparty_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the counterparty can reject this offer.")
    if offer_payload.get("status") != "active":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only active offers can be rejected.")
    offer_payload["status"] = "rejected"
    offer_payload["updated_at"] = _now()
    store.upsert_record("conversation_offer", offer_id, offer_payload, parent_id=conversation_id)
    _append_conversation_message(
        store,
        conversation,
        sender_id=user["entity_id"],
        message_type="system",
        content_text="已拒绝本次报价。",
        recipient_notification=False,
    )
    return ok(request, {"conversation_id": conversation_id, "offer": _serialize_offer(store.get_record("conversation_offer", offer_id))})


@router.post("/conversations/{conversation_id}/messages")
def send_conversation_message_v2(
    request: Request,
    conversation_id: str,
    payload: SendMessageRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")

    asset = None
    if payload.asset_id:
        asset = {
            "id": payload.asset_id,
            "kind": payload.message_type if payload.message_type in {"image", "video"} else "image",
            "url": f"/storage/uploads/{payload.asset_id}",
            "thumbnail_url": None,
            "width": None,
            "height": None,
            "mime_type": None,
            "sort_order": 0,
        }
    message_payload = _append_conversation_message(
        store,
        conversation,
        sender_id=user["entity_id"],
        message_type=payload.message_type,
        content_text=payload.content_text,
        asset=asset,
        offer_id=payload.offer_id,
    )
    return ok(request, message_payload)


@router.post("/conversations/{conversation_id}/read")
def read_conversation_v2(
    request: Request,
    conversation_id: str,
    payload: ConversationReadRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    conversation = store.get_record("conversation", conversation_id)
    if conversation is None or user["entity_id"] not in {conversation["payload"].get("buyer_id"), conversation["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")

    user_id = user["entity_id"]
    member = _member_record(store, conversation_id, user_id)
    if member is not None:
        member_payload = dict(member["payload"])
        member_payload["last_read_message_id"] = payload.last_read_message_id
        member_payload["unread_count"] = 0
        store.upsert_record("conversation_member", member["entity_id"], member_payload, parent_id=conversation_id)

    read_at = _now()
    for record in store.list_records("message", parent_id=conversation_id):
        message_payload = dict(record["payload"])
        if message_payload.get("sender_id") != user_id and message_payload.get("read_at") is None:
            message_payload["read_at"] = read_at
            store.upsert_record("message", record["entity_id"], message_payload, parent_id=conversation_id)

    return ok(request, {"conversation_id": conversation_id, "last_read_message_id": payload.last_read_message_id, "read_at": read_at})


@router.post("/orders")
def create_order(
    request: Request,
    payload: OrderCreateRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    buyer = _require_current_user(store, request)
    listing = _ensure_listing_exists(store, payload.listing_id)
    listing_payload = dict(listing["payload"])
    seller_id = listing_payload.get("seller_id") or ""
    buyer_id = buyer["entity_id"]
    if not seller_id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Listing seller is missing.")
    if seller_id == buyer_id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="You cannot place an order on your own listing.")
    if listing_payload.get("status") != "live":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only live listings can be ordered.")

    address = store.get_user_address(payload.address_id)
    if address is None or address["payload"].get("user_id") != buyer_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Address not found.")

    order_conversation_id = payload.conversation_id
    if order_conversation_id:
        conversation = store.get_record("conversation", order_conversation_id)
        if conversation is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")
        conversation_payload = dict(conversation["payload"])
        if (
            conversation_payload.get("listing_id") != payload.listing_id
            or conversation_payload.get("buyer_id") != buyer_id
            or conversation_payload.get("seller_id") != seller_id
        ):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Conversation does not match this order.")

    offer_record = None
    agreed_price_minor = None
    if payload.offer_id:
        offer_record = store.get_record("conversation_offer", payload.offer_id)
        if offer_record is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Offer not found.")
        offer_payload = dict(offer_record["payload"])
        if offer_payload.get("listing_id") != payload.listing_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Offer does not belong to this listing.")
        if offer_payload.get("status") != "accepted":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only accepted offers can be checked out.")
        if offer_payload.get("order_id"):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Offer already has an order.")
        if order_conversation_id and offer_payload.get("conversation_id") != order_conversation_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Offer does not belong to this conversation.")
        if buyer_id not in {offer_payload.get("proposer_id"), offer_payload.get("counterparty_id")}:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Offer does not belong to the current buyer.")
        order_conversation_id = order_conversation_id or offer_payload.get("conversation_id")
        agreed_price_minor = int(offer_payload.get("amount_minor") or 0)

    order_id = _new_id("order")
    now = _now()
    listing_price_minor = int(listing_payload.get("price_minor") or 0)
    price_minor = agreed_price_minor if agreed_price_minor is not None else listing_price_minor
    shipping_minor = int(listing_payload.get("shipping_fee_minor") or 0)
    discount_minor = max(listing_price_minor - price_minor, 0)
    total_minor = price_minor + shipping_minor
    logistics_json = {
        "carrier_name": None,
        "tracking_no": None,
        "status": "pending",
        "shipped_at": None,
        "estimated_delivery_at": None,
        "address": _address_snapshot(address),
    }
    order_payload = {
        "id": order_id,
        "order_no": f"ORD-{uuid.uuid4().hex[:8].upper()}",
        "buyer_id": buyer_id,
        "seller_id": seller_id,
        "listing_id": payload.listing_id,
        "conversation_id": order_conversation_id,
        "offer_id": payload.offer_id,
        "buyer_note": payload.buyer_note,
        "status": "pending_payment",
        "status_message": "订单已创建，等待模拟支付确认。",
        "payment_status": "pending",
        "shipping_status": "pending",
        "aftersale_status": "none",
        "payment_method": "mock_wallet",
        "provider_ref": f"mock_{order_id}",
        "currency": listing_payload.get("currency") or BASE_CURRENCY,
        "subtotal_minor": price_minor,
        "shipping_minor": shipping_minor,
        "discount_minor": discount_minor,
        "total_minor": total_minor,
        "can_confirm_receipt": False,
        "item_snapshot_json": _listing_snapshot(store, listing),
        "logistics_json": logistics_json,
        "aftersale_reason": None,
        "aftersale_requested_at": None,
        "aftersale_resolved_at": None,
        "aftersale_resolution_note": None,
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("order", order_id, order_payload)
    if offer_record is not None:
        offer_payload = dict(offer_record["payload"])
        offer_payload["order_id"] = order_id
        offer_payload["updated_at"] = now
        store.upsert_record("conversation_offer", offer_record["entity_id"], offer_payload, parent_id=offer_payload.get("conversation_id"))
    _write_order_event(store, order_id, status_name="pending_payment", event_note="订单已提交，等待完成模拟支付。", actor_user_id=buyer_id)
    _update_listing_status(store, payload.listing_id, "reserved")
    store.create_notification(
        buyer_id,
        notification_type="order",
        category="order",
        icon_key="receipt",
        title="Order created",
        body="Please confirm the mock payment to continue.",
        entity_type="order",
        entity_id=order_id,
    )
    return ok(
        request,
        _order_detail(
            store,
            store.get_record("order", order_id) or {"entity_id": order_id, "payload": order_payload},
            current_user_id=buyer_id,
        ),
    )


@router.post("/orders/{order_id}/mock-pay")
def mock_pay_order(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can confirm mock payment.")
    if order_payload.get("status") != "pending_payment":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only pending-payment orders can be paid.")

    now = _now()
    order_payload.update(
        {
            "status": "awaiting_shipment",
            "status_message": "模拟支付已确认，等待卖家发货。",
            "payment_status": "paid",
            "shipping_status": "awaiting_shipment",
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    _write_order_event(store, order_id, status_name="awaiting_shipment", event_note="模拟支付已完成，等待卖家发货。", actor_user_id=user["entity_id"])
    total_minor = int(order_payload.get("total_minor") or 0)
    buyer_id = order_payload.get("buyer_id")
    seller_id = order_payload.get("seller_id")
    if buyer_id:
        store.append_wallet_transaction(buyer_id, transaction_type="purchase", amount_minor=-total_minor, reference_type="order", reference_id=order_id)
    if seller_id:
        store.append_wallet_transaction(seller_id, transaction_type="incoming_hold", amount_minor=total_minor, reference_type="order", reference_id=order_id, status="held")
        store.create_notification(
            seller_id,
            notification_type="order",
            category="order",
            icon_key="paid",
            title="Buyer has paid",
            body="The order is now waiting for shipment.",
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.get("/orders")
def orders(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    items = []
    for record in store.list_records("order"):
        payload = record["payload"]
        if user_id not in {payload.get("buyer_id"), payload.get("seller_id")}:
            continue
        items.append(_order_summary(store, record, current_user_id=user_id))
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/orders/{order_id}")
def order_detail(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = store.get_record("order", order_id)
    if order is None or user["entity_id"] not in {order["payload"].get("buyer_id"), order["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="订单不存在。")
    return ok(request, _order_detail(store, order, current_user_id=user["entity_id"]))


@router.get("/orders/{order_id}/timeline")
def order_timeline(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = store.get_record("order", order_id)
    if order is None or user["entity_id"] not in {order["payload"].get("buyer_id"), order["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="订单不存在。")
    return ok(request, _order_detail(store, order, current_user_id=user["entity_id"])["timeline"])


@router.get("/orders/{order_id}/shipment")
def order_shipment(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = store.get_record("order", order_id)
    if order is None or user["entity_id"] not in {order["payload"].get("buyer_id"), order["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="订单不存在。")
    return ok(request, _order_detail(store, order, current_user_id=user["entity_id"])["receipt"]["shipment"])


@router.get("/orders/{order_id}/receipt")
def order_receipt(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    if user["entity_id"] not in {order["payload"].get("buyer_id"), order["payload"].get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found.")
    return ok(request, _order_detail(store, order, current_user_id=user["entity_id"])["receipt"])


@router.post("/orders/{order_id}/ship")
def ship_order(
    request: Request,
    order_id: str,
    payload: OrderShipRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("seller_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the seller can ship this order.")
    if order_payload.get("status") != "awaiting_shipment":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only awaiting-shipment orders can be shipped.")
    carrier_name = payload.carrier_name.strip()
    tracking_no = payload.tracking_no.strip()
    if not carrier_name or not tracking_no:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="物流公司和运单号不能为空。")

    shipped_at = _now()
    logistics_json = dict(order_payload.get("logistics_json") or {})
    logistics_json.update(
        {
            "carrier_name": carrier_name,
            "tracking_no": tracking_no,
            "status": "shipped",
            "shipped_at": shipped_at,
            "estimated_delivery_at": payload.estimated_delivery_at,
        }
    )
    order_payload.update(
        {
            "status": "shipped",
            "status_message": "卖家已发货，等待买家确认收货。",
            "shipping_status": "shipped",
            "can_confirm_receipt": True,
            "logistics_json": logistics_json,
            "updated_at": shipped_at,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    shipment = _upsert_shipment(
        store,
        order_id,
        carrier_name=carrier_name,
        tracking_no=tracking_no,
        status_name="shipped",
        shipped_at=shipped_at,
        estimated_delivery_at=payload.estimated_delivery_at,
    )
    _write_shipment_event(store, shipment["entity_id"], event_code="shipped", event_text="卖家已填写物流信息。")
    _write_order_event(store, order_id, status_name="shipped", event_note="卖家已发货，物流信息已生成。", actor_user_id=user["entity_id"])
    buyer_id = order_payload.get("buyer_id")
    if buyer_id:
        store.create_notification(
            buyer_id,
            notification_type="order",
            category="order",
            icon_key="shipping",
            title="Order shipped",
            body=f"Tracking {payload.tracking_no} is now available.",
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/confirm-receipt")
def confirm_receipt_v2(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can confirm receipt.")
    if order_payload.get("status") != "shipped":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only shipped orders can be completed.")

    now = _now()
    order_payload.update(
        {
            "status": "completed",
            "status_message": "交易已完成，欢迎为本次订单评价。",
            "shipping_status": "delivered",
            "can_confirm_receipt": False,
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    shipment = store.find_first("shipment", predicate=lambda item: item["payload"].get("order_id") == order_id)
    if shipment is not None:
        shipment_payload = dict(shipment["payload"])
        shipment_payload["status"] = "delivered"
        store.upsert_record("shipment", shipment["entity_id"], shipment_payload, parent_id=order_id)
        _write_shipment_event(store, shipment["entity_id"], event_code="delivered", event_text="买家已确认收货。")
    _write_order_event(store, order_id, status_name="completed", event_note="买家已确认收货，交易完成。", actor_user_id=user["entity_id"])
    listing_id = order_payload.get("listing_id")
    if listing_id:
        _update_listing_status(store, listing_id, "sold")
    seller_id = order_payload.get("seller_id")
    if seller_id:
        total_minor = int(order_payload.get("total_minor") or 0)
        store.append_wallet_transaction(seller_id, transaction_type="sale_income", amount_minor=total_minor, reference_type="order", reference_id=order_id)
        store.create_notification(
            seller_id,
            notification_type="order",
            category="order",
            icon_key="success",
            title="Order completed",
            body="The buyer confirmed receipt.",
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/cancel")
def cancel_order_v2(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] not in {order_payload.get("buyer_id"), order_payload.get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found.")
    if user["entity_id"] != order_payload.get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can cancel an unpaid order.")
    if order_payload.get("status") != "pending_payment":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="已支付订单不能直接取消，请申请退款。")

    now = _now()
    order_payload.update(
        {
            "status": "cancelled",
            "status_message": "订单已取消。",
            "payment_status": "pending",
            "shipping_status": "cancelled",
            "can_confirm_receipt": False,
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    _write_order_event(store, order_id, status_name="cancelled", event_note="订单已取消，商品恢复可购买。", actor_user_id=user["entity_id"])
    listing_id = order_payload.get("listing_id")
    if listing_id:
        _update_listing_status(store, listing_id, "live")
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/refund-request")
def request_order_refund(
    request: Request,
    order_id: str,
    payload: OrderRefundRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can request a refund.")
    if order_payload.get("status") not in {"awaiting_shipment", "shipped"}:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only awaiting-shipment or shipped orders can request a refund.")

    now = _now()
    order_payload.update(
        {
            "status": "refund_requested",
            "status_message": "退款申请已提交，等待卖家处理。",
            "payment_status": "refunding",
            "aftersale_status": "refund_requested",
            "aftersale_reason": payload.reason.strip(),
            "aftersale_requested_at": now,
            "can_confirm_receipt": False,
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    _write_order_event(store, order_id, status_name="refund_requested", event_note=payload.reason.strip() or "买家已提交退款申请，等待卖家处理。", actor_user_id=user["entity_id"])
    seller_id = order_payload.get("seller_id")
    if seller_id:
        store.create_notification(
            seller_id,
            notification_type="order",
            category="order",
            icon_key="refund",
            title="Refund requested",
            body=payload.reason.strip() or "The buyer requested a refund before shipment.",
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/approve-refund")
def approve_order_refund(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("seller_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the seller can approve a refund.")
    if order_payload.get("status") != "refund_requested":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only refund-requested orders can be approved.")

    now = _now()
    order_payload.update(
        {
            "status": "refunded",
            "status_message": "退款已完成。",
            "payment_status": "refunded",
            "shipping_status": "cancelled",
            "aftersale_status": "refunded",
            "aftersale_resolved_at": now,
            "aftersale_resolution_note": "卖家同意退款。",
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    _write_order_event(store, order_id, status_name="refunded", event_note="卖家同意退款，款项已退回买家账户。", actor_user_id=user["entity_id"])
    listing_id = order_payload.get("listing_id")
    if listing_id:
        _update_listing_status(store, listing_id, "live")
    buyer_id = order_payload.get("buyer_id")
    total_minor = int(order_payload.get("total_minor") or 0)
    if buyer_id:
        store.append_wallet_transaction(buyer_id, transaction_type="refund", amount_minor=total_minor, reference_type="order", reference_id=order_id)
        store.create_notification(
            buyer_id,
            notification_type="order",
            category="order",
            icon_key="refund",
            title="Refund completed",
            body="The seller approved your refund request.",
            entity_type="order",
            entity_id=order_id,
        )
    seller_id = order_payload.get("seller_id")
    if seller_id:
        store.append_wallet_transaction(seller_id, transaction_type="refund_out", amount_minor=-total_minor, reference_type="order", reference_id=order_id)
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/reject-refund")
def reject_order_refund(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("seller_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the seller can reject a refund.")
    if order_payload.get("status") != "refund_requested":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only refund-requested orders can be rejected.")

    now = _now()
    order_payload.update(
        {
            "status": "disputed",
            "status_message": "卖家已拒绝退款，订单进入纠纷处理。",
            "payment_status": "paid",
            "aftersale_status": "disputed",
            "aftersale_resolved_at": now,
            "aftersale_resolution_note": "卖家拒绝退款。",
            "updated_at": now,
        }
    )
    store.upsert_record("order", order_id, order_payload)
    _write_order_event(store, order_id, status_name="disputed", event_note="卖家拒绝退款，订单进入纠纷处理。", actor_user_id=user["entity_id"])
    buyer_id = order_payload.get("buyer_id")
    if buyer_id:
        store.create_notification(
            buyer_id,
            notification_type="order",
            category="order",
            icon_key="warning",
            title="Refund rejected",
            body="The seller rejected the refund request. The order is now disputed.",
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/orders/{order_id}/dispute")
def dispute_order(
    request: Request,
    order_id: str,
    payload: OrderDisputeRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] not in {order_payload.get("buyer_id"), order_payload.get("seller_id")}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found.")
    if order_payload.get("status") not in {"refund_requested", "shipped"}:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only shipped or refund-requested orders can be disputed.")
    order_payload["status"] = "disputed"
    order_payload["status_message"] = "订单已进入平台纠纷处理。"
    order_payload["aftersale_status"] = "disputed"
    order_payload["aftersale_reason"] = payload.reason.strip() or order_payload.get("aftersale_reason")
    order_payload["can_confirm_receipt"] = False
    order_payload["updated_at"] = _now()
    store.upsert_record("order", order_id, order_payload)
    note = payload.reason.strip() or "A dispute was opened for the order."
    _write_order_event(store, order_id, status_name="disputed", event_note=note, actor_user_id=user["entity_id"])
    other_user_id = (
        order_payload.get("seller_id")
        if user["entity_id"] == order_payload.get("buyer_id")
        else order_payload.get("buyer_id")
    )
    if other_user_id:
        store.create_notification(
            other_user_id,
            notification_type="order",
            category="order",
            icon_key="warning",
            title="Order dispute opened",
            body=note,
            entity_type="order",
            entity_id=order_id,
        )
    return ok(request, _order_detail(store, store.get_record("order", order_id) or order, current_user_id=user["entity_id"]))


@router.post("/_legacy/orders/{order_id}/confirm-receipt")
def confirm_receipt(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return confirm_receipt_v2(request, order_id, store)


@router.post("/_legacy/orders/{order_id}/cancel")
def cancel_order(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return cancel_order_v2(request, order_id, store)


@router.get("/reviews")
def reviews(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    listing_id: str | None = None,
    order_id: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    items = []
    for record in store.list_records("review"):
        payload = record["payload"]
        if listing_id and payload.get("listing_id") != listing_id:
            continue
        if order_id and payload.get("order_id") != order_id:
            continue
        items.append(_review_summary(store, record))
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/reviews/tags")
def review_tags(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    items = []
    for record in store.list_records("review_tag"):
        payload = record["payload"]
        if payload.get("active", True):
            items.append(
                {
                    "id": record["entity_id"],
                    "tag_key": payload.get("tag_key"),
                    "display_name": payload.get("display_name"),
                    "tag_group": payload.get("tag_group"),
                }
            )
    return ok(request, items)


@router.get("/orders/{order_id}/review-draft")
def order_review_draft(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    if user["entity_id"] != order["payload"].get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can review this order.")
    if order["payload"].get("status") != "completed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only completed orders can be reviewed.")
    draft = store.find_first(
        "review_draft",
        predicate=lambda item: item["payload"].get("user_id") == user["entity_id"] and item["payload"].get("order_id") == order_id,
    )
    if draft is None:
        payload = {
            "id": _new_id("review_draft"),
            "user_id": user["entity_id"],
            "order_id": order_id,
            "listing_id": order["payload"].get("listing_id"),
            "rating": None,
            "tags": [],
            "content": "",
            "media_asset_ids": [],
            "anonymity_enabled": False,
            "created_at": _now(),
            "updated_at": _now(),
        }
        draft = store.upsert_record("review_draft", payload["id"], payload, parent_id=user["entity_id"])
    return ok(request, draft["payload"])


@router.patch("/orders/{order_id}/review-draft")
def update_order_review_draft(
    request: Request,
    order_id: str,
    payload: ReviewDraftUpdateRequest,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, order_id)
    if user["entity_id"] != order["payload"].get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can review this order.")
    if order["payload"].get("status") != "completed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only completed orders can be reviewed.")
    draft = store.find_first(
        "review_draft",
        predicate=lambda item: item["payload"].get("user_id") == user["entity_id"] and item["payload"].get("order_id") == order_id,
    )
    if draft is None:
        draft_id = _new_id("review_draft")
        draft = store.upsert_record(
            "review_draft",
            draft_id,
            {
                "id": draft_id,
                "user_id": user["entity_id"],
                "order_id": order_id,
                "listing_id": None,
                "rating": None,
                "tags": [],
                "content": "",
                "media_asset_ids": [],
                "anonymity_enabled": False,
                "created_at": _now(),
                "updated_at": _now(),
            },
            parent_id=user["entity_id"],
        )
    updated = dict(draft["payload"])
    updated.update(payload.model_dump(exclude_none=True))
    updated["updated_at"] = _now()
    store.upsert_record("review_draft", draft["entity_id"], updated, parent_id=user["entity_id"])
    return ok(request, updated)


@router.post("/reviews")
def create_review_v2(request: Request, payload: ReviewCreateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    order = _ensure_order_exists(store, payload.order_id)
    order_payload = dict(order["payload"])
    if user["entity_id"] != order_payload.get("buyer_id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the buyer can review this order.")
    if order_payload.get("status") != "completed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Only completed orders can be reviewed.")
    existing = store.find_first(
        "review",
        predicate=lambda item: item["payload"].get("order_id") == payload.order_id and item["payload"].get("reviewer_user_id") == user["entity_id"],
    )
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This order has already been reviewed.")

    review_id = _new_id("review")
    now = _now()
    review_payload = {
        "id": review_id,
        "order_id": payload.order_id,
        "listing_id": payload.listing_id or order_payload.get("listing_id"),
        "reviewer_user_id": user["entity_id"],
        "seller_user_id": order_payload.get("seller_id"),
        "rating": payload.rating,
        "content": payload.content,
        "is_anonymous": payload.anonymity_enabled,
        "status": "published",
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("review", review_id, review_payload)
    for index, asset_id in enumerate(payload.media_asset_ids):
        store.upsert_record(
            "review_media",
            f"review_media_{review_id}_{index + 1}",
            {
                "id": f"review_media_{review_id}_{index + 1}",
                "review_id": review_id,
                "asset": {
                    "id": asset_id,
                    "kind": "image",
                    "url": f"/storage/uploads/{asset_id}",
                    "thumbnail_url": None,
                    "width": None,
                    "height": None,
                    "mime_type": None,
                    "sort_order": index,
                },
                "sort_order": index,
            },
            parent_id=review_id,
        )
    for index, tag_name in enumerate(payload.tags):
        tag_record = store.find_first(
            "review_tag",
            predicate=lambda item, name=tag_name: item["payload"].get("tag_key") == name or item["payload"].get("display_name") == name,
        )
        if tag_record is None:
            tag_id = _new_id("review_tag")
            tag_record = store.upsert_record(
                "review_tag",
                tag_id,
                {
                    "id": tag_id,
                    "tag_key": tag_name,
                    "display_name": tag_name,
                    "tag_group": "custom",
                    "active": True,
                },
            )
        store.upsert_record(
            "review_tag_link",
            f"review_tag_link_{review_id}_{index + 1}",
            {"id": f"review_tag_link_{review_id}_{index + 1}", "review_id": review_id, "tag_id": tag_record["entity_id"]},
            parent_id=review_id,
        )
    store.create_notification(
        order_payload.get("seller_id") or "",
        notification_type="review",
        title="New review received",
        body="A buyer has submitted a review for an order.",
        entity_type="review",
        entity_id=review_id,
    )
    _write_order_event(store, payload.order_id, status_name="reviewed", event_note="Buyer submitted a review.", actor_user_id=user["entity_id"])
    return ok(request, _review_summary(store, store.get_record("review", review_id) or {"entity_id": review_id, "payload": review_payload}))


@router.post("/_legacy/reviews")
def create_review(request: Request, payload: ReviewCreateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    review_id = _new_id("review")
    now = _now()
    user = _require_current_user(store, request)
    order = store.get_record("order", payload.order_id)
    seller_user_id = None
    if order is not None:
        seller_user_id = order["payload"].get("seller_id")
    elif payload.listing_id:
        listing = store.get_record("listing", payload.listing_id)
        seller_user_id = listing["payload"].get("seller_id") if listing else None
    review_payload = {
        "id": review_id,
        "order_id": payload.order_id,
        "listing_id": payload.listing_id,
        "reviewer_user_id": user["entity_id"],
        "seller_user_id": seller_user_id,
        "rating": payload.rating,
        "content": payload.content,
        "is_anonymous": payload.anonymity_enabled,
        "status": "published",
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("review", review_id, review_payload)
    for index, asset_id in enumerate(payload.media_asset_ids):
        store.upsert_record(
            "review_media",
            f"review_media_{review_id}_{index + 1}",
            {
                "id": f"review_media_{review_id}_{index + 1}",
                "review_id": review_id,
                "asset": {
                    "id": asset_id,
                    "kind": "image",
                    "url": f"/storage/uploads/{asset_id}",
                    "thumbnail_url": None,
                    "width": None,
                    "height": None,
                    "mime_type": None,
                    "sort_order": index,
                },
                "sort_order": index,
            },
            parent_id=review_id,
        )
    for index, tag_name in enumerate(payload.tags):
        tag_record = store.find_first("review_tag", predicate=lambda item, name=tag_name: item["payload"].get("tag_key") == name or item["payload"].get("display_name") == name)
        if tag_record is None:
            tag_record = {
                "entity_id": f"review_tag_custom_{index + 1}",
                "payload": {
                    "id": f"review_tag_custom_{index + 1}",
                    "tag_key": tag_name,
                    "display_name": tag_name,
                    "tag_group": "custom",
                    "active": True,
                },
            }
            store.upsert_record("review_tag", tag_record["entity_id"], tag_record["payload"])
        store.upsert_record(
            "review_tag_link",
            f"review_tag_link_{review_id}_{index + 1}",
            {"review_id": review_id, "tag_id": tag_record["entity_id"]},
            parent_id=review_id,
        )
    return ok(request, _review_summary(store, store.get_record("review", review_id) or {"entity_id": review_id, "payload": review_payload}))


@router.get("/reviews/{review_id}")
def review_detail(request: Request, review_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    review = store.get_record("review", review_id)
    if review is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="评论不存在。")
    return ok(request, _review_summary(store, review))


@router.post("/reviews/drafts")
def create_review_draft(request: Request, payload: ReviewCreateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    draft_id = _new_id("review_draft")
    now = _now()
    draft_payload = {
        "id": draft_id,
        "user_id": user["entity_id"],
        "order_id": payload.order_id,
        "listing_id": payload.listing_id,
        "rating": payload.rating,
        "tags": list(payload.tags),
        "content": payload.content,
        "media_asset_ids": list(payload.media_asset_ids),
        "anonymity_enabled": payload.anonymity_enabled,
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("review_draft", draft_id, draft_payload, parent_id=user["entity_id"])
    return ok(request, draft_payload)


@router.get("/reviews/drafts/{draft_id}")
def review_draft_detail(request: Request, draft_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    draft = store.get_record("review_draft", draft_id)
    if draft is None or (draft["payload"].get("user_id") or draft["parent_id"]) != user["entity_id"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="评论草稿不存在。")
    return ok(request, draft["payload"])


@router.patch("/reviews/drafts/{draft_id}")
def review_draft_update(request: Request, draft_id: str, payload: ReviewDraftUpdateRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user = _require_current_user(store, request)
    draft = store.get_record("review_draft", draft_id)
    if draft is None or (draft["payload"].get("user_id") or draft["parent_id"]) != user["entity_id"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="评论草稿不存在。")
    updated = dict(draft["payload"])
    updated.update(payload.model_dump(exclude_none=True))
    updated["updated_at"] = _now()
    store.upsert_record("review_draft", draft_id, updated, parent_id=user["entity_id"])
    return ok(request, updated)


@router.get("/wallet")
def wallet(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    account = store.find_first("wallet_account", predicate=lambda item: item["payload"].get("user_id") == user_id)
    transactions = []
    if account is not None:
        transactions = [
            {
                "id": item["entity_id"],
                "wallet_account_id": item["payload"].get("wallet_account_id"),
                "transaction_type": item["payload"].get("transaction_type") or "unknown",
                "amount": _money(item["payload"].get("amount_minor"), item["payload"].get("currency")),
                "reference_type": item["payload"].get("reference_type"),
                "reference_id": item["payload"].get("reference_id"),
                "status": item["payload"].get("status") or "posted",
                "created_at": item["payload"].get("created_at"),
            }
            for item in store.list_records("wallet_transaction", parent_id=account["entity_id"])
        ]
    return ok(request, {"account": _wallet_summary(account) if account else None, "transactions": transactions})


@router.get("/wallet/summary")
def wallet_summary_alias(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return wallet(request, store)


@router.get("/wallet/transactions")
def wallet_transactions(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    account = store.find_first("wallet_account", predicate=lambda item: item["payload"].get("user_id") == user_id)
    if account is None:
        return ok(request, [])
    transactions = [
        {
            "id": item["entity_id"],
            "wallet_account_id": item["payload"].get("wallet_account_id"),
            "transaction_type": item["payload"].get("transaction_type") or "unknown",
            "amount": _money(item["payload"].get("amount_minor"), item["payload"].get("currency")),
            "reference_type": item["payload"].get("reference_type"),
            "reference_id": item["payload"].get("reference_id"),
            "status": item["payload"].get("status") or "posted",
            "created_at": item["payload"].get("created_at"),
        }
        for item in store.list_records("wallet_transaction", parent_id=account["entity_id"])
    ]
    return ok(request, transactions)


@router.get("/membership/plans")
def membership_plans(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    plans = []
    for item in store.list_records("membership_plan"):
        payload = item["payload"]
        plans.append(
            {
                "id": item["entity_id"],
                "plan_key": payload.get("plan_key") or "",
                "title": payload.get("title") or "",
                "price": _money(payload.get("price_minor"), payload.get("currency")),
                "benefits_json": list(payload.get("benefits_json") or []),
                "active": bool(payload.get("active", True)),
            }
        )
    return ok(request, plans)


@router.get("/membership/subscription")
def membership_subscription(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    subscription = store.find_first("membership_subscription", predicate=lambda item: item["payload"].get("user_id") == user_id)
    if subscription is None:
        return ok(request, None)
    plan = store.get_record("membership_plan", subscription["payload"].get("plan_id") or "")
    plan_payload = plan["payload"] if plan else {}
    return ok(request, {
        "id": subscription["entity_id"],
        "user_id": subscription["payload"].get("user_id"),
        "plan": {
            "id": plan["entity_id"] if plan else None,
            "plan_key": plan_payload.get("plan_key"),
            "title": plan_payload.get("title"),
            "price": _money(plan_payload.get("price_minor"), plan_payload.get("currency")),
            "benefits_json": list(plan_payload.get("benefits_json") or []),
            "active": bool(plan_payload.get("active", True)),
        },
        "status": subscription["payload"].get("status") or "active",
        "started_at": subscription["payload"].get("started_at"),
        "expires_at": subscription["payload"].get("expires_at"),
    })


@router.get("/memberships/current")
def membership_current_alias(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return membership_subscription(request, store)


@router.post("/membership/upgrade")
def membership_upgrade(request: Request, payload: MembershipUpgradeRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    plan = store.find_first("membership_plan", predicate=lambda item: item["payload"].get("plan_key") == payload.plan_key)
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="会员方案不存在。")
    user_id = _require_current_user_id(store, request)
    subscription_id = f"subscription_{user_id}"
    now = _now()
    subscription_payload = {
        "id": subscription_id,
        "user_id": user_id,
        "plan_id": plan["entity_id"],
        "status": "active",
        "started_at": now,
        "expires_at": None,
        "created_at": now,
        "updated_at": now,
    }
    store.upsert_record("membership_subscription", subscription_id, subscription_payload, parent_id=user_id)
    price_minor = int(plan["payload"].get("price_minor") or 0)
    if price_minor:
        store.append_wallet_transaction(
            user_id,
            transaction_type="membership_upgrade",
            amount_minor=-price_minor,
            reference_type="membership_plan",
            reference_id=plan["entity_id"],
        )
    store.create_notification(
        user_id,
        notification_type="membership",
        title="Membership updated",
        body=f"You are now on the {plan['payload'].get('title') or payload.plan_key} plan.",
        entity_type="membership_subscription",
        entity_id=subscription_id,
    )
    return ok(request, {
        "id": subscription_id,
        "user_id": user_id,
        "plan": {
            "id": plan["entity_id"],
            "plan_key": plan["payload"].get("plan_key"),
            "title": plan["payload"].get("title"),
            "price": _money(plan["payload"].get("price_minor"), plan["payload"].get("currency")),
            "benefits_json": list(plan["payload"].get("benefits_json") or []),
            "active": bool(plan["payload"].get("active", True)),
        },
        "status": "active",
        "started_at": now,
        "expires_at": None,
    })


@router.get("/notifications")
def notifications(
    request: Request,
    store: MarketplaceStore = Depends(get_store),
    page: int = Query(1, ge=1),
    page_size: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=100),
) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    items = [_notification_summary(item) for item in store.list_records("notification") if item["payload"].get("user_id") == user_id]
    page_items, page_meta = store.paginate(items, page=page, page_size=page_size)
    return ok(request, page_items, page=page_meta)


@router.get("/badges/summary")
def badge_summary(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    return ok(request, store.badge_summary_payload(user_id))


@router.get("/notifications/badge")
def notification_badge(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    return badge_summary(request, store)


@router.post("/notifications/read")
def read_notifications(request: Request, payload: NotificationReadRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    read_at = payload.read_at or _now()
    updated_count = 0
    for item in store.list_records("notification"):
        if item["payload"].get("user_id") != user_id or item["payload"].get("read_at") is not None:
            continue
        payload_dict = dict(item["payload"])
        payload_dict["read_at"] = read_at
        store.upsert_record("notification", item["entity_id"], payload_dict)
        updated_count += 1
    return ok(request, {"read_count": updated_count, "read_at": read_at})


@router.post("/notifications/read-all")
def read_notifications_alias(
    request: Request,
    payload: NotificationReadRequest | None = None,
    store: MarketplaceStore = Depends(get_store),
) -> dict[str, Any]:
    return read_notifications(request, payload or NotificationReadRequest(), store)


@router.patch("/notifications/{notification_id}/read")
def read_notification(request: Request, notification_id: str, payload: NotificationReadRequest, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    user_id = _require_current_user_id(store, request)
    notification = store.get_record("notification", notification_id)
    if notification is None or notification["payload"].get("user_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="通知不存在。")
    updated = dict(notification["payload"])
    updated["read_at"] = payload.read_at or _now()
    store.upsert_record("notification", notification_id, updated)
    return ok(request, updated)


@router.get("/pages/orders")
def page_orders(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, _page("orders", title="订单中心", subtitle="查看买卖双方的订单状态与物流进度。", resources={"orders": orders(request, store, page=1, page_size=DEFAULT_PAGE_SIZE)["data"]}))


@router.get("/pages/orders/{order_id}")
def page_order_detail(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    order = order_detail(request, order_id, store)["data"]
    return ok(request, _page("order_detail", title="订单详情", subtitle="查看支付、物流与收货进度。", resources=order))


@router.get("/pages/orders/{order_id}/success")
def page_order_success(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    order = order_detail(request, order_id, store)["data"]
    return ok(
        request,
        _page(
            "order_success",
            title="Order placed",
            subtitle="The order is now waiting for the seller to ship it.",
            resources=order,
        ),
    )


@router.get("/pages/reviews/{order_id}")
def page_review_order(request: Request, order_id: str, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    order = order_detail(request, order_id, store)["data"]
    draft = order_review_draft(request, order_id, store)["data"]
    tags = review_tags(request, store)["data"]
    return ok(
        request,
        _page(
            "review_order",
            title="Review order",
            subtitle="Rate the completed order and leave structured feedback.",
            resources={"order": order, "draft": draft, "tags": tags},
        ),
    )


@router.get("/pages/wallet")
def page_wallet(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, _page("wallet", title="钱包", subtitle="查看余额、冻结金额和资金流水。", resources=wallet(request, store)["data"]))


@router.get("/pages/membership")
def page_membership(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, _page("membership", title="会员中心", subtitle="升级会员以获得推荐、展示和客服权益。", resources={"plans": membership_plans(request, store)["data"], "subscription": membership_subscription(request, store)["data"]}))


@router.get("/pages/messages")
def page_messages(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, _page("messages", title="消息", subtitle="和买家卖家保持沟通。", resources={"conversations": conversations(request, store, page=1, page_size=DEFAULT_PAGE_SIZE)["data"]}))


@router.get("/pages/notifications")
def page_notifications(request: Request, store: MarketplaceStore = Depends(get_store)) -> dict[str, Any]:
    _require_current_user_id(store, request)
    return ok(request, _page("notifications", title="通知", subtitle="查看订单、消息和系统通知。", resources={"notifications": notifications(request, store, page=1, page_size=DEFAULT_PAGE_SIZE)["data"], "badge": badge_summary(request, store)["data"]}))
