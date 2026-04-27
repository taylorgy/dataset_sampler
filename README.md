# 文件处理脚本使用说明

本工具包包含 PowerShell 脚本，用于批量文件筛选和智能复制操作。

## 脚本列表

| 脚本名称 | 功能描述 |
|---------|---------|
| `Copy-FilesEvenly.ps1` | 从大量文件中均匀筛选指定数量的文件并复制 |
| `FindAndCopy.ps1` | 根据源文件名在多个文件夹中查找同名文件并分别保存 |

---

## 一、Copy-FilesEvenly.ps1 - 均匀筛选文件

### 功能说明
从一个包含大量文件的文件夹中，按均匀间隔筛选出指定数量的文件并复制到目标文件夹。

### 适用场景
- 需要从数千个文件中抽取样本
- 希望保持文件的顺序分布（而非随机抽取）
- 需要定期从大文件中选取测试集

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `-SourceFolder` | string | ✅ | 源文件夹路径 |
| `-DestinationFolder` | string | ✅ | 目标文件夹路径 |
| `-FileCount` | int | ❌ | 需要筛选的文件数量（默认：150） |
| `-Filter` | string | ❌ | 文件筛选条件（默认：`*.*`） |

### 使用示例

#### 基本用法
```powershell
.\Copy-FilesEvenly.ps1 -SourceFolder "C:\images\original" -DestinationFolder "C:\images\sample"
```

#### 指定筛选数量
```powershell
.\Copy-FilesEvenly.ps1 -SourceFolder "C:\images\original" -DestinationFolder "C:\images\sample" -FileCount 200
```

#### 只复制特定类型文件
```powershell
.\Copy-FilesEvenly.ps1 -SourceFolder "C:\images\original" -DestinationFolder "C:\images\sample" -Filter "*.jpg"
```

#### 使用相对路径
```powershell
.\Copy-FilesEvenly.ps1 -SourceFolder ".\data\original" -DestinationFolder ".\data\selected" -FileCount 100
```

### 工作原理
1. 扫描源文件夹中的所有文件
2. 计算均匀分布的步长：`步长 = (总文件数 - 1) / (目标数量 - 1)`
3. 按步长选取文件（例如：第0个、第N个、第2N个...）
4. 复制选中的文件到目标文件夹

### 输出示例
```
正在扫描源文件夹: C:\images\original
找到文件总数: 2500

开始复制文件...
✓ 已复制: 0000.jpg
✓ 已复制: 0017.jpg
✓ 已复制: 0034.jpg
...

========== 复制完成 ==========
源文件夹: C:\images\original
目标文件夹: C:\images\sample
总文件数: 2500
选中文件数: 150
成功复制: 150
```

---

## 二、FindAndCopy.ps1 - 智能查找并复制文件

### 功能说明
读取源文件夹中的所有文件名，然后在多个指定的搜索路径中查找同名文件，并将找到的文件分别保存到对应的子文件夹中。

### 适用场景
- 需要从不同目录查找对应的文件（如左右视图、RGB和深度图）
- 文件扩展名可能不同（如 `.jpg` 和 `.png`）
- 需要保持原始文件夹结构

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `-SourceFolder` | string | ✅ | 包含参考文件名的源文件夹 |
| `-SearchFolders` | string[] | ✅ | 要搜索的文件夹列表（支持扩展名指定） |
| `-DestinationFolder` | string | ✅ | 目标根文件夹 |
| `-FileFilter` | string | ❌ | 源文件筛选条件（默认：`*.*`） |
| `-PreserveFolderStructure` | switch | ❌ | 保留文件在搜索文件夹内的相对路径结构 |
| `-Overwrite` | switch | ❌ | 是否覆盖已存在文件（默认：启用） |

### 搜索文件夹格式

支持为每个搜索路径单独指定文件扩展名，格式为：`路径|扩展名`

| 格式 | 说明 |
|------|------|
| `"文件夹路径"` | 使用源文件的扩展名 |
| `"文件夹路径\|扩展名"` | 使用指定的扩展名 |
| `"文件夹路径 \| 扩展名"` | 支持空格，会自动去除 |

### 使用示例

#### 基础用法（使用相同扩展名）
```powershell
.\FindAndCopy.ps1 -SourceFolder ".\left" `
                  -SearchFolders @(".\right", ".\disparity") `
                  -DestinationFolder ".\output"
```

#### 指定不同扩展名
```powershell
.\FindAndCopy.ps1 -SourceFolder ".\left" `
                  -SearchFolders @(
                      ".\right",                  # 使用 .jpg（与源文件相同）
                      ".\disparity|png"      # 使用 .png
                  ) `
                  -DestinationFolder ".\output"
```

