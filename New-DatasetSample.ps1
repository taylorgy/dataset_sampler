<#
.SYNOPSIS
    一步完成数据集采样：自动发现子路径 + 抽样 + 补全

.DESCRIPTION
    自动扫描 RawsetRoot 找到第一个包含文件的位置（根目录或子路径），
    从中抽样 FileCount 个文件到 SubsetRoot，
    再补全其余子文件夹中的所有同名文件。

    等价于顺序执行 Select-DatasetSample + Complete-DatasetSample，
    无需中间手动步骤。

.PARAMETER RawsetRoot
    源数据集根目录

.PARAMETER SubsetRoot
    子集输出根目录

.PARAMETER FileCount
    采样数量，默认 150

.PARAMETER Random
    启用随机抽样。不指定时使用均匀等距抽样

.EXAMPLE
    .\New-DatasetSample.ps1 -RawsetRoot "datasets\fsd" -SubsetRoot "subset" -FileCount 200

.EXAMPLE
    .\New-DatasetSample.ps1 -RawsetRoot "datasets\kitti" -SubsetRoot "subset" -FileCount 50 -Random

.EXAMPLE
    .\New-DatasetSample.ps1 -RawsetRoot "datasets\flat" -SubsetRoot "subset" -FileCount 50 -Random
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RawsetRoot,

    [Parameter(Mandatory = $true)]
    [string]$SubsetRoot,

    [int]$FileCount = 150,

    [switch]$Random
)

$ErrorActionPreference = "Continue"

$rawsetAbs = (Resolve-Path -Path $RawsetRoot -ErrorAction Stop).Path

# ----- 自动发现 SourcePath -----
function Find-FirstLeafDir {
    param([string]$Root)
    $dirs = Get-ChildItem -Path $Root -Directory
    # 无子目录时，退化到根目录自身
    if ($dirs.Count -eq 0) {
        $rootFiles = Get-ChildItem -Path $Root -File | Select-Object -First 1
        if ($rootFiles) { return @{ Path = ""; FullPath = $Root } }
        return $null
    }
    $dirs = $dirs | Sort-Object Name
    foreach ($dir in $dirs) {
        $path = $dir.Name
        $current = $dir
        while ($true) {
            $hasFiles = Get-ChildItem -Path $current.FullName -File | Select-Object -First 1
            if ($hasFiles) { return @{ Path = $path; FullPath = $current.FullName } }
            $subDirs = Get-ChildItem -Path $current.FullName -Directory | Sort-Object Name
            if ($subDirs.Count -eq 0) { break }
            $current = $subDirs[0]
            $path = "$path\$($current.Name)"
        }
    }
    return $null
}

$source = Find-FirstLeafDir -Root $rawsetAbs
if ($null -eq $source) {
    Write-Error "无法发现有效子路径: $rawsetAbs"
    exit 1
}

$sourcePath = $source.Path
$sourceDir = $source.FullPath
Write-Host "采样路径: $sourceDir"

# ----- 抽样（逻辑同 Select-DatasetSample） -----
$allFiles = Get-ChildItem -Path $sourceDir -File
$totalFiles = $allFiles.Count

if ($totalFiles -eq 0) {
    Write-Error "采样路径中没有文件: $sourceDir"
    exit 1
}
Write-Host "文件总数: $totalFiles"

if ($totalFiles -lt $FileCount) {
    Write-Host "采样数 $FileCount 大于源文件数 $totalFiles，退出" -ForegroundColor Red
    exit 1
}

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

if (-not (Test-Path -Path $SubsetRoot)) {
    New-Item -Path $SubsetRoot -ItemType Directory -Force | Out-Null
}
$subsetAbs = (Resolve-Path -Path $SubsetRoot).Path

$destDir = Join-Path -Path $subsetAbs -ChildPath $sourcePath
if (-not (Test-Path -Path $destDir)) {
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
}

$failedCount = 0
foreach ($file in $selectedFiles) {
    $destFile = Join-Path -Path $destDir -ChildPath $file.Name
    try {
        Copy-Item -Path $file.FullName -Destination $destFile -Force
    }
    catch {
        Write-Host "  ✗ $($file.Name) — $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
    }
}

# ----- 补全 -----
$baseNames = @{}
foreach ($f in $selectedFiles) {
    $bn = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $baseNames[$bn] = $true
}

$sourceIndex = @{}
$allFiles = Get-ChildItem -Path $rawsetAbs -Recurse -File
foreach ($f in $allFiles) {
    $bn = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $sourceIndex.ContainsKey($bn)) {
        $sourceIndex[$bn] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $sourceIndex[$bn].Add($f)
}

$copiedCount = 0
foreach ($bn in $baseNames.Keys) {
    if (-not $sourceIndex.ContainsKey($bn)) { continue }
    foreach ($sourceFile in $sourceIndex[$bn]) {
        $relativePath = $sourceFile.FullName.Substring($rawsetAbs.Length).TrimStart('\')
        $destFile = Join-Path -Path $subsetAbs -ChildPath $relativePath
        if (-not (Test-Path -Path $destFile)) {
            $destDir = Split-Path -Path $destFile -Parent
            if (-not (Test-Path -Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
            try {
                Copy-Item -Path $sourceFile.FullName -Destination $destFile -Force
                $copiedCount++
            }
            catch {
                Write-Host "  ✗ $relativePath — $($_.Exception.Message)" -ForegroundColor Red
                $failedCount++
            }
        }
    }
}

$totalFilesInSubset = $FileCount + $copiedCount
Write-Host "`n========== 完成 =========="
Write-Host "子集路径: $subsetAbs"
Write-Host "子集统计: $($baseNames.Count) 组 / $($totalFilesInSubset) 文件"
if ($failedCount -gt 0) {
    Write-Host "异常: $failedCount" -ForegroundColor Red
}
