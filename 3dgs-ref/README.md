# 3DGS Marketplace

本项目是一个基于 **3D Gaussian Splatting (3DGS)** 的 MVP，用于把商品视频重建成可交互的 3D 模型，并在 Flutter App 中完成上传、任务管理、Object Masking、训练、Viewer 查看、姿态编辑和发布展示的完整闭环。

当前仓库已经实现：

1. Flutter App 基础框架
2. 视频上传与重建任务创建
3. FastAPI 后端 API
4. 3DGS 重建流水线
5. 基于 SAM2 的 Object Masking 交互
6. PLY / SOG 导出
7. Web Viewer 查看与初始视角编辑
8. 商品发布到首页和详情页展示

> 2026-04-09 起，训练服务拆分已经继续演进到“本地业务后端 + 远程 trainer_service”模式：业务后端不再直接 import `trainer.pipeline`，而是通过 HTTP 调用远程训练服务。  
> 当前推荐边界是：**服务器上只部署 trainer_service 与模型文件；viewer 继续由业务后端本地托管。**  
> 当前已验证环境以 **Windows 11 + PowerShell + NVIDIA GPU** 为主，README 也按这个前提来写。

---

## 1. 项目结构

```text
backend/      FastAPI 后端
docs/         项目文档与交接文档
mobile_app/   Flutter App
shared/       前后端共享的任务存储与路径逻辑
storage/      上传视频、处理中间产物、模型产物、任务 JSON
trainer/      训练流水线、SAM2、对象提取、依赖文件
trainer_service/ 内部训练服务，负责启动/取消/Mask 预览/恢复流水线
viewer/       Web Viewer 静态资源
```

当前实际链路：

1. Flutter App 上传视频到后端
2. 后端把视频转发给远程 `trainer_service`
3. App 再调用“启动流水线”
4. 后端调用 `trainer_service`
5. `trainer_service` 启动 `trainer/pipeline.py`
6. `pipeline.py` 调用 `ffmpeg / ffprobe / colmap / ns-process-data / ns-train / ns-export / SAM2 / object_pruning / npx splat-transform`
7. 模型产出到远程训练服务 `STORAGE_ROOT/models/<task_id>/`
8. Viewer 继续由业务后端本地静态托管，但通过远程 `model_url` 加载模型

推荐先阅读：

1. [docs/21-团队开发环境配置手册.md](docs/21-团队开发环境配置手册.md)
2. [docs/6-前后端启动方法.md](/d:/Projects/3dgs-app/docs/6-前后端启动方法.md)
3. [docs/20-训练服务服务器部署准备说明.md](/d:/Projects/3dgs-app/docs/20-%E8%AE%AD%E7%BB%83%E6%9C%8D%E5%8A%A1%E6%9C%8D%E5%8A%A1%E5%99%A8%E9%83%A8%E7%BD%B2%E5%87%86%E5%A4%87%E8%AF%B4%E6%98%8E.md)
4. [docs/17-3DGS项目环境搭建与运行交接文档.md](/d:/Projects/3dgs-app/docs/17-3DGS%E9%A1%B9%E7%9B%AE%E7%8E%AF%E5%A2%83%E6%90%AD%E5%BB%BA%E4%B8%8E%E8%BF%90%E8%A1%8C%E4%BA%A4%E6%8E%A5%E6%96%87%E6%A1%A3.md)
5. [docs/18-训练服务拆分与团队协作开发方案.md](/d:/Projects/3dgs-app/docs/18-%E8%AE%AD%E7%BB%83%E6%9C%8D%E5%8A%A1%E6%8B%86%E5%88%86%E4%B8%8E%E5%9B%A2%E9%98%9F%E5%8D%8F%E4%BD%9C%E5%BC%80%E5%8F%91%E6%96%B9%E6%A1%88.md)

---

## 2. 在开始配置之前，你需要提前准备什么

先不要急着 clone 和装包。  
阶段 A 之后，业务开发和训练服务已经可以分开看待：

1. 本地业务开发机通常只需要 `backend/.venv` + Flutter
2. 只有运行 `trainer_service` 的机器才需要 `3dgs_app / sam2_app / COLMAP / CUDA`

如果你要本地全链路验证，那么它仍然不是“一个 Python 环境就能跑”的类型，而是多个环境协同：

1. `backend/.venv`
2. `conda:3dgs_app`
3. `conda:sam2_app`
4. Flutter / Android SDK
5. FFmpeg / COLMAP / CUDA / Node.js

