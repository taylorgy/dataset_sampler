<#
.SYNOPSIS
    为压缩文件生成文件列表文件

.DESCRIPTION
    扫描压缩文件内部结构，生成文件清单。
    默认生成 _filelist.txt（纯路径列表）和 _filelist.html（可折叠交互页面）。
    使用 -Tree 可额外生成 _filetree.txt（tree 字符画风格）。
    支持 tar、tar.gz、tar.bz2、tar.xz、zip 格式。
    若 _filelist.txt 已存在则从 txt 重建树，避免重复扫描压缩包。

.PARAMETER Path
    压缩文件路径或包含压缩文件的文件夹路径。默认为当前工作目录。

.PARAMETER Recurse
    当 Path 为文件夹时，是否递归扫描子文件夹中的压缩文件。

.PARAMETER OutputDir
    列表文件的输出目录。默认与压缩文件放在同一目录。

.PARAMETER Txt
    生成 _filelist.txt（纯路径列表）。若无 -Html 则只生成 txt。

.PARAMETER Html
    生成 _filelist.html（可折叠交互页面）。若无 -Txt 则只生成 html。

.PARAMETER Tree
    额外生成 _filetree.txt（tree 字符画风格，含文件夹计数）。

.EXAMPLE
    Export-ArchiveFileList -Path "D:\backups\archive.tar.gz"

.EXAMPLE
    Export-ArchiveFileList -Path "D:\downloads" -Recurse

.EXAMPLE
    Export-ArchiveFileList -Path "D:\data" -Tree
    生成 txt + html + tree 三种文件

.EXAMPLE
    Export-ArchiveFileList -Path "D:\data" -Txt
    只生成 _filelist.txt
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,
    [switch]$Recurse,
    [string]$OutputDir,
    [switch]$Txt,
    [switch]$Html,
    [switch]$Tree
)

$ErrorActionPreference = "Continue"

# 默认生成 txt 和 html
if (-not $Txt -and -not $Html) {
    $Txt = $true
    $Html = $true
}

$formatList = @()
if ($Txt) { $formatList += "txt" }
if ($Html) { $formatList += "html" }
if ($Tree) { $formatList += "tree" }
$formatStr = $formatList -join " + "

# ============================================================
# 初始化
# ============================================================

$tarFormats = @{
    '.tar'     = @{ Args = @('-tf') }
    '.tar.gz'  = @{ Args = @('-tzf') }
    '.tgz'     = @{ Args = @('-tzf') }
    '.tar.bz2' = @{ Args = @('-tjf') }
    '.tbz2'    = @{ Args = @('-tjf') }
    '.tar.xz'  = @{ Args = @('-tJf') }
    '.txz'     = @{ Args = @('-tJf') }
}

$allExtensions = @($tarFormats.Keys) + '.zip'

