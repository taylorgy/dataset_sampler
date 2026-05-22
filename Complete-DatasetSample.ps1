<#
.SYNOPSIS
    根据已有子集文件，从源数据集中补全整个文件夹结构

.DESCRIPTION
    扫描 SubsetRoot 中的所有文件，提取文件名列表。
    在 RawsetRoot 中查找所有同名文件（任意扩展名、任意子目录），
    按原始相对路径补全到 SubsetRoot 中。
    已存在的文件自动跳过，不重复复制。

    此脚本专为结构化数据集设计，自动处理：
    - 不同扩展名（jpg/png/npy 等）
    - 不同子目录（rgb/disparity 等）
    - 深层嵌套路径

.PARAMETER RawsetRoot
    源数据集根目录

.PARAMETER SubsetRoot
    已有部分文件的子集目录

.EXAMPLE
    .\Complete-DatasetSample.ps1 -RawsetRoot "datasets\fsd" -SubsetRoot "subset"

.NOTES
    与 Select-DatasetSample.ps1 配合完成两步采样流程。
    也支持手动创建/删除文件后再次运行来补全或修正。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RawsetRoot,

    [Parameter(Mandatory = $true)]
    [string]$SubsetRoot
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path -Path $SubsetRoot)) {
    Write-Host "错误: 子集目录不存在 - $SubsetRoot" -ForegroundColor Red
    exit 1
}
$rawsetAbs = (Resolve-Path -Path $RawsetRoot).Path
$subsetAbs = (Resolve-Path -Path $SubsetRoot).Path

# Step 1: 扫描 SubsetRoot，获取所有 basename
Write-Host "正在扫描: $subsetAbs"
$selectedFiles = Get-ChildItem -Path $subsetAbs -Recurse -File
$baseNames = @{}
foreach ($f in $selectedFiles) {
    $bn = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $baseNames[$bn] = $true
}
Write-Host "样本数量: $($baseNames.Count)组"

if ($baseNames.Count -eq 0) {
    Write-Host "错误: 子集目录中没有文件 - $subsetAbs" -ForegroundColor Red
    exit 1
}

# Step 2: 建立 RawsetRoot 的文件索引（basename → 文件列表）
$sourceIndex = @{}
$allFiles = Get-ChildItem -Path $rawsetAbs -Recurse -File
foreach ($f in $allFiles) {
    $bn = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $sourceIndex.ContainsKey($bn)) {
        $sourceIndex[$bn] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $sourceIndex[$bn].Add($f)
}

# Step 3: 遍历 basename，补全缺失文件
$foundCount = 0
$copiedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($bn in $baseNames.Keys) {
    if (-not $sourceIndex.ContainsKey($bn)) { continue }

    foreach ($sourceFile in $sourceIndex[$bn]) {
        # 计算相对 RawsetRoot 的路径
        $relativePath = $sourceFile.FullName.Substring($rawsetAbs.Length).TrimStart('\')
        $destFile = Join-Path -Path $subsetAbs -ChildPath $relativePath

        if (Test-Path -Path $destFile) {
            $skippedCount++
        }
        else {
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
        $foundCount++
    }
}

Write-Host "`n========== 完成 =========="
Write-Host "子集路径: $subsetAbs"
Write-Host "子集统计: $($baseNames.Count)组 / $($foundCount)文件"
if ($failedCount -gt 0) {
    Write-Host "异常: $failedCount" -ForegroundColor Red
}