建议先确认下面这些软件都准备好。

### 2.1 必备软件

| 软件 | 建议版本 | 用途 |
| --- | --- | --- |
| Git | 最新稳定版 | 拉代码、提交代码 |
| Python | `3.13.x` | 后端 venv |
| Miniconda / Anaconda | 最新稳定版 | 管理 `3dgs_app` / `sam2_app` |
| Flutter | `3.41.6` 附近 | 运行移动端 |
| Android Studio | 最新稳定版 | Android SDK / 模拟器 / 构建工具 |
| JDK | `21` | Flutter Android 构建 |
| FFmpeg | `8.x` | 视频预处理 |
| COLMAP | `3.13.x` Windows CUDA 版 | 位姿恢复和稀疏重建 |
| Node.js | `22.x` 附近 | SOG 导出 |
| CUDA Toolkit | `11.8` | 训练依赖 |
| Visual Studio 2022 | 含 C++ 桌面开发组件 | Windows 下 CUDA / C++ 扩展 |

### 2.2 硬件与系统要求

建议至少满足：

1. Windows 11
2. NVIDIA GPU
3. 8GB 显存左右更稳妥
4. 硬盘预留足够空间

说明：

1. `storage/` 会保存上传视频、抽帧数据、中间日志、PLY、SOG，体积增长很快
2. 当前项目已在 RTX 4060 Laptop GPU（8GB）上实际跑通

### 2.3 网络准备

请提前确认你的网络环境允许：

1. 安装 Python 包
2. 安装 npm 包
3. 首次下载 SAM2 模型
4. Viewer 访问 PlayCanvas CDN

如果公司网络限制外网访问，至少要提前准备：

1. Python 镜像源
2. npm 镜像源
3. Hugging Face 模型缓存

### 2.4 Android 调试准备

如果你要完整跑通 App 侧流程，建议提前准备：

1. 一台 Android 真机，或
2. 一个 Android Emulator

真机调试要额外注意：

1. 手机和电脑要在同一局域网
2. App 不能一直用 `10.0.2.2`
3. `10.0.2.2` 只适用于模拟器访问宿主机

---

## 3. 当前仓库的环境设计

这是最关键的一节。  
你必须先理解为什么阶段 A 之后要把“业务后端环境”和“训练服务环境”分开。

### 3.1 环境分工

| 环境 | 用途 | 是否必须 |
| --- | --- | --- |
| `backend/.venv` | 跑业务 FastAPI 后端 | 所有开发机都必须 |
| `conda:3dgs_app` | 跑 `trainer_service`、`ns-process-data`、`ns-train`、`ns-export`、对象提取 | 只有训练服务机器必须 |
| `conda:sam2_app` | 跑 SAM2 掩码推理 | 只有训练服务机器在启用 Object Masking 时必须 |
| `trainer_service/requirements.txt` | 训练服务 API 依赖 | 只有训练服务机器必须 |

### 3.2 为什么不是“只装一个 requirements.txt”

因为当前项目同时依赖：

1. Web 后端依赖
2. Nerfstudio / gsplat / CUDA 训练依赖
3. SAM2 的单独 PyTorch 组合

把这三者强行塞进一个环境，维护成本和失败概率都更高。  
当前仓库已经把依赖拆成了：

- [backend/requirements.txt](/d:/Projects/3dgs-app/backend/requirements.txt)
- [trainer/requirements-cu118.txt](/d:/Projects/3dgs-app/trainer/requirements-cu118.txt)
- [trainer/requirements.txt](/d:/Projects/3dgs-app/trainer/requirements.txt)
- [trainer/requirements-gsplat-cu118.txt](/d:/Projects/3dgs-app/trainer/requirements-gsplat-cu118.txt)
- [trainer/requirements-sam2.txt](/d:/Projects/3dgs-app/trainer/requirements-sam2.txt)

### 3.3 一个重要事实

阶段 A 之前，后端虽然运行在 `backend/.venv` 中，但真正触发训练时，需要当前 shell 能找到：

1. `ns-process-data`
2. `ns-train`
3. `ns-export`
4. `ffmpeg`
5. `ffprobe`
6. `colmap`

现在推荐改为：

1. 业务后端只配置 `TRAINER_SERVICE_BASE_URL`
2. 训练依赖只放到运行 `trainer_service` 的机器

只有当你要在同一台机器上同时跑 `trainer_service` 时，才需要：

1. 先 `conda activate 3dgs_app`
2. 再启动 `trainer_service`
3. 另外再用 `backend/.venv` 的 Python 启动 FastAPI

