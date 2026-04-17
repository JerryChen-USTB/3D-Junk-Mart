# Deployment Notes

This directory contains the server-side artifacts for the marketplace backend and trainer integration.

## Contents

- `linux/systemd/3dgs-backend.service`: FastAPI backend service
- `linux/systemd/3dgs-trainer.service`: trainer service unit
- `linux/systemd/3dgs-backup.service` and `.timer`: runtime backup job
- `linux/systemd/3dgs-healthcheck.service` and `.timer`: periodic health verification
- `linux/nginx/3dgs-marketplace.conf`: reverse proxy template
- `linux/logrotate/3dgs-marketplace`: log rotation policy
- `linux/env/backend.env.example`: backend environment sample
- `scripts/backup_runtime_state.py`: sqlite + storage backup helper
- `scripts/check_runtime_health.py`: backend/trainer/model/viewer health checker

## Required environment

At minimum, configure:

- `STORAGE_ROOT`
- `VIEWER_ROOT`
- `SQLITE_DB_PATH`
- `GS_SERVICE_BASE_URL`

If the backend reaches the trainer through an internal address but phones need a public address for returned model URLs, also configure:

- `GS_SERVICE_PUBLIC_BASE_URL`

Backward-compatible aliases are still supported:

- `TRAINER_SERVICE_BASE_URL`
- `TRAINER_SERVICE_PUBLIC_BASE_URL`

## Suggested bootstrap flow

1. Copy `linux/env/backend.env.example` to the target host and fill in real paths and URLs.
2. Install the backend and trainer `systemd` units.
3. Enable the backup and healthcheck timers.
4. Install the nginx config and logrotate policy.
5. Run `deploy/scripts/check_runtime_health.py` after the first deploy.

## Off-campus note

If the trainer host is only reachable from campus or an internal network, backend health can still be green while trainer-dependent checks fail. In that case:

- backend-only endpoints should still pass
- trainer/model/viewer checks should be treated as network-path failures, not necessarily deployment regressions
