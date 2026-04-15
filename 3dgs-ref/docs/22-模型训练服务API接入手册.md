# 模型训练服务 API 接入手册

更新时间：2026-04-10

本文面向后续负责电商业务、任务编排、商品发布、Viewer 入口拼接的团队成员，目标是说明：

1. `trainer_service` 负责什么
2. 业务后端应该怎么调用
3. 每个接口的请求/响应格式是什么
4. Object Masking、训练、导出完成后该看哪些字段

---

## 1. 当前架构与边界

当前推荐架构：

```text
Flutter App
   -> 本地业务 backend
   -> 远程 trainer_service

viewer 继续由本地业务 backend 托管
训练任务、模型文件、日志、mask 产物由远程 trainer_service 管理
```

当前团队共享训练服务地址：

```text
http://222.199.216.192:9000
```

### 1.1 职责划分

`trainer_service` 负责：

1. 接收视频上传并创建训练任务
2. 执行预处理、COLMAP、Object Masking、3DGS 训练、导出
3. 保存任务状态、日志、模型文件
4. 通过 `/storage/*` 公开模型、日志、mask 预览等静态产物
5. 保存模型旋转、平移、缩放、初始视角等 `viewer_config`

本地业务 backend 负责：

1. 接收 Flutter 请求
2. 调用 `trainer_service`
3. 维护商品发布、电商业务状态、买家首页、商品详情等业务逻辑
4. 用本地 `viewer/` 静态页拼接最终 `viewer_url`

Flutter App 负责：

1. 只连接本地业务 backend
2. 不直接调用远程 `trainer_service`
3. 在需要展示模型、日志、mask 预览时使用 backend 返回的数据

### 1.2 一个关键原则

业务后端应把 `trainer_service` 当成“训练与模型资产服务”。

不要把下面这些业务能力塞进 `trainer_service`：

1. 商品发布
2. 首页商品列表
3. 买家详情页
4. Flutter 登录态与用户身份
5. 本地 Viewer 页面路由

---

## 2. 接入建议

### 2.1 推荐接入方式

推荐由业务后端统一封装一个客户端，再对 Flutter 暴露自己的业务接口。

仓库里当前已有一份可参考实现：

1. [gs_client.py](/home/wsh/3DGS-Marketplace/backend/app/services/gs_client.py)
2. [reconstructions.py](/home/wsh/3DGS-Marketplace/backend/app/routes/reconstructions.py)

### 2.2 不推荐的接入方式

不建议：

1. Flutter 直接调用 `trainer_service`
2. Flutter 直接拼 `POST /tasks`、`POST /tasks/{task_id}/start`
3. Flutter 直接把训练服务地址写死成 `222.199.216.192:9000`

原因：

1. 会把训练服务暴露给客户端
2. 后续鉴权、限流、地址切换会很难收口
3. `viewer_url` 本来就应该由本地 backend 生成

### 2.3 业务后端需要配置什么

本地 backend 只需要配置：

```bash
GS_SERVICE_BASE_URL=http://222.199.216.192:9000
```

当前代码会优先读取：

1. `GS_SERVICE_BASE_URL`
2. `TRAINER_SERVICE_BASE_URL`

定义位置见 [config.py](/home/wsh/3DGS-Marketplace/shared/config.py)。

---

## 3. 服务概览

### 3.1 基础信息

- Base URL：`http://222.199.216.192:9000`
- Content-Type：
  - 上传任务：`multipart/form-data`
  - 其他大部分写接口：`application/json`
- 静态资源：`/storage/*`

### 3.2 公开接口与内部接口

`trainer_service` 分两类接口：

1. 公开接口：`/tasks/*`
2. 内部接口：`/internal/tasks/*`

业务接入默认优先使用公开接口。

内部接口主要用于：

1. 服务器内部脚本
2. 需要单独鉴权保护的运维入口

如果服务器配置了 `TRAINER_SERVICE_AUTH_TOKEN`，内部接口必须带：

```http
X-Internal-Token: <token>
```

当前公开接口不要求这个 header。

---

## 4. 任务生命周期

一个完整任务通常按这个顺序流转：

1. `POST /tasks` 创建任务
2. `POST /tasks/{task_id}/start` 启动训练流水线
3. 轮询 `GET /tasks/{task_id}`
4. 如果开启 `object_masking=true`：
   - 等待进入 `awaiting_mask_prompt`
   - 用 `mask_prompt_frame_url` 显示提示帧
   - 调 `POST /tasks/{task_id}/mask-preview`
   - 用户检查全帧预览
   - 调 `POST /tasks/{task_id}/mask-confirm`