---

## 4. 保姆级配置教程

下面按“新电脑从零开始”的顺序写。

### 4.1 克隆仓库

```powershell
git clone <your-repo-url> 3dgs-marketplace
cd 3dgs-marketplace
```

如果你已经有仓库，只需要进入项目根目录即可。

### 4.2 创建后端虚拟环境

在项目根目录执行：

```powershell
py -3.13 -m venv backend\.venv
backend\.venv\Scripts\python.exe -m pip install --upgrade pip
backend\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
```

验证：

```powershell
backend\.venv\Scripts\python.exe -c "import fastapi, uvicorn, pydantic; print('backend ok')"
```

### 4.3 创建训练环境 `3dgs_app`

先创建环境：

```powershell
conda create -n 3dgs_app python=3.10 -y
conda activate 3dgs_app
python -m pip install --upgrade pip setuptools wheel
```

安装 PyTorch / CUDA 11.8 版本：

```powershell
pip install -r trainer\requirements-cu118.txt
```

安装训练基础依赖：

```powershell
pip install -r trainer\requirements.txt
```

把 `gsplat` 切到已验证的预编译 wheel：

```powershell
pip install --force-reinstall --no-deps --index-url https://docs.gsplat.studio/whl/pt21cu118 -r trainer\requirements-gsplat-cu118.txt
```

验证：

```powershell
where ns-process-data
where ns-train
where ns-export
python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
python -c "import gsplat, viser, open3d, plyfile, PIL, numpy; print('3dgs_app ok')"
```

> 注意  
> `trainer/environment.yml` 目前只是历史骨架，不要把它当成唯一安装入口。  
> 真正以当前仓库为准的安装方式，是上面这组 `requirements*.txt`。

### 4.4 创建 SAM2 环境 `sam2_app`

创建环境：

```powershell
conda create -n sam2_app python=3.10 -y
conda activate sam2_app
conda install pytorch=2.5.1 torchvision=0.20.1 pytorch-cuda=11.8 -c pytorch -c nvidia -y
pip install -r trainer\requirements-sam2.txt
```

验证：

```powershell
python -c "import torch, numpy, PIL; print(torch.__version__)"
python -c "import sam2; print('sam2 ok')"
```

说明：

1. 当前代码默认 `SAM2_MODEL_ID=facebook/sam2.1-hiera-small`
2. 首次运行 SAM2 可能会下载模型
3. 如果网络受限，需要提前准备缓存或改成本地 checkpoint

### 4.5 安装 FFmpeg

建议安装后把 `bin` 目录加入系统 PATH。  
安装后验证：

```powershell
ffmpeg -version
ffprobe -version
```

### 4.6 安装 COLMAP

建议使用 Windows CUDA 版 COLMAP。  
安装后验证：

```powershell
colmap -h
```

如果你不想配置全局 PATH，请至少记住你的 `colmap.exe` 路径，后面会通过环境变量显式指定给项目。

### 4.7 安装 Node.js

安装后验证：

```powershell
node -v
npm -v
npx -v
npx -y @playcanvas/splat-transform --version
```

当前项目的 SOG 导出依赖 `npx @playcanvas/splat-transform`。

### 4.8 安装 CUDA 11.8 和 Visual Studio C++ 工具链

请确保：

1. 已安装 CUDA Toolkit 11.8
2. 已安装 Visual Studio 2022
3. 已勾选 C++ 桌面开发组件

验证：

```powershell
nvcc --version
```

如果后续遇到 CUDA 扩展或 Windows 编译错误，优先回来看这一步。

### 4.9 安装 Flutter / Android Studio / Android SDK

安装完成后建议先跑：

```powershell
flutter --version
dart --version
flutter doctor -v
```

请确保：

1. Flutter 可用
2. Android SDK 可用
3. 至少有一个设备可调试
4. `flutter doctor -v` 没有关键红字

### 4.10 修正 `mobile_app/android/local.properties`

这个文件是**本机私有路径配置**，每个开发者都需要改。  
示例：

```properties
sdk.dir=D:\\Android\\Sdk
flutter.sdk=D:\\flutter_windows_3.41.6-stable\\flutter
```

### 4.11 安装 Flutter 依赖

```powershell
cd mobile_app
flutter pub get
flutter analyze
cd ..
```

如果 `flutter analyze` 通过，说明 App 侧至少没有明显静态错误。

### 4.12 设置项目运行需要的环境变量

