# 3dv-junk-mart 电商化落地计划

## Summary
- 当前仓库已经形成 `Flutter app + FastAPI 业务后端 + 远程 3DGS 训练服务 + 本地 viewer` 的完整骨架，真正可用的闭环是“登录/游客进入 -> 发布 3D 任务 -> 远程训练 -> Viewer 校准 -> 发布 listing -> 首页/详情查看 3D 商品”。
- 主项目相较 `3DGS-Marketplace` 的新增重点在于：本地业务后端、SQLite 业务存储、基础电商资源模型、个人资料编辑、与远程训练服务的联通；参考仓库主要提供 3DGS 发布链路，不包含完整电商成品。
- 当前最关键的真实现状是：后端电商 API 面已经铺开，但前端只接通了首页/搜索/详情/发布流/个人资料，消息、下单、订单、评价、钱包、会员、通知仍未形成真实前台闭环。
- 当前最关键的真实风险是：`/health` 依赖默认用户导致空库首次启动会 500；3DGS 任务创建/启动/发布未强制登录；guest 模式能进壳但没有完整只读降级；训练服务 URL 依赖运行时环境，当前默认 `127.0.0.1:9000`，与实际远程服务配置容易漂移。
- 当前维护性风险也很高：`backend/app/routes/marketplace.py`、`backend/app/services/marketplace_store.py`、`app/lib/features/reconstructions/reconstruction_publish_flow_page.dart` 都已超过千行，后续实现应优先在现架构上补齐功能，不做大规模重构拖慢交付。

## Current State
- 已有能力：登录/注册、游客进入、个人资料编辑与头像上传、商品列表/详情、3DGS 任务库、训练启动/取消/Mask/Viewer 校准/发布、Viewer 代理访问、SQLite 持久化、远程 trainer 客户端。
- 后端已存在但前端未接通的能力：地址 CRUD、收藏、会话详情/发消息/已读、订单查询/取消/确认收货、评价草稿/提交、钱包、会员、通知、页面 bootstrap。
- 明确未完成：创建订单、卖家发货、创建会话、聊天列表/详情前台、订单详情/支付成功页、评价页、通知页、钱包页、会员页、搜索 facets 的真实接入、guest 只读约束、任务按用户隔离。
- 当前真实数据状态只支持“纯空市场 + 少量个人实跑数据”，没有分类/Banner/服务卡/会员方案/评价标签等平台元数据；这不冲突于“纯空市场”目标，但需要补齐平台配置种子。
- 当前自动化基线失真：部署测试缺少 `deploy` 工件直接失败；后端矩阵测试仍假设 demo seed 用户/商品/订单存在；Flutter widget test 仍绑定旧英文文案和旧页面结构。

## Public API And Behavior Changes
- 保持 `/api/v1` 不变，现有 Flutter 已消费的接口继续可用；采用“补充缺失接口 + 增加别名 + 修正行为”而不是破坏式改名。
- 新增或补齐接口：`POST /conversations`、`GET /conversations/{conversation_id}/messages`、`GET /pages/conversations/{conversation_id}`、`POST /orders`、`POST /orders/{order_id}/ship`、`GET /orders/{order_id}/receipt`、`POST /orders/{order_id}/dispute`、`GET /pages/orders/{order_id}/success`、`GET /pages/reviews/{order_id}`、`GET /reviews/tags`、`GET/PATCH /orders/{order_id}/review-draft`、`GET /listings/{listing_id}/reviews`、`GET /home/feed`。
- 新增兼容别名：`GET /wallet/summary -> /wallet`，`GET /memberships/current -> /membership/subscription`，`POST /notifications/read-all -> /notifications/read`。
- `GET /auth/session` 改为返回“合成 guest session”，不再回退到第一个真实用户；guest session 保留空 access token，并显式携带 `guest_mode: true`。
- 所有写接口强制登录：包括 reconstruction 创建/启动/取消/Mask/发布/Viewer 校准、收藏、创建会话、发消息、下单、地址写入、评价提交、会员升级、通知已读。
- reconstruction 任务必须绑定创建者 `seller_id`，列表与详情默认只返回当前用户自己的任务；发布 listing 时只能以任务归属用户为卖家。
- `POST /auth/logout` 必须兼容“仅 Bearer header、无 body”的当前 Flutter 调用方式。
- `/health`、`/api/v1/health`、`/api/v1/config/public`、`/api/v1/pages/home` 必须在空数据库下稳定返回，不依赖 demo 用户。
- 订单状态流统一为：`live listing -> POST /orders 创建 paid order 并将 listing 置为 reserved -> 卖家 ship -> 买家 confirm-receipt -> order completed + listing sold -> 才允许 review`；取消订单仅允许未发货阶段，取消后 listing 回到 `live`。
- 本期支付与物流为展示级闭环：支付方法使用平台内模拟支付，物流由卖家录入 `carrier_name/tracking_no`，不接第三方支付/短信/实名。
- 平台默认“纯空市场”：不内置 demo 用户、demo 商品、demo 订单、demo 聊天；但允许内置平台元数据，例如分类、服务卡、会员方案、评价标签、空态 Banner。