$successCount = 0
$skipCount = 0
$spinnerChars = @('|', '/', '-', '\')

# ============================================================
# 树结构（脚本级变量）
# ============================================================

$script:treeRoot = @{}
$script:rootFiles = @()
$script:allDirs = @{}
$script:totalFileCount = 0
$script:totalDirCount = 0

function Reset-Tree {
    $script:treeRoot = @{}
    $script:rootFiles = @()
    $script:allDirs = @{}
    $script:totalFileCount = 0
    $script:totalDirCount = 0
}

function Add-PathToTree {
    param([string]$RawPath)
    $raw = $RawPath.Trim().Replace('\', '/')
    if ($raw -eq '') { return }
    $isDir = $raw.EndsWith('/')
    $clean = $raw.TrimEnd('/')
    if ($clean -eq '') { return }
    $parts = $clean -split '/'

    if ($parts.Length -eq 1) {
        if ($isDir) {
            if (-not $script:treeRoot.ContainsKey($parts[0])) {
                $script:treeRoot[$parts[0]] = @{ Files = @{}; Dirs = @{} }
                $script:allDirs[$clean] = $script:treeRoot[$parts[0]]
            }
        }
        else {
            if ($script:rootFiles -notcontains $parts[0]) {
                $script:rootFiles += $parts[0]
            }
        }
        return
    }

    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $ancestorPath = ($parts[0..$i] -join '/')
        $parentPath = if ($i -eq 0) { $null } else { ($parts[0..($i - 1)] -join '/') }
        $name = $parts[$i]
        if (-not $script:allDirs.ContainsKey($ancestorPath)) {
            $newNode = @{ Files = @{}; Dirs = @{} }
            $script:allDirs[$ancestorPath] = $newNode
            if ($parentPath -eq $null) {
                $script:treeRoot[$name] = $newNode
            }
            else {
                $script:allDirs[$parentPath].Dirs[$name] = $newNode
            }
        }
    }

    $parentPath = ($parts[0..($parts.Length - 2)] -join '/')
    $lastName = $parts[-1]
    $parentNode = $script:allDirs[$parentPath]

    if ($isDir) {
        $dirPath = $clean
        if (-not $script:allDirs.ContainsKey($dirPath)) {
            $newNode = @{ Files = @{}; Dirs = @{} }
            $script:allDirs[$dirPath] = $newNode
            $parentNode.Dirs[$lastName] = $newNode
        }
    }
    else {
        if (-not $parentNode.Files.ContainsKey($lastName)) {
            $parentNode.Files[$lastName] = $true
        }
    }
}

# ============================================================
# 建树
# ============================================================

function New-TreeFromTar {
    param([string]$FilePath, [string]$FileExt)
    Reset-Tree
    $rawLines = [System.Collections.Generic.List[string]]::new()
    $entryCount = 0
    $spinnerIndex = 0
    $label = $FileExt.TrimStart('.')

    if ($FileExt -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        foreach ($entry in $zip.Entries) {
            $line = $entry.FullName
            $rawLines.Add($line)
            Add-PathToTree -RawPath $line
            $entryCount++
            $spinnerIndex = ($entryCount % 4)
            Write-Host -NoNewline "`r  从 $label 构建文件树：$entryCount 个条目  $($spinnerChars[$spinnerIndex])"
        }
        $zip.Dispose()
        Write-Host "`r  从 $label 构建文件树：$entryCount 个条目     "
        return @{ RawLines = $rawLines; EntryCount = $entryCount }
    }

    $tarArgs = $tarFormats[$FileExt].Args
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = "tar"
    $process.StartInfo.Arguments = "$($tarArgs -join ' ') `"$FilePath`""
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true
    $process.Start() | Out-Null

    $reader = $process.StandardOutput
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -ne $null -and $line.Trim() -ne '') {
            $rawLines.Add($line)
            Add-PathToTree -RawPath $line
            $entryCount++
            $spinnerIndex = ($entryCount % 4)
            Write-Host -NoNewline "`r  从 $label 构建文件树：$entryCount 个条目  $($spinnerChars[$spinnerIndex])"
        }
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $errorOutput = $process.StandardError.ReadToEnd()
        throw "tar 命令执行失败 (退出码: $($process.ExitCode)): $errorOutput"
    }
    Write-Host "`r  从 $label 构建文件树：$entryCount 个条目     "
    return @{ RawLines = $rawLines; EntryCount = $entryCount }
}

function New-TreeFromTxt {
    param([string]$TxtPath)
    Reset-Tree
    Write-Host -NoNewline "  从 txt 构建文件树..."
    $lines = Get-Content -Path $TxtPath -Encoding UTF8
    $entryCount = 0
    foreach ($line in $lines) {
        if ($line -eq '') { continue }
        if ($line.StartsWith('#')) { continue }
        if ($line.Trim() -eq '(空压缩包)') { continue }
        Add-PathToTree -RawPath $line.Trim()
        $entryCount++
    }
    Write-Host "`r  从 txt 构建文件树：$entryCount 个条目     "
    return $entryCount
}

# ============================================================
# 统计
# ============================================================

function Count-Node {
    param($node)
    $fCount = $node.Files.Count
    $dCount = $node.Dirs.Count
    foreach ($childDir in $node.Dirs.Values) {
        $sub = Count-Node $childDir
        $fCount += $sub.Files
        $dCount += $sub.Dirs
    }
    return @{ Files = $fCount; Dirs = $dCount }
}

function Finalize-TreeStats {
    $totalFiles = $script:rootFiles.Count
    $totalDirs = 0
    foreach ($dirNode in $script:treeRoot.Values) {
        $sub = Count-Node $dirNode
        $totalFiles += $sub.Files
        $totalDirs += $sub.Dirs
    }
    $totalDirs += $script:treeRoot.Count
    $script:totalFileCount = $totalFiles
    $script:totalDirCount = $totalDirs
}

# ============================================================
# 辅助
# ============================================================