5. 继续轮询任务状态
6. 任务进入 `ready`
7. 使用 `model_url` / `model_ply_url` / `model_sog_url`
8. 用 `PUT /tasks/{task_id}/viewer` 保存 Viewer 校准参数

### 4.1 状态枚举

当前状态定义见 [task_status.py](/home/wsh/3DGS-Marketplace/shared/task_status.py)。

常见状态如下：

| 状态 | 含义 |
| --- | --- |
| `uploaded` | 已上传视频，还没启动流水线 |
| `queued` | 已确认配置，等待或刚启动流水线 |
| `preprocessing` | 正在抽帧、COLMAP、预处理 |
| `awaiting_mask_prompt` | 等待用户在提示帧上补点 |
| `awaiting_mask_confirmation` | 已生成全帧分割预览，等待用户确认 |
| `masking` | 正在执行 SAM2 掩码生成 |
| `training` | 正在执行 3DGS 训练 |
| `exporting` | 正在导出模型 |
| `ready` | 模型可用 |
| `failed` | 流水线失败 |
| `cancelled` | 流水线已取消 |

### 4.2 哪些状态可以继续做什么

| 场景 | 允许状态 |
| --- | --- |
| 启动流水线 | `uploaded` / `failed` / `cancelled` |
| 取消流水线 | `queued` / `preprocessing` / `awaiting_mask_prompt` / `awaiting_mask_confirmation` / `masking` / `training` / `exporting` |
| 生成 mask 预览 | `awaiting_mask_prompt` / `awaiting_mask_confirmation` |
| 确认 mask 并继续训练 | `awaiting_mask_confirmation` |
| 重新进入 mask debug | 任务空闲且已有可复用 COLMAP 数据时 |
| 删除任务 | 非活动状态，且不在 mask 交互中 |

---

## 5. 核心数据结构

## 5.1 TaskResponse

绝大多数接口最终都会返回 `TaskResponse`。

主要字段如下：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `task_id` | `string` | 任务 ID |
| `title` | `string` | 标题 |
| `description` | `string` | 描述 |
| `price` | `string` | 价格字符串，训练服务不做金额业务校验 |
| `status` | `string` | 当前状态 |
| `progress` | `int` | 0-100 的粗粒度进度 |
| `status_message` | `string?` | 当前阶段描述 |
| `error_message` | `string?` | 失败原因 |
| `video_url` | `string?` | 上传视频 URL |
| `model_url` | `string?` | 当前推荐使用的模型 URL |
| `model_ply_url` | `string?` | PLY 模型 URL |
| `model_sog_url` | `string?` | SOG 模型 URL，存在时说明导出成功 |
| `model_format` | `string?` | 当前推荐模型格式，通常为 `ply` 或 `sog` |
| `viewer_url` | `string?` | 在 `trainer_service` 中固定为 `null`，由业务 backend 自己拼 |
| `viewer_config` | `object?` | 当前 Viewer 参数 |
| `log_url` | `string?` | 全量日志文件 URL |
| `log_tail` | `string[]` | 日志尾部片段 |
| `train_step` | `int?` | 当前训练步数 |
| `train_total_steps` | `int?` | 总训练步数 |
| `train_eta` | `string?` | 训练剩余时间文本 |
| `train_max_steps` | `int?` | 任务配置的总步数 |
| `quality_profile` | `string?` | 质量档位 |
| `object_masking` | `bool` | 是否开启 Object Masking |
| `mask_prompt_frame_url` | `string?` | 提示帧图片 |
| `mask_prompt_frame_name` | `string?` | 提示帧文件名 |
| `mask_prompt_frame_width` | `int?` | 提示帧宽 |
| `mask_prompt_frame_height` | `int?` | 提示帧高 |
| `mask_prompts_url` | `string?` | 用户提示点 JSON |
| `mask_preview_url` | `string?` | 当前提示帧对应的预览图 |
| `mask_preview_manifest_url` | `string?` | 全帧预览 manifest |
| `mask_summary_url` | `string?` | 掩码统计信息 |
| `can_debug_masking` | `bool` | 是否允许重新进入 mask debug |
| `pipeline_pid` | `int?` | 服务器子进程 PID，仅调试用 |
| `mock_mode` | `bool` | 是否 mock 流程 |
| `is_published` | `bool` | 是否已发布 |
| `published_at` | `string?` | 发布时间 |
| `viewer_rotation_done` | `bool` | 业务流程位，用于前端步骤判断 |
| `viewer_translation_done` | `bool` | 业务流程位 |
| `viewer_initial_view_done` | `bool` | 业务流程位 |
| `viewer_animation_approved` | `bool` | 业务流程位 |

