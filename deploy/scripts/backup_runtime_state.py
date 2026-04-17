from __future__ import annotations

import argparse
import shutil
import tarfile
from datetime import datetime, timezone
from pathlib import Path


def _timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def _archive_tree(source: Path, destination: Path) -> Path:
    with tarfile.open(destination, "w:gz") as archive:
        archive.add(source, arcname=source.name)
    return destination


def backup_runtime_state(
    database_path: Path,
    backup_root: Path,
    *,
    model_root: Path | None = None,
    log_root: Path | None = None,
) -> list[Path]:
    timestamp = _timestamp()
    artifacts: list[Path] = []

    sqlite_dir = _ensure_dir(backup_root / "sqlite")
    sqlite_backup = sqlite_dir / f"{database_path.stem}_{timestamp}.db"
    shutil.copy2(database_path, sqlite_backup)
    artifacts.append(sqlite_backup)

    if model_root is not None and model_root.exists():
        model_dir = _ensure_dir(backup_root / "models")
        model_archive = model_dir / f"models_{timestamp}.tar.gz"
        artifacts.append(_archive_tree(model_root, model_archive))

    if log_root is not None and log_root.exists():
        log_dir = _ensure_dir(backup_root / "logs")
        log_archive = log_dir / f"logs_{timestamp}.tar.gz"
        artifacts.append(_archive_tree(log_root, log_archive))

    return artifacts


def main() -> int:
    parser = argparse.ArgumentParser(description="Backup database, model files, and logs.")
    parser.add_argument("--database", default="storage/db/business.db")
    parser.add_argument("--backup-root", default="storage/backups")
    parser.add_argument("--model-root", default="storage/models")
    parser.add_argument("--log-root", default="storage/logs")
    args = parser.parse_args()

    artifacts = backup_runtime_state(
        Path(args.database),
        Path(args.backup_root),
        model_root=Path(args.model_root),
        log_root=Path(args.log_root),
    )
    for artifact in artifacts:
        print(artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
