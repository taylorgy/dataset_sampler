<#
.SYNOPSIS
根据源文件夹中的文件名，在多个指定文件夹中分别查找并复制同名文件

.DESCRIPTION
分别在每个搜索文件夹中查找同名文件，并按照搜索文件夹的名称分别保存到目标文件夹的子目录中
使用 -PreserveFolderStructure 时，会保留文件在搜索文件夹内的相对路径结构

搜索文件夹格式：
  可以指定扩展名，格式： "路径|扩展名"
  支持空格，会自动去除： "..\FSD\left\disparity | png" 会自动解析为路径和扩展名
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFolder,           # 源文件夹（读取文件名）
    
    [Parameter(Mandatory=$true)]
    [string[]]$SearchFolders,        # 要搜索的文件夹列表，支持 "路径|扩展名" 格式
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationFolder,      # 目标根文件夹
    
    [string]$FileFilter = "*.*",     # 源文件筛选条件
    
    [switch]$PreserveFolderStructure,   # 保留文件在搜索文件夹内的相对路径结构
    
    [switch]$Overwrite = $true       # 是否覆盖已存在文件
)

$ErrorActionPreference = "Continue"

# 解析路径为绝对路径
function Resolve-PathSafe {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path.TrimEnd('\')
    } else {
        return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path)).TrimEnd('\')
    }
}