function Get-BaseName {
    param([string]$FileName)
    $name = $FileName
    foreach ($ext in ($tarFormats.Keys | Sort-Object { $_.Length } -Descending)) {
        if ($name.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
            return $name.Substring(0, $name.Length - $ext.Length)
        }
    }
    if ($name.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        return $name.Substring(0, $name.Length - 4)
    }
    $dotIndex = $name.LastIndexOf('.')
    if ($dotIndex -gt 0) { return $name.Substring(0, $dotIndex) }
    return $name
}

function Get-FormattedCount {
    param([int]$FileCount, [int]$DirCount)
    if ($FileCount -eq 0 -and $DirCount -eq 0) { return '(空)' }
    $parts = @()
    if ($FileCount -gt 0) { $parts += "$FileCount 个文件" }
    if ($DirCount -gt 0) { $parts += "$DirCount 个文件夹" }
    return '(' + ($parts -join ', ') + ')'
}

function Get-PathsFromNode {
    param($node, [string]$Prefix)
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($dirName in ($node.Dirs.Keys | Sort-Object)) {
        $dirPath = "$Prefix$dirName/"
        $paths.Add($dirPath)
        $subPaths = Get-PathsFromNode -node $node.Dirs[$dirName] -Prefix $dirPath
        foreach ($sp in $subPaths) { $paths.Add($sp) }
    }
    foreach ($fn in ($node.Files.Keys | Sort-Object)) {
        $paths.Add("$Prefix$fn")
    }
    return $paths
}

# ============================================================
# Tree 字符画渲染（-Tree 时使用）
# ============================================================

function Render-TreeNode {
    param($node, [string]$Prefix, [string]$Name, [bool]$IsLast)
    $lines = @()
    $connector = if ($Name -ne '') { if ($IsLast) { '└── ' } else { '├── ' } } else { '' }
    $directFiles = $node.Files.Count
    $directDirs = $node.Dirs.Count
    $countStr = Get-FormattedCount -FileCount $directFiles -DirCount $directDirs
    if ($Name -ne '') { $lines += "$Prefix$connector$Name/ $countStr" }
    $childPrefix = $Prefix + $(if ($Name -ne '') { if ($IsLast) { '    ' } else { '│   ' } } else { '' })
    $sortedDirs = $node.Dirs.Keys | Sort-Object
    $sortedFiles = $node.Files.Keys | Sort-Object
    $totalChildren = $sortedDirs.Count + $sortedFiles.Count
    $idx = 0
    foreach ($dirName in $sortedDirs) {
        $idx++; $childIsLast = ($idx -eq $totalChildren)
        $lines += Render-TreeNode -node $node.Dirs[$dirName] -Prefix $childPrefix -Name $dirName -IsLast $childIsLast
    }
    foreach ($fileName in $sortedFiles) {
        $idx++; $childIsLast = ($idx -eq $totalChildren)
        $fileConnector = if ($childIsLast) { '└── ' } else { '├── ' }
        $lines += "$childPrefix$fileConnector$fileName"
    }
    return $lines
}

function Render-TreeFile {
    Finalize-TreeStats
    $lines = @()
    $rootDirs = $script:treeRoot.Keys | Sort-Object
    $totalRootItems = $rootDirs.Count + $script:rootFiles.Count
    $itemIndex = 0

    foreach ($dirName in $rootDirs) {
        $itemIndex++; $isLast = ($itemIndex -eq $totalRootItems)
        $connector = if ($isLast) { '└── ' } else { '├── ' }
        $childPrefix = if ($isLast) { '    ' } else { '│   ' }
        $node = $script:treeRoot[$dirName]
        $directFiles = $node.Files.Count; $directDirs = $node.Dirs.Count
        $countStr = Get-FormattedCount -FileCount $directFiles -DirCount $directDirs
        $lines += "$connector$dirName/ $countStr"
        $sortedSubDirs = $node.Dirs.Keys | Sort-Object
        $sortedSubFiles = $node.Files.Keys | Sort-Object
        $totalSub = $sortedSubDirs.Count + $sortedSubFiles.Count
        $subIdx = 0
        foreach ($subDirName in $sortedSubDirs) {
            $subIdx++; $subIsLast = ($subIdx -eq $totalSub)
            $lines += Render-TreeNode -node $node.Dirs[$subDirName] -Prefix $childPrefix -Name $subDirName -IsLast $subIsLast
        }
        foreach ($subFileName in $sortedSubFiles) {
            $subIdx++; $subIsLast = ($subIdx -eq $totalSub)
            $subConnector = if ($subIsLast) { '└── ' } else { '├── ' }
            $lines += "$childPrefix$subConnector$subFileName"
        }
    }
    $sortedRootFiles = $script:rootFiles | Sort-Object
    for ($i = 0; $i -lt $sortedRootFiles.Count; $i++) {
        $itemIndex++; $isLast = ($itemIndex -eq $totalRootItems)
        $connector = if ($isLast) { '└── ' } else { '├── ' }
        $lines += "$connector$($sortedRootFiles[$i])"
    }
    return $lines
}

