<#
功能：
- 按 task_id 导出单个任务的分享包，方便上传到网盘后给团队成员下载使用。
- 默认导出“只查看包”，只包含任务 JSON 和模型目录，适合直接在手机页面查看商品和打开 viewer。
- 也支持导出“完整调试包”，额外包含 processed / uploads，适合继续排查日志、Masking、中间产物和原视频。

导出模式：
- view（默认）：
  - storage/tasks/<task_id>.json
  - storage/models/<task_id>/
- full：
  - storage/tasks/<task_id>.json
  - storage/models/<task_id>/
  - storage/processed/<task_id>/
  - storage/uploads/<task_id>/

使用方法：
1. 默认导出“只查看包”
   powershell -ExecutionPolicy Bypass -File .\scripts\export_single_task.ps1 -TaskId task_20260408_211120_e7184d

2. 导出“完整调试包”
   powershell -ExecutionPolicy Bypass -File .\scripts\export_single_task.ps1 -TaskId task_20260408_211120_e7184d -PackageType full

3. 自定义输出目录
   powershell -ExecutionPolicy Bypass -File .\scripts\export_single_task.ps1 -TaskId task_20260408_211120_e7184d -OutputRoot D:\share

输出结果：
- 默认输出到 outputs/task_exports/<task_id>-<package_type>/
- 脚本会同时生成 export_manifest.json，记录本次导出的内容

给队友的使用方式：
- 队友下载并解压后，把其中的 storage 目录放到项目根目录
- 然后启动后端，并把手机 App 的 API_BASE_URL 指向他们自己的后端地址
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskId,

    [ValidateSet("view", "full")]
    [string]$PackageType = "view",

    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
function Resolve-RepoPath {
    param(
        [string]$RawValue,
        [string]$RepoRoot,
        [string]$DefaultRelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RawValue)) {
        return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $DefaultRelativePath))
    }

    if ([System.IO.Path]::IsPathRooted($RawValue)) {
        return [System.IO.Path]::GetFullPath($RawValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $RawValue))
}

$storageRoot = Resolve-RepoPath -RawValue $env:STORAGE_ROOT -RepoRoot $repoRoot -DefaultRelativePath "storage"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot "outputs\task_exports"
}

$outputRootFull = [System.IO.Path]::GetFullPath($OutputRoot)
$packageName = "$TaskId-$PackageType"
$packageRoot = Join-Path $outputRootFull $packageName
$packageStorageRoot = Join-Path $packageRoot "storage"

$taskFile = Join-Path $storageRoot "tasks\$TaskId.json"
$modelDir = Join-Path $storageRoot "models\$TaskId"
$processedDir = Join-Path $storageRoot "processed\$TaskId"
$uploadDir = Join-Path $storageRoot "uploads\$TaskId"

function Require-Path {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label 不存在：$Path"
    }
}

function Ensure-CleanDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $allowedFull = [System.IO.Path]::GetFullPath($AllowedRoot)

    if (-not $targetFull.StartsWith($allowedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝删除输出目录之外的路径：$targetFull"
    }

    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }

    New-Item -ItemType Directory -Path $targetFull -Force | Out-Null
}

function Copy-Entry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationParent
    )

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationParent -Recurse -Force
}

Require-Path -Path $taskFile -Label "任务 JSON"
Require-Path -Path $modelDir -Label "模型目录"

Ensure-CleanDirectory -TargetPath $packageRoot -AllowedRoot $outputRootFull

New-Item -ItemType Directory -Force `
    (Join-Path $packageStorageRoot "tasks"), `
    (Join-Path $packageStorageRoot "models") | Out-Null

Copy-Entry -SourcePath $taskFile -DestinationParent (Join-Path $packageStorageRoot "tasks")
Copy-Entry -SourcePath $modelDir -DestinationParent (Join-Path $packageStorageRoot "models")

if ($PackageType -eq "full") {
    New-Item -ItemType Directory -Force `
        (Join-Path $packageStorageRoot "processed"), `
        (Join-Path $packageStorageRoot "uploads") | Out-Null

    if (Test-Path -LiteralPath $processedDir) {
        Copy-Entry -SourcePath $processedDir -DestinationParent (Join-Path $packageStorageRoot "processed")
    }
    else {
        Write-Warning "未找到 processed 目录，已跳过：$processedDir"
    }

    if (Test-Path -LiteralPath $uploadDir) {
        Copy-Entry -SourcePath $uploadDir -DestinationParent (Join-Path $packageStorageRoot "uploads")
    }
    else {
        Write-Warning "未找到 uploads 目录，已跳过：$uploadDir"
    }
}

$manifest = [ordered]@{
    task_id = $TaskId
    package_type = $PackageType
    exported_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
    package_root = $packageRoot
    includes = @(
        "storage/tasks/$TaskId.json"
        "storage/models/$TaskId"
    )
}

if ($PackageType -eq "full") {
    $manifest.includes += @(
        "storage/processed/$TaskId"
        "storage/uploads/$TaskId"
    )
}

$manifestPath = Join-Path $packageRoot "export_manifest.json"
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "导出完成：" -ForegroundColor Green
Write-Host "  TaskId      : $TaskId"
Write-Host "  PackageType : $PackageType"
Write-Host "  Output      : $packageRoot"
Write-Host ""
Write-Host "建议下一步：" -ForegroundColor Yellow
Write-Host "  1. 压缩整个目录：$packageRoot"
Write-Host "  2. 队友解压到项目根目录后启动后端"
Write-Host "  3. 手机 App 的 API_BASE_URL 指向他们自己的后端地址"