### 5.2 一个重要约定

请把 `model_url`、`video_url`、`log_url`、`mask_preview_manifest_url` 等 URL 当成“可直接使用的完整 URL”。

不要自己重新拼接：

1. `/storage/...`
2. 查询参数 `?v=...`
3. 域名和端口

这些都由服务端统一生成。

### 5.3 viewer_config

当前默认值：

```json
{
  "model_rotation_deg": [0, 0, 0],
  "model_translation": [0, 0, 0],
  "model_scale": 1.0,
  "camera_rotation_deg": [-18, 26, 0],
  "camera_distance": 1.6
}
```

### 5.4 质量档位

当前支持：

| 档位 | 用途 |
| --- | --- |
| `fast` | 低分辨率，快速检查 |
| `balanced` | 默认档位，团队当前主用 |
| `quality` | 更高细节、更高成本 |
| `raw` | 实验档位，成本最高，不支持 Object Masking |

默认档位：`balanced`

### 5.5 训练步数

当前只支持：

1. `7000`
2. `30000`

默认值：`7000`

---

## 6. 接口清单

## 6.1 健康检查

### `GET /health`

用途：

1. 检查服务是否存活
2. 看当前服务根目录和对外地址

示例：

```bash
curl http://222.199.216.192:9000/health
```

示例响应：

```json
{
  "status": "ok",
  "repo_root": "/home/wsh/3DGS-Marketplace",
  "storage_root": "/data/3dgs-storage",
  "viewer_root": "/home/wsh/3DGS-Marketplace/viewer",
  "python_executable": "/home/wsh/.conda/envs/3dgs_app/bin/python",
  "public_base_url": "http://222.199.216.192:9000"
}
```

---

## 6.2 创建任务

### `POST /tasks`

用途：

上传视频并创建一个新任务。

请求类型：

`multipart/form-data`

字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | 是 | 商品标题 |
| `description` | string | 否 | 商品描述 |
| `price` | string | 否 | 价格字符串 |
| `video` | file | 是 | 视频文件 |

约束：

1. 文件名不能为空
2. `content_type` 应为 `video/*`
3. 视频时长不能超过 60 秒
4. 必须能被 `ffprobe` 识别为有效视频

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks" \
  -F "title=demo" \
  -F "description=test upload" \
  -F "price=299.00" \
  -F "video=@./demo.mp4;type=video/mp4"
```

成功响应：

`201 Created`，返回 `TaskResponse`

接入建议：

1. 创建任务成功后，先保存 `task_id`
2. 不要假设创建后会自动训练
3. 业务后端应显式调用 `/tasks/{task_id}/start`

---

## 6.3 查询任务列表

### `GET /tasks`

用途：

按条件查询任务列表。

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `status` | string | 否 | 状态过滤，多个状态用逗号分隔 |

示例：

```bash
curl "http://222.199.216.192:9000/tasks"
curl "http://222.199.216.192:9000/tasks?status=ready"
curl "http://222.199.216.192:9000/tasks?status=failed,cancelled"
```

成功响应：

```json
[
  {
    "task_id": "task_20260409_223738_c35bd6",
    "status": "ready",
    "model_url": "http://222.199.216.192:9000/storage/models/task_20260409_223738_c35bd6/model.ply?v=...",
    "model_format": "ply"
  }
]
```

接入建议：

1. 商品首页如果只想展示已训练完成任务，可先按业务侧条件筛选 `ready`
2. “是否发布”仍应由业务 backend 自己控制

---

## 6.4 查询单个任务

### `GET /tasks/{task_id}`

用途：

获取任务详情与当前进度。

示例：

```bash
curl "http://222.199.216.192:9000/tasks/task_20260409_223738_c35bd6"
```

业务接入最常用的字段：

1. `status`
2. `progress`
3. `status_message`
4. `error_message`
5. `log_tail`
6. `mask_prompt_frame_url`
7. `mask_preview_manifest_url`
8. `model_url`
9. `viewer_config`

轮询建议：

1. `queued / preprocessing / masking / training / exporting`：每 2-3 秒轮询一次
2. `awaiting_mask_prompt / awaiting_mask_confirmation`：收到状态变化后再刷新即可
3. `ready / failed / cancelled`：停止轮询

---

## 6.5 启动训练流水线

### `POST /tasks/{task_id}/start`

用途：

在 `uploaded / failed / cancelled` 状态下启动或重启流水线。

请求体：

```json
{
  "quality_profile": "balanced",
  "train_max_steps": 7000,
  "object_masking": true,
  "mock_mode": false
}
```

字段说明：

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `quality_profile` | string | 否 | `balanced` | 质量档位 |
| `train_max_steps` | int | 否 | `7000` | 训练步数，只支持 7000 / 30000 |
| `object_masking` | bool | 否 | `false` | 是否开启 Object Masking |
| `mock_mode` | bool | 否 | `false` | 是否用 mock 模式跑流程 |

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/task_xxx/start" \
  -H "Content-Type: application/json" \
  -d '{
    "quality_profile": "balanced",
    "train_max_steps": 7000,
    "object_masking": true,
    "mock_mode": false
  }'
```

