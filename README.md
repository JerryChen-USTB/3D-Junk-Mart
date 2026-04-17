# 3dv-junk-mart

`3dv-junk-mart` is the main product repository for a 3DGS-based second-hand marketplace. It contains:

- `app/`: Flutter client
- `backend/`: FastAPI business backend
- `shared/`: shared runtime/config helpers
- `viewer/`: local 3D viewer assets
- `deploy/`: Linux deployment artifacts, health checks, backup scripts

The current repo state supports a real marketplace shell instead of a demo-only flow:

- login, register, guest mode
- listing feed, search, listing detail, 3D preview
- conversation creation and messaging
- checkout, order creation, ship, confirm receipt, dispute
- review draft and review submission
- wallet, membership, notifications, addresses
- 3DGS reconstruction task library, publish flow, viewer calibration, listing publish

A Chinese close-out summary for the commerce completion and UX fixes is in [docs/19-电商业务收口与体验优化总结.md](docs/19-电商业务收口与体验优化总结.md).

## Local run

Backend:

```powershell
cd D:\Projects\3dv-junk-mart
py -3.13 -m venv backend\.venv
.\backend\.venv\Scripts\python.exe -m pip install --upgrade pip
.\backend\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt

$env:STORAGE_ROOT="D:\Projects\3dv-junk-mart\storage"
$env:VIEWER_ROOT="D:\Projects\3dv-junk-mart\viewer"
$env:GS_SERVICE_BASE_URL="http://222.199.216.192:9000"
$env:GS_SERVICE_PUBLIC_BASE_URL="http://222.199.216.192:9000"

.\backend\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload
```

Flutter:

```powershell
cd D:\Projects\3dv-junk-mart\app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android real-device debugging, use `adb reverse tcp:8000 tcp:8000` first.

Detailed Windows instructions are in [LOCAL_RUN_3DV_JUNK_MART.md](LOCAL_RUN_3DV_JUNK_MART.md).

## Network note

The remote training service is currently expected at `http://222.199.216.192:9000`. If you are off campus or on a phone hotspot, the backend may not be able to reach that host.

In that case you can still validate:

- auth and guest mode
- feed, search, detail, viewer pages for existing models
- chat, checkout, order lifecycle, review, wallet, membership, notifications
- local backend startup and deployment health scripts

What will not validate off campus:

- starting new remote 3DGS training jobs
- remote task polling that depends on the trainer being reachable
- end-to-end publish flow from uploaded video to trained model

## Tests

Backend:

```powershell
cd D:\Projects\3dv-junk-mart
python -m unittest discover
```

Flutter:

```powershell
cd D:\Projects\3dv-junk-mart\app
flutter test
```

Remote trainer connectivity tests are opt-in and skipped by default. Enable them only when the remote service is reachable:

```powershell
$env:RUN_REMOTE_3DGS_CONNECTIVITY_TESTS="1"
python -m unittest tests.test_remote_3dgs_connectivity
```

## Deployment

Deployment artifacts live in `deploy/`:

- `deploy/linux/systemd/`
- `deploy/linux/nginx/`
- `deploy/linux/logrotate/`
- `deploy/linux/env/backend.env.example`
- `deploy/scripts/backup_runtime_state.py`
- `deploy/scripts/check_runtime_health.py`

See [deploy/README.md](deploy/README.md) for the server-side layout and expected environment variables.