阶段 A 之后，推荐先区分“业务后端机器”和“训练服务机器”。

#### 业务后端机器

```powershell
$env:STORAGE_ROOT="D:\Projects\3dgs-app\storage"
$env:VIEWER_ROOT="D:\Projects\3dgs-app\viewer"
$env:TRAINER_SERVICE_BASE_URL="http://127.0.0.1:9000"
```

如果你启用了内部 token：

```powershell
$env:TRAINER_SERVICE_AUTH_TOKEN="replace-with-a-shared-secret"
```

#### 训练服务机器

在运行 `trainer_service` 的机器上，除了 `STORAGE_ROOT / VIEWER_ROOT` 之外，还建议显式设置：

```powershell
$env:SAM2_PYTHON="D:\miniconda3\envs\sam2_app\python.exe"
$env:PRUNING_PYTHON="D:\miniconda3\envs\3dgs_app\python.exe"
$env:COLMAP_COMPAT_REAL_EXE="D:\colmap-x64-windows-cuda\bin\colmap.exe"
```

可选变量：

```powershell
$env:SAM2_CONDA_ENV="sam2_app"
$env:PRUNING_CONDA_ENV="3dgs_app"
$env:SAM2_MODEL_ID="facebook/sam2.1-hiera-small"
$env:SOG_EXPORT_ENABLED="1"
$env:SOG_EXPORT_ITERATIONS="10"
$env:BACKEND_PIPELINE_MOCK="false"
```

说明：

1. 当前项目没有强制 `.env` 文件
2. 当前不会自动启动训练流水线
3. 业务后端只负责调用 `trainer_service`
4. `BACKEND_PIPELINE_MOCK=true` 只用于联调假流程

### 4.13 一次性自检

在项目根目录执行：

```powershell
backend\.venv\Scripts\python.exe -m py_compile shared\config.py shared\training_config.py shared\task_status.py shared\task_store.py backend\app\schemas.py backend\app\main.py backend\app\routes\reconstructions.py backend\app\services\trainer_client.py trainer_service\schemas.py trainer_service\app.py trainer_service\services\runtime.py trainer\pipeline.py trainer\worker.py trainer\sam2_masking.py trainer\object_pruning.py trainer\colmap_compat.py
```

再执行：

```powershell
cd mobile_app
flutter analyze
cd ..
```

如果这两组命令都通过，基础环境基本就对了。

---

## 5. 配置完成后，如何启动项目

### 5.1 启动顺序

推荐顺序：

1. 设置共享路径和 `TRAINER_SERVICE_BASE_URL`
2. 启动 `trainer_service`（本机或服务器）
3. 启动业务 FastAPI
4. 检查两个 `/health`
5. 启动 Flutter App
6. 在 App 中配置 API 地址

### 5.2 启动后端

本地业务开发推荐直接使用轻量模式：

```powershell
$env:STORAGE_ROOT="D:\Projects\3dgs-app\storage"
$env:VIEWER_ROOT="D:\Projects\3dgs-app\viewer"
$env:TRAINER_SERVICE_BASE_URL="http://127.0.0.1:9000"
backend\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload
```

如果你本机并不运行训练服务，就把 `TRAINER_SERVICE_BASE_URL` 改成远程地址，例如：

```powershell
$env:TRAINER_SERVICE_BASE_URL="http://<trainer-server>:9000"
```

如果你要在本机同时跑训练服务，再单独开一个终端执行：

```powershell
conda activate 3dgs_app
python -m pip install -r trainer_service\requirements.txt
$env:STORAGE_ROOT="D:\Projects\3dgs-app\storage"
$env:VIEWER_ROOT="D:\Projects\3dgs-app\viewer"
$env:SAM2_PYTHON="D:\miniconda3\envs\sam2_app\python.exe"
$env:PRUNING_PYTHON="D:\miniconda3\envs\3dgs_app\python.exe"
$env:COLMAP_COMPAT_REAL_EXE="D:\colmap-x64-windows-cuda\bin\colmap.exe"
python -m uvicorn trainer_service.app:app --host 0.0.0.0 --port 9000 --reload
```

健康检查：

```text
http://127.0.0.1:8000/health
```

正常应返回：

```json
{
  "status": "ok",
  "trainer_service_base_url": "http://127.0.0.1:9000",
  "auto_start_pipeline": false
}
```

### 5.3 启动 Flutter App

#### 模拟器

```powershell
cd mobile_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
cd ..
```

#### 真机