接入建议：

1. 电商业务默认用 `balanced + 7000`
2. 如果做交互式抠图，传 `object_masking=true`
3. `raw` 档位不支持 Object Masking

---

## 6.6 取消任务

### `POST /tasks/{task_id}/cancel`

用途：

取消正在运行或正在等待 mask 交互的任务。

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/task_xxx/cancel"
```

成功响应：

返回取消后的 `TaskResponse`

常见场景：

1. 用户取消训练
2. 用户想改参数后重启
3. 任务卡住后人工终止

---

## 6.7 重新进入 Mask Debug

### `POST /tasks/{task_id}/mask-debug`

用途：

在已有可复用 COLMAP 数据时，重新进入 Object Masking 调试流程。

这个接口适合：

1. 任务之前已经至少成功跑到过预处理完成
2. 想重新选提示帧或重新补点
3. 不想整条流水线从头再跑

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/task_xxx/mask-debug"
```

成功后，任务会重新进入等待补点的交互状态。

---

## 6.8 生成全帧 Mask 预览

### `POST /tasks/{task_id}/mask-preview`

用途：

用户在提示帧上补点后，生成整段视频的 SAM2 分割预览。

请求体：

```json
{
  "points": [
    { "x": 0.51, "y": 0.42, "label": 1 },
    { "x": 0.12, "y": 0.30, "label": 0 }
  ]
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `x` | float | 归一化横坐标，范围 0-1 |
| `y` | float | 归一化纵坐标，范围 0-1 |
| `label` | int | `1` 表示正样本点，`0` 表示负样本点 |

约束：

1. 至少要有一个点
2. 至少要有一个 `label=1` 的正样本点

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/task_xxx/mask-preview" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      { "x": 0.52, "y": 0.43, "label": 1 },
      { "x": 0.17, "y": 0.29, "label": 0 }
    ]
  }'
```

成功后重点查看：

1. `mask_preview_url`
2. `mask_preview_manifest_url`
3. `mask_summary_url`
4. `status=awaiting_mask_confirmation`

---

## 6.9 确认 Mask 并继续训练

### `POST /tasks/{task_id}/mask-confirm`

用途：

用户确认全帧分割预览无误后，继续执行后续 SAM2 mask、训练与导出。

示例：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/task_xxx/mask-confirm"
```

成功后：

1. 任务会重新进入 `queued`
2. 接着走 `masking -> training -> exporting -> ready`

---

## 6.10 更新 Viewer 参数

### `PUT /tasks/{task_id}/viewer`

用途：

保存模型旋转、平移、缩放与初始相机参数。

请求体支持部分更新：

```json
{
  "model_rotation_deg": [0, 180, 0],
  "model_translation": [0.0, 0.02, -0.01],
  "model_scale": 1.0,
  "camera_rotation_deg": [-18, 26, 0],
  "camera_distance": 1.6
}
```

示例：

```bash
curl -X PUT "http://222.199.216.192:9000/tasks/task_xxx/viewer" \
  -H "Content-Type: application/json" \
  -d '{
    "model_rotation_deg": [0, 180, 0],
    "camera_rotation_deg": [-20, 28, 0],
    "camera_distance": 1.8
  }'