# ============================================================
# HTML 生成
# ============================================================

function Get-FileIcon {
    param([string]$Extension)
    switch ($Extension.ToLower()) {
        'png' { return '🖼️' }
        'jpg' { return '🖼️' }
        'jpeg' { return '🖼️' }
        'gif' { return '🖼️' }
        'bmp' { return '🖼️' }
        'svg' { return '🖼️' }
        'txt' { return '📄' }
        'md' { return '📝' }
        'json' { return '📋' }
        'xml' { return '📋' }
        'csv' { return '📊' }
        'py' { return '🐍' }
        'ps1' { return '⚡' }
        'zip' { return '📦' }
        'tar' { return '📦' }
        'gz' { return '📦' }
        'bz2' { return '📦' }
        'xz' { return '📦' }
        'mp4' { return '🎬' }
        'avi' { return '🎬' }
        'mov' { return '🎬' }
        'mp3' { return '🎵' }
        'wav' { return '🎵' }
        'flac' { return '🎵' }
        'pdf' { return '📕' }
        default { return '📄' }
    }
}

function Write-HtmlNode {
    param($node, [string]$Name, [int]$Depth, [System.IO.StreamWriter]$Writer)
    $indent = '    ' * $Depth
    $id = "dir_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
    $directFiles = $node.Files.Count
    $directDirs = $node.Dirs.Count
    $countStr = Get-FormattedCount -FileCount $directFiles -DirCount $directDirs

    $Writer.WriteLine("$indent<li class=`"folder`">")
    $Writer.WriteLine("$indent    <span class=`"caret`" id=`"$id`" onclick=`"toggleNode(this)`">▶</span>")
    $Writer.WriteLine("$indent    <span class=`"folder-name`" onclick=`"toggleNode(document.getElementById('$id'))`">📁 $Name/</span>")
    $Writer.WriteLine("$indent    <span class=`"folder-stats`">$countStr</span>")

    if ($directDirs -gt 0 -or $directFiles -gt 0) {
        $Writer.WriteLine("$indent    <ul class=`"nested`">")
        $sortedDirs = $node.Dirs.Keys | Sort-Object
        foreach ($dirName in $sortedDirs) {
            Write-HtmlNode -node $node.Dirs[$dirName] -Name $dirName -Depth ($Depth + 2) -Writer $Writer
        }
        $sortedFiles = $node.Files.Keys | Sort-Object
        foreach ($fileName in $sortedFiles) {
            $ext = if ($fileName -match '\.(\w+)$') { $Matches[1] } else { '' }
            $icon = Get-FileIcon -Extension $ext
            $Writer.WriteLine("$indent        <li class=`"file`"><span class=`"file-icon`">$icon</span> $fileName</li>")
        }
        $Writer.WriteLine("$indent    </ul>")
    }
    $Writer.WriteLine("$indent</li>")
}

function New-Html {
    param([string]$ArchiveName, [string]$OutputPath)

    # 先统计
    Finalize-TreeStats

    # 用 StreamWriter 直接写文件，避免字符串拼接和管道泄漏
    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        $writer.WriteLine('<!DOCTYPE html>')
        $writer.WriteLine('<html lang="zh-CN">')
        $writer.WriteLine('<head>')
        $writer.WriteLine('<meta charset="UTF-8">')
        $writer.WriteLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
        $writer.WriteLine("<title>$ArchiveName 文件列表</title>")
        $writer.WriteLine('<style>')
        $writer.WriteLine('* { margin: 0; padding: 0; box-sizing: border-box; }')
        $writer.WriteLine("body { font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif; background: #1e1e1e; color: #d4d4d4; padding: 20px; min-height: 100vh; }")
        $writer.WriteLine('.header { background: #252526; border: 1px solid #3e3e42; border-radius: 8px; padding: 16px 20px; margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }')
        $writer.WriteLine('.header h1 { font-size: 18px; font-weight: 600; color: #e0e0e0; }')
        $writer.WriteLine('.header .stats { font-size: 13px; color: #9cdcfe; }')
        $writer.WriteLine('.buttons { display: flex; gap: 8px; flex-wrap: wrap; }')
        $writer.WriteLine('.buttons button { padding: 6px 14px; border: 1px solid #3e3e42; border-radius: 4px; background: #3c3c3c; color: #cccccc; cursor: pointer; font-size: 12px; transition: all 0.15s; }')
        $writer.WriteLine('.buttons button:hover { background: #505050; border-color: #007acc; color: #ffffff; }')
        $writer.WriteLine('.tree-container { background: #252526; border: 1px solid #3e3e42; border-radius: 8px; padding: 16px 20px; overflow-x: auto; }')
        $writer.WriteLine('ul { list-style: none; padding-left: 24px; }')
        $writer.WriteLine('.tree-container > ul { padding-left: 0; }')
        $writer.WriteLine('li { line-height: 1.8; white-space: nowrap; }')
        $writer.WriteLine('.caret { display: inline-block; width: 16px; cursor: pointer; user-select: none; color: #6a9955; font-size: 12px; transition: transform 0.15s; }')
        $writer.WriteLine('.caret.open { transform: rotate(90deg); }')
        $writer.WriteLine('.caret.empty { color: transparent; cursor: default; }')
        $writer.WriteLine('.folder-name { cursor: pointer; color: #dcdcaa; }')
        $writer.WriteLine('.folder-name:hover { color: #e8e8a0; text-decoration: underline; }')
        $writer.WriteLine('.folder-stats { color: #6a9955; font-size: 12px; margin-left: 6px; }')
        $writer.WriteLine('.file { color: #cccccc; }')
        $writer.WriteLine('.file-icon { margin-right: 4px; font-size: 14px; }')
        $writer.WriteLine('.nested { display: none; }')
        $writer.WriteLine('.nested.visible { display: block; }')
        $writer.WriteLine('.footer { margin-top: 16px; font-size: 11px; color: #6a6a6a; text-align: center; }')
        $writer.WriteLine('</style>')
        $writer.WriteLine('<script>')
        $writer.WriteLine('function toggleNode(el) { el.classList.toggle("open"); var nested = el.parentElement.querySelector(".nested"); if (nested) { nested.classList.toggle("visible"); } }')
        $writer.WriteLine('function expandAll() { document.querySelectorAll(".caret").forEach(function(c) { if (!c.classList.contains("empty")) c.classList.add("open"); }); document.querySelectorAll(".nested").forEach(function(n) { n.classList.add("visible"); }); }')
        $writer.WriteLine('function collapseAll() { document.querySelectorAll(".caret").forEach(function(c) { c.classList.remove("open"); }); document.querySelectorAll(".nested").forEach(function(n) { n.classList.remove("visible"); }); }')
        $writer.WriteLine('function collapseFiles() { (function collapse(ul) { ul.querySelectorAll(":scope > .folder").forEach(function(li) { var caret = li.querySelector(":scope > .caret"); var nested = li.querySelector(":scope > .nested"); if (nested) { var hasSubDir = nested.querySelector(".folder"); if (hasSubDir) { if (caret) caret.classList.add("open"); nested.classList.add("visible"); collapse(nested); } else { if (caret) caret.classList.remove("open"); nested.classList.remove("visible"); } } }); })(document.querySelector(".tree-container > ul")); }')
        $writer.WriteLine('</script>')
        $writer.WriteLine('</head>')
        $writer.WriteLine('<body onload="expandAll()">')
        $writer.WriteLine('<div class="header">')
        $writer.WriteLine('    <div>')
        $writer.WriteLine("        <h1>$ArchiveName 文件列表</h1>")
        $writer.WriteLine("        <div class=`"stats`">总文件数: $script:totalFileCount 个文件, $script:totalDirCount 个文件夹</div>")
        $writer.WriteLine('    </div>')
        $writer.WriteLine('    <div class="buttons">')
        $writer.WriteLine('        <button onclick="expandAll()">展开全部</button>')
        $writer.WriteLine('        <button onclick="collapseAll()">折叠全部</button>')
        $writer.WriteLine('        <button onclick="collapseFiles()">折叠文件</button>')
        $writer.WriteLine('    </div>')
        $writer.WriteLine('</div>')
        $writer.WriteLine('<div class="tree-container">')
        $writer.WriteLine('    <ul>')

        # 渲染树内容
        $rootDirs = @($script:treeRoot.Keys | Sort-Object)
        $sortedRootFiles = @($script:rootFiles | Sort-Object)

        foreach ($dirName in $rootDirs) {
            Write-Progress -Activity "生成 HTML" -Status "$dirName/" -PercentComplete -1
            Write-HtmlNode -node $script:treeRoot[$dirName] -Name $dirName -Depth 2 -Writer $writer
        }

        foreach ($fileName in $sortedRootFiles) {
            $ext = if ($fileName -match '\.(\w+)$') { $Matches[1] } else { '' }
            $icon = Get-FileIcon -Extension $ext
            $writer.WriteLine("        <li class=`"file`"><span class=`"file-icon`">$icon</span> $fileName</li>")
        }

        Write-Progress -Activity "生成 HTML" -Completed

        $writer.WriteLine('    </ul>')
        $writer.WriteLine('</div>')
        $writer.WriteLine('<div class="footer">由 Export-ArchiveFileList 生成</div>')
        $writer.WriteLine('</body>')
        $writer.WriteLine('</html>')
    }
    finally {
        $writer.Close()
        $writer.Dispose()
    }
}