```powershell
cd mobile_app
flutter run --dart-define=API_BASE_URL=http://<你的电脑局域网IP>:8000
cd ..
```

如果 `adb` 不在 PATH，可临时补：

```powershell
$env:Path += ";D:\Android\Sdk\platform-tools"
```

### 5.4 Viewer 说明

Viewer 不需要单独起服务。  
后端已经把 `viewer/` 目录挂载成静态资源：

```text
http://127.0.0.1:8000/viewer/index.html
```

App 里打开的就是后端托管的这个 Viewer。

### 5.5 当前 App 首页

当前 Flutter 入口页面是：

```text
MarketplaceShellPage
```

不是旧版单页 Demo。  
当前结构可以简单理解为：

1. 首页：商品列表
2. 详情页：商品信息 + 内嵌 Viewer
3. 我的：API 配置、开发者入口、卖家任务流

---

## 6. 配置成功后，建议你先完成一次最小验收

至少完成下面这组检查：

1. `/health` 返回正常
2. App 可以连接后端
3. 能上传一个视频并创建任务
4. 能手动点击“启动流水线”
5. 任务最终能到 `ready`
6. `storage/models/<task_id>/` 下生成 `model.ply` 或 `model.sog`
7. Viewer 能正常打开

如果只想先测前后端联通，不想真实训练，可以临时使用：

```powershell
$env:BACKEND_PIPELINE_MOCK="true"
```

---

## 7. 最常见的坑

### 7.1 后端启动了，但一启动训练就失败

通常是因为：

1. 没有先 `conda activate 3dgs_app`
2. 当前 shell 找不到 `ns-train` / `ns-export` / `colmap`
3. `COLMAP_COMPAT_REAL_EXE` 没配对

### 7.2 只照着 `trainer/environment.yml` 装，结果跑不起来

这是当前仓库的已知情况。  
请以 `trainer/requirements*.txt` 为准。

### 7.3 `gsplat` 在 Windows 上报 CUDA 编译错误

优先确认你是否执行了这一步：

```powershell
pip install --force-reinstall --no-deps --index-url https://docs.gsplat.studio/whl/pt21cu118 -r trainer\requirements-gsplat-cu118.txt
```

### 7.4 真机连不上后端

优先检查：

1. 手机和电脑是否在同一局域网
2. 是否还在用 `10.0.2.2`
3. Windows 防火墙是否拦截了 8000 端口

### 7.5 Viewer 白屏

优先检查：

1. 后端是否启动
2. `viewer_url` 是否正确
3. 模型文件是否可访问
4. 当前网络是否能访问 PlayCanvas CDN

---

## 8. 推荐阅读

如果你要继续维护或扩展这个项目，建议按下面顺序阅读：

1. [docs/17-3DGS项目环境搭建与运行交接文档.md](/d:/Projects/3dgs-app/docs/17-3DGS项目环境搭建与运行交接文档.md)
2. [backend/app/routes/reconstructions.py](/d:/Projects/3dgs-app/backend/app/routes/reconstructions.py)
3. [shared/task_store.py](/d:/Projects/3dgs-app/shared/task_store.py)
4. [trainer/pipeline.py](/d:/Projects/3dgs-app/trainer/pipeline.py)
5. [trainer/object_pruning.py](/d:/Projects/3dgs-app/trainer/object_pruning.py)
6. [mobile_app/lib/src/services/api_client.dart](/d:/Projects/3dgs-app/mobile_app/lib/src/services/api_client.dart)
7. [mobile_app/lib/src/pages/seller_publish_flow_page.dart](/d:/Projects/3dgs-app/mobile_app/lib/src/pages/seller_publish_flow_page.dart)
8. [viewer/viewer.js](/d:/Projects/3dgs-app/viewer/viewer.js)

---

## 9. 当前仓库的推荐定位

这个仓库当前最适合这样定位：

1. 作为 3DGS 商品展示 MVP
2. 作为电商业务接入前的技术底座
3. 作为本地训练、查看、调试、交接用工程

它已经适合：

1. 新同学本地搭环境
2. 团队做功能交接
3. 在此基础上继续扩展电商业务流程

但它暂时还不是：

1. 生产级训练平台
2. 多机协同平台
3. 正式数据库 / 对象存储 / 队列化架构

如果你需要更完整的工程交接说明，请继续看：

- [docs/17-3DGS项目环境搭建与运行交接文档.md](/d:/Projects/3dgs-app/docs/17-3DGS项目环境搭建与运行交接文档.md)