```

成功响应：

```json
{
  "task_id": "task_xxx",
  "viewer_config": {
    "model_rotation_deg": [0, 180, 0],
    "model_translation": [0, 0, 0],
    "model_scale": 1.0,
    "camera_rotation_deg": [-20, 28, 0],
    "camera_distance": 1.8
  },
  "task": { "...": "完整 TaskResponse" }
}
```

说明：

1. `trainer_service` 只保存 `viewer_config`
2. 最终的 `viewer_url` 仍应由业务 backend 自己拼接

---

## 6.11 删除任务

### `DELETE /tasks/{task_id}`

用途：

删除空闲任务。

示例：

```bash
curl -X DELETE "http://222.199.216.192:9000/tasks/task_xxx"
```

成功响应：

`204 No Content`

限制：

如果任务处于运行中或正在等待 mask 交互，会返回 `409 Conflict`。

---

## 7. 内部接口

内部接口前缀：

```text
/internal/tasks/{task_id}/...
```

默认只建议服务端或运维脚本使用。

如果服务端配置了 token，需要带：

```http
X-Internal-Token: <TRAINER_SERVICE_AUTH_TOKEN>
```

### 7.1 `POST /internal/tasks/{task_id}/start`

和公开 `start` 类似，但返回的是：

```json
{
  "accepted": true,
  "task_id": "task_xxx",
  "message": "training started",
  "pipeline_pid": 12345,
  "worker_job_id": "task_xxx",
  "killed_pids": []
}
```

### 7.2 `POST /internal/tasks/{task_id}/cancel`

返回被结束的进程 PID 列表。

### 7.3 `POST /internal/tasks/{task_id}/mask-debug`

内部版重新进入 mask debug。

### 7.4 `POST /internal/tasks/{task_id}/mask-preview`

内部版生成全帧 mask 预览。

### 7.5 `POST /internal/tasks/{task_id}/resume`

内部版继续 mask 后的训练流程，等价于公开接口：

```text
POST /tasks/{task_id}/mask-confirm
```

---

## 8. `/storage/*` 静态产物说明

训练服务会返回很多静态 URL，它们通常落在：

```text
http://222.199.216.192:9000/storage/...
```

常见产物：

| 字段 | 含义 |
| --- | --- |
| `video_url` | 原始上传视频 |
| `log_url` | 全量流水线日志 |
| `model_ply_url` | PLY 模型 |
| `model_sog_url` | SOG 模型 |
| `mask_prompt_frame_url` | 当前提示帧 |
| `mask_preview_url` | 当前提示帧的分割预览图 |
| `mask_preview_manifest_url` | 全帧预览清单 |
| `mask_summary_url` | 掩码统计信息 |

### 8.1 `mask_preview_manifest.json` 格式

`mask_preview_manifest_url` 返回一个 JSON 文件，结构大致如下：

```json
{
  "source_factor": 2,
  "frame_count": 131,
  "prompt_frame_name": "frame_00001.png",
  "prompt_frame_index": 0,
  "frame_width": 720,
  "frame_height": 1280,
  "frames": [
    {
      "index": 0,
      "name": "frame_00001.png",
      "image_rel_url": "/storage/processed/task_xxx/dataset/_sam2_video_frames/00000.jpg?v=...",
      "preview_rel_url": "/storage/processed/task_xxx/mask_preview_frames/frame_00001.jpg?v=...",
      "mask_coverage": 0.2024
    }
  ]
}
```

接入建议：

1. `frames[index].image_rel_url` 是原始帧图
2. `frames[index].preview_rel_url` 是带 mask 叠加的预览图
3. 业务侧应把这些 URL 当成 trainer_service 返回资源来显示
4. 如果拿到的是相对 `/storage/...` 路径，必须按 manifest 自己的来源地址解析，不要错拼到本地 backend

### 8.2 `mask_summary.json` 格式

`mask_summary_url` 典型内容如下：

```json
{
  "frame_count": 131,
  "mask_count": 131,
  "prompt_frame_name": "frame_00001.png",
  "positive_points": 5,
  "negative_points": 0,
  "average_mask_coverage": 0.2457,
  "min_mask_coverage": 0.1550,
  "max_mask_coverage": 0.3967,
  "preview_frame_count": 131
}
```

这个文件更适合调试和质量统计，不建议作为核心业务字段依赖。

---

## 9. 业务后端推荐接入流程

最推荐的做法是：

1. Flutter 上传视频到本地 backend
2. backend 调 `POST /tasks`
3. backend 返回自己的任务详情接口给 Flutter
4. backend 调 `POST /tasks/{task_id}/start`
5. Flutter 只轮询 backend 自己的任务详情接口
6. backend 再去轮询或透传 trainer_service 的任务结果
7. 训练完成后，backend 自己拼接本地 `viewer_url`

### 9.1 推荐后端封装方法

建议封装以下方法：

1. `create_task`
2. `get_task`
3. `list_tasks`
4. `start_task`
5. `cancel_task`
6. `start_mask_debug`
7. `preview_mask`
8. `confirm_mask`
9. `update_viewer`
10. `delete_task`

当前仓库里的 [gs_client.py](/home/wsh/3DGS-Marketplace/backend/app/services/gs_client.py) 已经是这样封装的。

### 9.2 推荐的 `viewer_url` 拼接方式

`trainer_service` 返回 `model_url` 和 `viewer_config`。

业务 backend 应根据自己的本地地址拼：

```text
/viewer/index.html?task_id=...&model=<远程 model_url>&model_rx=...&cam_rx=...
```

当前参考实现见：

1. [reconstruction_mirror.py](/home/wsh/3DGS-Marketplace/backend/app/services/reconstruction_mirror.py)

---

## 10. 错误处理建议

### 10.1 常见 HTTP 状态码

| 状态码 | 含义 |
| --- | --- |
| `400` | 请求参数不合法，例如视频无效、时长超限、缺少 mask 点 |
| `401` | 内部接口 token 错误 |
| `404` | 任务或文件不存在 |
| `409` | 当前状态不允许执行该操作 |
| `500` | 服务内部错误 |

### 10.2 错误响应格式

大多数错误会返回：

```json
{
  "detail": "具体错误信息"
}
```

业务后端建议：

1. 优先把 `detail` 透传给上层
2. 对 `409` 做更友好的状态提示
3. 对 `5xx` 做重试或人工提示

### 10.3 不要只看 HTTP 成功

训练任务是异步的。

这意味着：

1. `POST /start` 返回 `200` 不代表训练成功
2. `POST /mask-confirm` 返回 `200` 不代表后续训练一定成功
3. 真正是否成功，要以后续 `GET /tasks/{task_id}` 中的 `status` 为准

---

## 11. 接入示例

## 11.1 创建并启动任务

```bash
curl -X POST "http://222.199.216.192:9000/tasks" \
  -F "title=chair-demo" \
  -F "description=demo" \
  -F "price=299.00" \
  -F "video=@./chair.mp4;type=video/mp4"
```

拿到 `task_id` 后：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/<task_id>/start" \
  -H "Content-Type: application/json" \
  -d '{
    "quality_profile": "balanced",
    "train_max_steps": 7000,
    "object_masking": true,
    "mock_mode": false
  }'
```

轮询：

```bash
curl "http://222.199.216.192:9000/tasks/<task_id>"
```

## 11.2 进行 Object Masking

当任务进入 `awaiting_mask_prompt` 后：

1. 使用 `mask_prompt_frame_url` 展示提示帧
2. 收集用户点击点
3. 调用：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/<task_id>/mask-preview" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      { "x": 0.45, "y": 0.41, "label": 1 },
      { "x": 0.18, "y": 0.33, "label": 0 }
    ]
  }'
```

检查 `mask_preview_manifest_url` 后，确认继续：

```bash
curl -X POST "http://222.199.216.192:9000/tasks/<task_id>/mask-confirm"
```

## 11.3 保存 Viewer 配置

```bash
curl -X PUT "http://222.199.216.192:9000/tasks/<task_id>/viewer" \
  -H "Content-Type: application/json" \
  -d '{
    "model_rotation_deg": [0, 180, 0],
    "model_translation": [0, 0.02, 0],
    "camera_rotation_deg": [-18, 26, 0],
    "camera_distance": 1.6
  }'
```

---

## 12. 结论

对于电商业务开发来说，最重要的接入结论只有几条：

1. Flutter 不直连 `trainer_service`
2. 业务 backend 调 `trainer_service`
3. 训练是异步任务，最终结果以 `GET /tasks/{task_id}` 为准
4. Object Masking 需要走“提示帧 -> 预览 -> 确认”三步
5. `viewer_url` 由本地业务 backend 自己拼，不由 `trainer_service` 直接返回
6. 模型、日志、mask 预览等静态文件全部走 `trainer_service` 的 `/storage/*`

如果你是第一次接入，建议先对照：

1. [trainer_service/app.py](/home/wsh/3DGS-Marketplace/trainer_service/app.py)
2. [trainer_service/schemas.py](/home/wsh/3DGS-Marketplace/trainer_service/schemas.py)
3. [backend/app/services/gs_client.py](/home/wsh/3DGS-Marketplace/backend/app/services/gs_client.py)
4. [backend/app/services/reconstruction_mirror.py](/home/wsh/3DGS-Marketplace/backend/app/services/reconstruction_mirror.py)
