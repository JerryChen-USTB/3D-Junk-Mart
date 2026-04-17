from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from typing import Any
from urllib import request as urllib_request


@dataclass
class HealthCheckResult:
    url: str
    status_code: int
    ok: bool
    payload: Any | None = None


def _fetch(url: str, timeout_seconds: float) -> HealthCheckResult:
    with urllib_request.urlopen(url, timeout=timeout_seconds) as response:
        body = response.read()
        payload: Any | None
        try:
            payload = json.loads(body.decode("utf-8"))
        except ValueError:
            payload = body.decode("utf-8") or None
    return HealthCheckResult(
        url=url,
        status_code=getattr(response, "status", 200),
        ok=200 <= getattr(response, "status", 200) < 300,
        payload=payload,
    )


def check_deployment_health(
    *,
    backend_health_url: str,
    trainer_health_url: str,
    model_url: str,
    viewer_url: str,
    timeout_seconds: float = 5.0,
) -> list[HealthCheckResult]:
    return [
        _fetch(backend_health_url, timeout_seconds),
        _fetch(trainer_health_url, timeout_seconds),
        _fetch(model_url, timeout_seconds),
        _fetch(viewer_url, timeout_seconds),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Check backend, trainer, and static resource health.")
    parser.add_argument("--backend-health-url", default="http://127.0.0.1:8000/health")
    parser.add_argument("--trainer-health-url", default="http://127.0.0.1:9000/health")
    parser.add_argument("--model-url", default="http://127.0.0.1:8000/storage/models/latest/model.ply")
    parser.add_argument("--viewer-url", default="http://127.0.0.1:8000/viewer/index.html")
    parser.add_argument("--timeout-seconds", type=float, default=5.0)
    args = parser.parse_args()

    results = check_deployment_health(
        backend_health_url=args.backend_health_url,
        trainer_health_url=args.trainer_health_url,
        model_url=args.model_url,
        viewer_url=args.viewer_url,
        timeout_seconds=args.timeout_seconds,
    )
    for result in results:
        print(f"{result.status_code} {result.url}")
    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