#### 支持空格格式
```powershell
.\FindAndCopy.ps1 -SourceFolder ".\left" `
                  -SearchFolders @(
                      ".\right",
                      ".\disparity | png"    # 带空格方便阅读
                  ) `
                  -DestinationFolder ".\output"
```

#### 保留文件夹结构
```powershell
.\FindAndCopy.ps1 -SourceFolder ".\left" `
                  -SearchFolders @(".\right", ".\disparity|png") `
                  -DestinationFolder ".\output" `
                  -PreserveFolderStructure
```

#### 使用绝对路径
```powershell
.\FindAndCopy.ps1 -SourceFolder "C:\datasets\left" `
                  -SearchFolders @(
                      "C:\datasets\right",
                      "C:\datasets\disparity|png") `
                  -DestinationFolder "C:\datasets\output"
```

### 输出目录结构

#### 不使用 -PreserveFolderStructure（默认）
```
output\
  ├── right                    # 来自 right 的所有匹配文件
  │   ├── 0000.jpg
  │   ├── 0001.jpg
  │   └── ...
  └── disparity\              # 来自 disparity 的文件
      ├── 0000.png
      ├── 0001.png
      └── ...
```

#### 使用 -PreserveFolderStructure
```
output\
  ├── right\                    # 来自 right 的不同 subfolder 的匹配文件
  │   ├── subfolder1\
  │   │   └── 0000.jpg
  │   └── subfolder2\
  │       └── 0001.jpg
  └── disparity\              # 来自 left\disparity
      ├── subfolder1\
      │   └── 0000.png
      └── subfolder2\
          └── 0001.png
```

### 输出示例
```
当前工作目录: C:\datasets\script
源文件夹: C:\datasets\left
目标根文件夹: C:\datasets\output
保留文件夹结构: False

源文件扩展名（默认）: .jpg

✓ 搜索路径:  C:\datasets\right
  └─ 目标文件夹:  C:\datasets\output\right
  └─ 扩展名: .jpg （默认: .jpg）
✓ 搜索路径:  C:\datasets\disparity
  └─ 目标文件夹:  C:\datasets\output\disparity
  └─ 扩展名: .png （指定: .png）

找到 2500 个参考文件

[1/2500] 查找文件: 0000.jpg
  在 [right] 中查找: 0000.jpg
    ✓ 已复制
  在 [disparity] 中查找: 0000.png
    ✓ 已复制

...

========== 复制完成 ==========
详细统计:
  [right]
    搜索路径:  C:\datasets\right
    目标路径:  C:\datasets\output\right
    查找扩展名: .jpg
    找到文件: 2500
    成功复制: 2500

  [disparity]
    搜索路径:  C:\datasets\disparity
    目标路径:  C:\datasets\output\disparity
    查找扩展名: .png
    找到文件: 2500
    成功复制: 2500

总计:
  源文件总数: 2500
  总匹配次数: 5000
  总复制成功: 5000

详细报告已保存到:  C:\datasets\output\copy_report_YYYYMMDD_HHMMSS.txt
```

---

## 三、常见问题

### Q1: 运行 PowerShell 脚本时提示“无法加载，因为在此系统上禁止运行脚本”
**解决方案**：以管理员身份打开 PowerShell，执行：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Q2: 路径中包含空格怎么办？
**解决方案**：将路径用双引号包裹即可，例如：
```powershell
-SourceFolder "C:\My Images\Left RGB"
```

### Q3: 如何预览将要复制的文件而不实际复制？
**解决方案**：脚本当前版本不支持预览模式，建议先使用小范围测试：
```powershell
.\FindAndCopy.ps1 -SourceFolder ".\test\small_set" -SearchFolders @(...) -DestinationFolder ".\test\output"
```

### Q4: 搜索文件夹中的子目录结构是否会保留？
**解决方案**：使用 `-PreserveFolderStructure` 参数可以保留文件在搜索文件夹内的相对路径结构。

### Q5: 如果搜索文件夹中存在多个同名文件会怎样？
**解决方案**：脚本只会复制第一个找到的文件。如果需要处理多个同名文件，建议调整搜索路径的粒度。

---

## 四、系统要求

- **操作系统**：Windows 7 / 8 / 10 / 11
- **PowerShell 版本**：3.0 或更高版本
- **运行环境**：建议在 PowerShell 控制台中运行，而非 CMD

检查 PowerShell 版本：
```powershell
$PSVersionTable.PSVersion
```

---

## 五、文件清单

脚本运行后会生成以下辅助文件：

| 文件 | 说明 |
|------|------|
| `copy_report_YYYYMMDD_HHMMSS.txt` | `FindAndCopy.ps1` 生成的详细复制报告 |

---
