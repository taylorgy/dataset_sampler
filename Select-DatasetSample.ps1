<#
.SYNOPSIS
    从数据集子文件夹或根目录中均匀/随机抽样

.DESCRIPTION
    从 RawsetRoot\RawsetPath（或 RawsetRoot 根目录）中抽样 FileCount 个文件，
    复制到 SubsetRoot\RawsetPath（或 SubsetRoot 根目录）下。自动保留相对路径结构。

    支持均匀等距抽样（默认）和随机抽样（-Random）。
    若文件直接存放在 RawsetRoot 根目录，可省略 -RawsetPath。

    此脚本不修改源数据集，只复制文件到子集目录。

.PARAMETER RawsetRoot
    源数据集根目录

.PARAMETER SourcePath
    要采样的子路径，如 "left\rgb"。省略时从 RawsetRoot 根目录取样

.PARAMETER SubsetRoot
    子集输出根目录

.PARAMETER FileCount
    采样数量，默认 150。超过源文件总数时取全部文件

.PARAMETER Filter
    文件筛选通配符，默认 "*.*"

.PARAMETER Random
    启用随机抽样。不指定时使用均匀等距抽样

.EXAMPLE
    .\Select-DatasetSample.ps1 -RawsetRoot "datasets\fsd" -RawsetPath "left\rgb" -SubsetRoot "subset" -FileCount 200

.EXAMPLE
    .\Select-DatasetSample.ps1 -RawsetRoot "datasets\flat" -SubsetRoot "subset" -FileCount 50

.NOTES
    配合 Complete-DatasetSample.ps1 使用，可补全子集中的其他文件。
    配合 New-DatasetSample.ps1 使用，可一步到位完成全流程。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RawsetRoot,

    [string]$SourcePath = "",

    [Parameter(Mandatory = $true)]
    [string]$SubsetRoot,

    [int]$FileCount = 150,

    [string]$Filter = "*.*",

    [switch]$Random
)

$ErrorActionPreference = "Continue"

# 解析路径
$rawsetAbs = (Resolve-Path -Path $RawsetRoot -ErrorAction Stop).Path
$sourceDir = Join-Path -Path $rawsetAbs -ChildPath $SourcePath

if (-not (Test-Path -Path $sourceDir)) {
    Write-Error "源路径不存在: $sourceDir"
    exit 1
}

# 获取文件列表
Write-Host "采样路径: $sourceDir"
$allFiles = Get-ChildItem -Path $sourceDir -Filter $Filter -File
$totalFiles = $allFiles.Count
Write-Host "文件总数: $totalFiles"

if ($totalFiles -eq 0) {
    Write-Error "源路径中没有找到匹配的文件。筛选条件: $Filter"
    exit 1
}

if ($totalFiles -lt $FileCount) {
    Write-Host "采样数 $FileCount 大于源文件数 $totalFiles，退出" -ForegroundColor Red
    exit 1
}

# 抽样
if ($Random) {
    Write-Host "随机抽样: $FileCount"
    $selectedFiles = $allFiles | Get-Random -Count $FileCount
}
else {
    Write-Host "均匀抽样: $FileCount"
    if ($FileCount -eq $totalFiles) {
        $selectedFiles = $allFiles
    }
    elseif ($FileCount -eq 1) {
        $selectedFiles = @($allFiles[[Math]::Floor($totalFiles / 2)])
    }
    else {
        $step = ($totalFiles - 1) / ($FileCount - 1)
        $selectedFiles = for ($i = 0; $i -lt $FileCount; $i++) {
            $allFiles[[Math]::Round($i * $step)]
        }
    }
}

# 目标目录 = SubsetRoot + SourcePath
if (-not (Test-Path -Path $SubsetRoot)) {
    New-Item -Path $SubsetRoot -ItemType Directory -Force | Out-Null
}
$destDir = Join-Path -Path (Resolve-Path -Path $SubsetRoot).Path -ChildPath $SourcePath
if (-not (Test-Path -Path $destDir)) {
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
}

$failCount = 0

foreach ($file in $selectedFiles) {
    $destFile = Join-Path -Path $destDir -ChildPath $file.Name
    try {
        Copy-Item -Path $file.FullName -Destination $destFile -Force
    }
    catch {
        Write-Host "  ✗ $($file.Name) — $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

Write-Host "`n========== 完成 =========="
Write-Host "子集路径: $destDir"
Write-Host "子集统计: $($selectedFiles.Count)组"
if ($failCount -gt 0) {
    Write-Host "异常: $failCount" -ForegroundColor Red
}