# ============================================================
# 步骤1：解析路径
# ============================================================

if (-not $Path) {
    $Path = $PWD.Path
}

$targetFiles = @()

if (Test-Path -Path $Path -PathType Leaf) {
    $targetFiles = @(Get-Item -Path $Path)
}
elseif (Test-Path -Path $Path -PathType Container) {
    Write-Host "扫描文件夹: $Path"
    $getParams = @{ Path = $Path; File = $true }
    if ($Recurse) { $getParams['Recurse'] = $true }
    $allFiles = Get-ChildItem @getParams
    $targetFiles = $allFiles | Where-Object {
        $fullName = $_.Name
        foreach ($ext in $allExtensions) {
            if ($fullName.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    if ($targetFiles.Count -eq 0) {
        Write-Host "未发现支持的压缩文件，退出"
        return
    }
    Write-Host "发现 $($targetFiles.Count) 个压缩文件待处理"
    Write-Host ""
}
else {
    Write-Error "路径不存在: $Path"
    return
}

# ============================================================
# 步骤2：逐文件处理
# ============================================================

$totalCount = $targetFiles.Count
$currentIndex = 0

foreach ($file in $targetFiles) {
    $currentIndex++
    $filePath = $file.FullName
    $fileName = $file.Name

    $progressPrefix = if ($totalCount -gt 1) { "[$currentIndex/$totalCount] " } else { "" }

    $baseName = Get-BaseName -FileName $fileName
    $targetDir = if ($OutputDir) { $OutputDir } else { $file.DirectoryName }
    $txtOutputFile = Join-Path $targetDir "$baseName`_filelist.txt"
    $htmlOutputFile = Join-Path $targetDir "$baseName`_filelist.html"
    $treeOutputFile = Join-Path $targetDir "$baseName`_filetree.txt"

    $txtExists = Test-Path $txtOutputFile
    $htmlExists = Test-Path $htmlOutputFile
    $treeExists = if ($Tree) { Test-Path $treeOutputFile } else { $true }

    $needTxt = $Txt -and (-not $txtExists)
    $needHtml = $Html -and (-not $htmlExists)
    $needTree = $Tree -and (-not $treeExists)
    $needBuild = $needTxt -or $needHtml -or $needTree

    # 输出头部
    Write-Host "正在处理: $progressPrefix$fileName"

    if (-not $needBuild) {
        Write-Host "  所需文件已存在，跳过"
        $skipCount++
        Write-Host ""
        continue
    }

    # 识别扩展名
    $fileExt = $null
    foreach ($ext in ($allExtensions | Sort-Object { $_.Length } -Descending)) {
        if ($fileName.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
            $fileExt = $ext
            break
        }
    }

    if (-not $fileExt) {
        Write-Host "  已跳过: 无法识别的格式"
        $skipCount++
        Write-Host ""
        continue
    }

    # 建树
    $rawLines = $null
    $entryCount = 0
    $treeSource = ""

    if ($txtExists) {
        try {
            $entryCount = New-TreeFromTxt -TxtPath $txtOutputFile
            $treeSource = "txt"
        }
        catch {
            Write-Host "  从 txt 重建失败: $_，改为重新扫描..."
            $treeSource = ""
        }
    }

    if ($treeSource -ne "txt") {
        try {
            $result = New-TreeFromTar -FilePath $filePath -FileExt $fileExt
            $rawLines = $result.RawLines
            $entryCount = $result.EntryCount
            $treeSource = $fileExt.TrimStart('.')
        }
        catch {
            Write-Host "  错误: $_" -ForegroundColor Red
            $skipCount++
            Write-Host ""
            continue
        }
    }

    # 空压缩包
    if ($entryCount -eq 0) {
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        if ($needTxt) {
            $content = @("# $fileName 文件列表", "# 总文件数: 0  总文件夹数: 0", "", "(空压缩包)")
            [System.IO.File]::WriteAllLines($txtOutputFile, $content, [System.Text.UTF8Encoding]::new($false))
        }
        if ($needHtml) {
            $script:totalFileCount = 0; $script:totalDirCount = 0
            New-Html -ArchiveName $fileName -OutputPath $htmlOutputFile
        }
        if ($needTree) {
            $treeContent = @("$fileName 文件列表", "", "总文件数: 0 个文件, 0 个文件夹", "", "(空压缩包)")
            [System.IO.File]::WriteAllLines($treeOutputFile, $treeContent, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host "  文件统计: 0 个文件, 0 个文件夹"
        $successCount++
        Write-Host ""
        continue
    }

    # 确保输出目录存在
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # 输出 _filelist.txt
    if ($needTxt) {
        if ($rawLines) {
            $txtContent = @("# $fileName 文件列表", "# 总文件数: $script:totalFileCount  总文件夹数: $script:totalDirCount", "") + $rawLines
            [System.IO.File]::WriteAllLines($txtOutputFile, $txtContent, [System.Text.UTF8Encoding]::new($false))
        }
        else {
            Finalize-TreeStats
            $txtContent = [System.Collections.Generic.List[string]]::new()
            $txtContent.Add("# $fileName 文件列表")
            $txtContent.Add("# 总文件数: $script:totalFileCount  总文件夹数: $script:totalDirCount")
            $txtContent.Add("")

            foreach ($dirName in ($script:treeRoot.Keys | Sort-Object)) {
                $txtContent.Add("$dirName/")
                $subPaths = Get-PathsFromNode -node $script:treeRoot[$dirName] -Prefix "$dirName/"
                foreach ($sp in $subPaths) { $txtContent.Add($sp) }
            }
            foreach ($f in ($script:rootFiles | Sort-Object)) {
                $txtContent.Add($f)
            }
            [System.IO.File]::WriteAllLines($txtOutputFile, $txtContent, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # 输出 _filelist.html（StreamWriter 直接写文件，无泄漏）
    if ($needHtml) {
        Write-Host -NoNewline "  正在生成 html..."
        New-Html -ArchiveName $fileName -OutputPath $htmlOutputFile
        Write-Host "`r  已生成 html                    "
    }

    # 输出 _filetree.txt
    if ($needTree) {
        Write-Host -NoNewline "  正在生成 tree..."
        Finalize-TreeStats
        $treeLines = Render-TreeFile
        $treeContent = @("$fileName 文件列表", "", "总文件数: $script:totalFileCount 个文件, $script:totalDirCount 个文件夹", "") + $treeLines
        [System.IO.File]::WriteAllLines($treeOutputFile, $treeContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "`r  已生成 tree                    "
    }

    # 确保统计已计算
    if (-not $needTree -and -not $needHtml) {
        Finalize-TreeStats
    }

    Write-Host "  文件统计: $script:totalFileCount 个文件, $script:totalDirCount 个文件夹"
    $successCount++
    Write-Host ""
}

# ============================================================
# 步骤3：汇总
# ============================================================

$finalOutputDir = if ($OutputDir) { $OutputDir } elseif (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-Item -LiteralPath $Path).DirectoryName } else { (Resolve-Path -Path $Path).Path }

Write-Host "`n========== 完成 =========="
Write-Host "导出路径: $finalOutputDir"
Write-Host "导出格式: $formatStr"
Write-Host "导出统计: $successCount 成功 / $skipCount 跳过"