## Implementation Plan
- **P0 稳定底座**
- 修复空库启动：去掉 `default_user_id()` 对健康检查和 guest 会话的硬依赖；平台元数据初始化与用户数据初始化彻底分离。
- 修复安全边界：给全部 reconstruction 写接口补鉴权和归属校验，阻断游客/匿名用户消耗远程训练资源和发布商品。
- 修复运行时配置：统一使用 `GS_SERVICE_BASE_URL` 和 `GS_SERVICE_PUBLIC_BASE_URL`；所有 task/listing 的 `model_url/viewer_url/video_url` 在返回前都重写成手机可访问的代理或公共地址。
- 补齐部署工件：补 `deploy/linux/systemd/*.service`、`deploy/scripts/backup_runtime_state.py`、`deploy/scripts/check_runtime_health.py`、环境样例和启动文档。

- **P1 后端契约补齐**
- 在现有 `MarketplaceStore` 泛型 records 架构上继续实现，不做表级重构；只增加缺失 record type helper 和更清晰的 domain helper。
- 补齐平台元数据初始化：分类、服务卡、会员计划、评价标签、首页 Banner/空态资源；这些是平台配置，不算 demo 市场数据。
- 补齐页面 bootstrap：`pages/home`、`pages/me`、`pages/messages`、`pages/orders/{id}`、`pages/orders/{id}/success`、`pages/reviews/{order_id}`、`pages/conversations/{id}` 全部空态安全。
- 对齐 `API_PROTO.md`：优先补接口缺口和命名别名，不再新增第二套不兼容命名。
- 规范错误与分页：所有新增接口继续走 `ApiEnvelope`，保持 `meta.page` 一致。

- **P2 电商主链路后端**
- 聊天：实现“从 listing 发起或获取会话”、消息历史获取、消息发送、已读同步、会话列表未读数更新、下单/发货/评价后的通知写入。
- 下单：实现 `POST /orders`，输入 `listing_id + address_id`，写入 order 快照、order_event、payment mock、buyer/seller notification，并将 listing 状态改为 `reserved`。
- 发货与收货：实现卖家发货接口、买家确认收货、买家取消、争议入口；订单事件和 shipment 事件必须追加写入。
- 评价：实现评价标签、按订单的 review draft、评价提交校验、listing 评价列表；只允许 completed order 评价。
- 钱包/会员/通知：钱包以展示级账本为准，记录下单、退款、会员升级的流水；会员升级不接真实支付，只写 subscription 和 wallet transaction；通知支持单条与全部已读。
- 地址：沿用已有 CRUD，并接入 checkout 默认地址与订单快照。