# 获取路径的末端文件夹名称（用于目标子文件夹名）
function Get-EndFolderName {
    param([string]$Path)
    $cleanPath = $Path.TrimEnd('\')
    $folderName = Split-Path -Path $cleanPath -Leaf
    return $folderName
}

# 解析搜索文件夹配置（自动去除空格）
function Parse-SearchFolder {
    param([string]$SearchFolderSpec)
    
    # 去除首尾空格
    $cleanSpec = $SearchFolderSpec.Trim()
    
    # 查找 | 分隔符
    $pipeIndex = $cleanSpec.IndexOf('|')
    
    if ($pipeIndex -ge 0) {
        # 分离路径和扩展名，并去除各自的首尾空格
        $folderPath = $cleanSpec.Substring(0, $pipeIndex).Trim()
        $extension = $cleanSpec.Substring($pipeIndex + 1).Trim()
        
        # 如果扩展名为空，则设为 $null
        if ([string]::IsNullOrEmpty($extension)) {
            $extension = $null
        } else {
            # 确保扩展名没有前导点
            $extension = $extension.TrimStart('.')
        }
    } else {
        # 没有分隔符，整个字符串作为路径
        $folderPath = $cleanSpec
        $extension = $null
    }
    
    return @{
        Path = $folderPath
        Extension = $extension
    }
}

# 颜色输出函数
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# 解析所有路径
$SourceFolderAbs = Resolve-PathSafe -Path $SourceFolder
$DestinationFolderAbs = Resolve-PathSafe -Path $DestinationFolder

Write-ColorOutput "当前工作目录: $(Get-Location)" "Cyan"
Write-ColorOutput "源文件夹: $SourceFolderAbs" "Cyan"
Write-ColorOutput "目标根文件夹: $DestinationFolderAbs" "Cyan"
Write-ColorOutput "保留文件夹结构: $PreserveFolderStructure" "Cyan"
Write-ColorOutput ""

# 获取源文件的扩展名（作为默认）
$sourceExtension = $null
$firstSourceFile = Get-ChildItem -Path $SourceFolderAbs -File | Select-Object -First 1
if ($firstSourceFile) {
    $sourceExtension = $firstSourceFile.Extension.TrimStart('.')
    Write-ColorOutput "源文件扩展名（默认）: .$sourceExtension" "Cyan"
}
Write-ColorOutput ""

# 验证源文件夹
if (-not (Test-Path $SourceFolderAbs)) {
    Write-ColorOutput "错误：源文件夹不存在 - $SourceFolderAbs" "Red"
    exit 1
}

# 验证搜索文件夹并创建对应的目标子文件夹
$searchFolderConfigs = @()

foreach ($searchFolderSpec in $SearchFolders) {
    $parsed = Parse-SearchFolder -SearchFolderSpec $searchFolderSpec
    $searchFolder = $parsed.Path
    $specifiedExtension = $parsed.Extension
    
    # 显示原始输入和解析结果（用于调试）
    Write-ColorOutput "解析配置: '$searchFolderSpec'" "Gray"
    Write-ColorOutput "  -> 路径: '$searchFolder'" "Gray"
    if ($specifiedExtension) {
        Write-ColorOutput "  -> 扩展名: '.$specifiedExtension'" "Gray"
    } else {
        Write-ColorOutput "  -> 扩展名: 使用默认" "Gray"
    }
    
    $searchFolderAbs = Resolve-PathSafe -Path $searchFolder
    
    if (Test-Path $searchFolderAbs) {
        # 确定使用的扩展名
        $useExtension = if ($specifiedExtension) { 
            $specifiedExtension.TrimStart('.')
        } else { 
            $sourceExtension 
        }
        
        # 获取末端文件夹名称（用于目标文件夹名）
        $folderName = Get-EndFolderName -Path $searchFolderAbs
        
        # 目标基础路径：只使用末端文件夹名
        $destBasePath = Join-Path -Path $DestinationFolderAbs -ChildPath $folderName
        
        # 创建基础目标文件夹
        if (-not (Test-Path $destBasePath)) {
            New-Item -Path $destBasePath -ItemType Directory -Force | Out-Null
        }
        
        $searchFolderConfigs += @{
            SearchPath = $searchFolderAbs
            DestBasePath = $destBasePath
            FolderName = $folderName
            Extension = $useExtension
            OriginalSpec = $searchFolderSpec
        }
        
        $extInfo = if ($specifiedExtension) { "（指定: .$useExtension）" } else { "（默认: .$useExtension）" }
        Write-ColorOutput "✓ 搜索路径: $searchFolderAbs" "Green"
        Write-ColorOutput "  └─ 目标文件夹: $destBasePath" "Gray"
        Write-ColorOutput "  └─ 扩展名: .$useExtension $extInfo" "Green"
    } else {
        Write-ColorOutput "✗ 警告：搜索路径不存在 - $searchFolder" "Yellow"
    }
    Write-ColorOutput ""  # 空行分隔
}

if ($searchFolderConfigs.Count -eq 0) {
    Write-ColorOutput "错误：没有有效的搜索路径" "Red"
    exit 1
}

# 获取源文件列表
$sourceFiles = Get-ChildItem -Path $SourceFolderAbs -Filter $FileFilter -File
$totalFiles = $sourceFiles.Count

if ($totalFiles -eq 0) {
    Write-ColorOutput "错误：源文件夹中没有找到文件" "Red"
    exit 1
}

Write-ColorOutput "找到 $totalFiles 个参考文件" "Green"
Write-ColorOutput "将在 $($searchFolderConfigs.Count) 个搜索路径中查找并分别保存`n" "Cyan"

# 初始化统计
$stats = @{}
foreach ($config in $searchFolderConfigs) {
    $stats[$config.SearchPath] = @{
        Found = 0
        Copied = 0
        Failed = 0
        NotFound = 0
    }
}
$totalFound = 0
$totalCopied = 0

# 处理每个文件
$fileIndex = 0
foreach ($file in $sourceFiles) {
    $fileIndex++
    $fileName = $file.Name
    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    
    Write-ColorOutput "[$fileIndex/$totalFiles] 查找文件: $fileName" "White"
    
    # 在每个搜索文件夹中分别查找
    foreach ($config in $searchFolderConfigs) {
        $searchPath = $config.SearchPath
        $destBasePath = $config.DestBasePath
        $folderName = $config.FolderName
        $targetExtension = $config.Extension
        
        # 根据配置的扩展名构建要查找的文件名
        $searchFileName = if ($targetExtension) { 
            "$fileBaseName.$targetExtension" 
        } else { 
            $fileName 
        }
        
        Write-ColorOutput "  在 [$folderName] 中查找: $searchFileName" "Gray"
        
        # 在搜索路径中递归查找文件
        $foundFile = Get-ChildItem -Path $searchPath -Recurse -File | 
                     Where-Object { $_.Name -eq $searchFileName } | 
                     Select-Object -First 1
        
        if ($foundFile) {
            $stats[$config.SearchPath].Found++
            $totalFound++
            
            # 确定最终目标路径
            $finalDestFolder = $destBasePath
            
            if ($PreserveFolderStructure) {
                # 获取文件相对于搜索路径的目录部分
                $fileDir = $foundFile.DirectoryName
                
                # 计算相对路径（移除搜索路径部分）
                if ($fileDir.Length -gt $searchPath.Length) {
                    $relativeDir = $fileDir.Substring($searchPath.Length).TrimStart('\')
                    if ($relativeDir) {
                        $finalDestFolder = Join-Path -Path $destBasePath -ChildPath $relativeDir
                    }
                }
                
                # 创建目标子文件夹
                if (-not (Test-Path $finalDestFolder)) {
                    New-Item -Path $finalDestFolder -ItemType Directory -Force | Out-Null
                    Write-ColorOutput "    创建子文件夹: $relativeDir" "Gray"
                }
            }
            
            # 目标文件名（保持找到的文件名，可能扩展名不同）
            $destFile = Join-Path -Path $finalDestFolder -ChildPath $searchFileName
            
            # 复制文件
            try {
                Copy-Item -Path $foundFile.FullName -Destination $destFile -Force:$Overwrite -ErrorAction Stop
                $stats[$config.SearchPath].Copied++
                $totalCopied++
                
                # 显示成功信息
                $extChange = if ($targetExtension -and $targetExtension -ne $sourceExtension) { 
                    "（扩展名: .$sourceExtension -> .$targetExtension）" 
                } else { "" }
                
                if ($PreserveFolderStructure -and ($finalDestFolder -ne $destBasePath)) {
                    $relativeDisplay = $finalDestFolder.Substring($destBasePath.Length).TrimStart('\')
                    Write-ColorOutput "    ✓ 已复制到: $relativeDisplay $extChange" "Green"
                } else {
                    Write-ColorOutput "    ✓ 已复制 $extChange" "Green"
                }
            } catch {
                $stats[$config.SearchPath].Failed++
                Write-ColorOutput "    ✗ 复制失败: $($_.Exception.Message)" "Red"
            }
        } else {
            $stats[$config.SearchPath].NotFound++
            Write-ColorOutput "    ✗ 未找到: $searchFileName" "Red"
        }
    }
    Write-ColorOutput ""
}

# 输出统计报告
Write-ColorOutput "`n========== 复制完成 ==========" "Cyan"
Write-ColorOutput "源文件夹: $SourceFolderAbs" "White"
Write-ColorOutput "源文件扩展名: .$sourceExtension" "White"
Write-ColorOutput "目标根文件夹: $DestinationFolderAbs" "White"
Write-ColorOutput "保留文件夹结构: $PreserveFolderStructure" "White"
Write-ColorOutput "`n详细统计:" "Cyan"

foreach ($config in $searchFolderConfigs) {
    $stat = $stats[$config.SearchPath]
    Write-ColorOutput "  [$($config.FolderName)]" "Yellow"
    Write-ColorOutput "    搜索路径: $($config.SearchPath)" "Gray"
    Write-ColorOutput "    目标路径: $($config.DestBasePath)" "Gray"
    Write-ColorOutput "    查找扩展名: .$($config.Extension)" "Gray"
    Write-ColorOutput "    找到文件: $($stat.Found)" "Green"
    Write-ColorOutput "    成功复制: $($stat.Copied)" "Green"
    if ($stat.NotFound -gt 0) {
        Write-ColorOutput "    未找到: $($stat.NotFound)" "Yellow"
    }
    if ($stat.Failed -gt 0) {
        Write-ColorOutput "    复制失败: $($stat.Failed)" "Red"
    }
    Write-ColorOutput ""
}

Write-ColorOutput "总计:" "Cyan"
Write-ColorOutput "  源文件总数: $totalFiles" "White"
Write-ColorOutput "  总匹配次数: $totalFound" "Green"
Write-ColorOutput "  总复制成功: $totalCopied" "Green"

# 导出报告
if ($totalCopied -gt 0) {
    $reportPath = Join-Path -Path $DestinationFolderAbs -ChildPath "copy_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $report = @"
文件复制报告
生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
源文件夹: $SourceFolderAbs
源文件扩展名: .$sourceExtension
目标根文件夹: $DestinationFolderAbs
保留文件夹结构: $PreserveFolderStructure

搜索配置:
$(
    foreach ($config in $searchFolderConfigs) {
        @"
  [$($config.FolderName)]
    搜索路径: $($config.SearchPath)
    目标路径: $($config.DestBasePath)
    查找扩展名: .$($config.Extension)
    找到: $($stats[$config.SearchPath].Found)
    复制: $($stats[$config.SearchPath].Copied)
"@
    }
)

总计:
  源文件总数: $totalFiles
  总匹配次数: $totalFound
  总复制成功: $totalCopied
"@

    $report | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`n详细报告已保存到: $reportPath" "Cyan"
}