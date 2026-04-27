# 均匀筛选文件并复制的脚本
# 功能：从大量文件中按均匀间隔选择指定数量的文件

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFolder,    # 源文件夹路径
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationFolder, # 目标文件夹路径
    
    [int]$FileCount = 150,    # 需要筛选的文件数量（默认150）
    
    [string]$Filter = "*.*"    # 文件筛选条件（默认所有文件）
)

# 获取所有文件列表
Write-Host "正在扫描源文件夹: $SourceFolder" -ForegroundColor Cyan
$allFiles = Get-ChildItem -Path $SourceFolder -Filter $Filter -File

$totalFiles = $allFiles.Count
Write-Host "找到文件总数: $totalFiles" -ForegroundColor Cyan

# 检查文件数量是否足够
if ($totalFiles -eq 0) {
    Write-Host "错误：源文件夹中没有找到文件！" -ForegroundColor Red
    exit 1
}

if ($totalFiles -lt $FileCount) {
    Write-Host "警告：源文件总数($totalFiles)少于需要筛选的数量($FileCount)" -ForegroundColor Yellow
    Write-Host "将复制所有文件" -ForegroundColor Yellow
    $FileCount = $totalFiles
}

# 计算均匀间隔并筛选文件
if ($FileCount -eq $totalFiles) {
    # 如果选择数量等于总数，全部复制
    $selectedFiles = $allFiles
} else {
    # 计算步长，确保均匀分布
    $step = ($totalFiles - 1) / ($FileCount - 1)
    $selectedFiles = @()
    
    for ($i = 0; $i -lt $FileCount; $i++) {
        $index = [Math]::Round($i * $step)
        $selectedFiles += $allFiles[$index]
    }
}

# 创建目标文件夹（如果不存在）
if (-not (Test-Path -Path $DestinationFolder)) {
    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
    Write-Host "创建目标文件夹: $DestinationFolder" -ForegroundColor Cyan
}

# 复制选中的文件
Write-Host "`n开始复制文件..." -ForegroundColor Cyan
$successCount = 0
$failCount = 0

foreach ($file in $selectedFiles) {
    $destPath = Join-Path -Path $DestinationFolder -ChildPath $file.Name
    
    try {
        Copy-Item -Path $file.FullName -Destination $destPath -Force
        Write-Host "✓ 已复制: $($file.Name)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "✗ 复制失败: $($file.Name) - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# 输出统计信息
Write-Host "`n========== 复制完成 ==========" -ForegroundColor Cyan
Write-Host "源文件夹: $SourceFolder" -ForegroundColor White
Write-Host "目标文件夹: $DestinationFolder" -ForegroundColor White
Write-Host "总文件数: $totalFiles" -ForegroundColor White
Write-Host "选中文件数: $($selectedFiles.Count)" -ForegroundColor White
Write-Host "成功复制: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "复制失败: $failCount" -ForegroundColor Red
}

# 可选：显示选中的文件名列表
Write-Host "`n选中的文件列表:" -ForegroundColor Cyan
$selectedFiles | ForEach-Object { Write-Host "  - $($_.Name)" }