- **P3 Flutter 前台补齐**
- 新建真实的 `messages`、`conversation_detail`、`checkout`、`order_detail`、`order_success`、`review`、`wallet`、`membership`、`notifications` 页面；现有 `features/flows/product_flow_pages.dart` 仅作为视觉参考，不再直接作为业务实现入口。
- 首页与搜索改成真实后端驱动：搜索框走服务端 query，filters/facets 不再本地假筛选。
- 商品详情页的 `Contact / Reviews / Buy now` 全部接真实接口，不再调用 `_showComingSoon`。
- Profile 页的 “My listings” 改用 `/users/me/listings`，并补“收藏 / 地址 / 钱包 / 会员 / 通知 / 订单入口”；guest 态显示登录引导和只读空态，不调用需要 token 的写接口。
- guest 模式下允许浏览首页、搜索、详情、3D Viewer；点击发布、收藏、聊天、下单、个人写操作时统一弹登录引导，不直接报错。
- 修复退出登录：Flutter 端 `logout` 请求显式发 `{}` 或后端兼容无 body；会话清理后回到 auth gate。
- 清理前台遗留：移除未接业务的静态消息页和无引用的 legacy flow 导航入口，避免用户走进假页面。

- **P4 3DGS 业务化收口**
- task 创建时写入 `seller_id`，task 列表默认按当前用户过滤；历史 task 若缺 `seller_id`，提供一次性迁移脚本按 `listing.seller_id` 或当前拥有者补齐。
- publish listing 时把 task 的 viewer/model 资源、quality profile、masking 状态和发布时间回写到 listing，并保证 listing/detail/home 三处看到一致的 3D 状态。
- viewer 校准步骤保留当前 4 步工作流，但发布条件改成“任务 ready + 校准完成 + 已登录 + 任务归属合法”。
- 对远程 trainer 失败给出面向用户的状态文案与重试入口，不把原始基础设施错误直接暴露成主 UI 文案。
- 保留本地 viewer 代理方案，不让移动端直接依赖内网或错误的训练服务地址。

- **P5 发布前收尾**
- 后端测试重写到“纯空市场 + 平台元数据种子 + guest synthetic session”基线，删除对 demo user/demo listing 的默认假设。
- Flutter widget/integration 测试重写到当前中文文案和真实导航；覆盖 auth、guest gating、发布 flow、聊天、下单、评价、profile 设置。
- 增加端到端 smoke checklist：Android 真机 + 本地 backend + 远程 `http://222.199.216.192:9000`，验证上传视频、启动训练、发布商品、查看 3D、聊天、下单、发货、收货、评价。
- 更新 `LOCAL_RUN_3DV_JUNK_MART.md`、`README.md` 和 deploy/env 示例，确保新成员按文档即可拉起。
- 出一版“展示验收数据清单”：空市场首页空态、首个卖家发品、买家聊天下单、卖家发货、买家确认收货、评价成功、钱包/会员/通知有对应记录。

## Test Plan
- 后端必须新增并通过：空库启动测试、guest session 测试、reconstruction 鉴权测试、task 归属隔离测试、conversation create/send/read 测试、order create/ship/cancel/confirm/dispute 测试、review draft/publish 测试、wallet/membership/notification 测试、deploy 工件测试。
- Flutter 必须新增并通过：登录/注册/游客进入、guest 只读拦截、首页空态、搜索、商品详情 3D 预览、任务发布流、消息列表与详情、下单与订单页、评价页、个人资料保存、退出登录。
- 联调验收必须覆盖：环境变量正确时使用远程 trainer；环境变量错误时给出可诊断错误；旧 task URL 能被正确代理或重写；手机侧 Viewer 可稳定打开模型。

## Assumptions
- 本期目标是“展示级电商闭环”，不接入真实支付、短信、实名、第三方物流回调。
- 市场数据默认是纯空市场；只允许平台元数据种子，不默认注入 demo 用户/商品/订单/消息。
- guest 模式保留，但严格只读。
- 优先交付 Android 真机联调链路；桌面和 web 只做不破坏现状的兼容。
- 为了交付速度，本期不做 SQLite 架构重写，不拆成 PostgreSQL 风格多表仓储层；在现有 records 存储上补齐功能与边界，等产品闭环后再做结构性重构。
