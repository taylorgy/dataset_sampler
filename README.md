# 数据集采样工具集

本项目是一套 PowerShell 脚本工具集，用以快速从大规模构化数据集中抽取子集。

## ️ 数据集文件夹采样

针对典型的“多模态数据集”，支持“快速自动化处理”和“精细化人工筛选”两种模式。

### 数据集布局

在典型的多模态数据集中，数据通常按照以下方式组织：

- **按文件类型分目录**  
    不同类型的文件（如RGB图像、深度图、雷达点云等）存放在不同的子目录中
- **同名文件关联**  
    同一场景或同一时间点的不同模态数据使用相同的文件名（仅扩展名不同）
- **层级目录结构**  
    可能包含多个层级的子目录来组织数据

例如：

```
dataset_root/
├── left/rgb/          # 左摄像头 RGB 图像
│   ├── 0001.jpg
│   ├── 0002.jpg
│   └── ...
├── right/rgb/         # 右摄像头 RGB 图像
│   ├── 0001.jpg
│   ├── 0002.jpg
│   └── ...
├── disparity/         # 视差图
│   ├── 0001.pfm
│   ├── 0002.pfm
│   └── ...
└── lidar/             # 激光雷达数据
    ├── 0001.bin
    ├── 0002.bin
    └── ...
```

在这种布局中，同名文件（如`0001.jpg`、`0001.pfm`、`0001.bin`）表示同一组的不同模态数据。

### 模式一：一键全自动采样（推荐）

`New-DatasetSample.ps1`

一键完成从路径发现、文件抽样到多模态数据补全的全过程。

```pwsh
# 从 dataset_root 中随机抽取 200 组样本到 subset 目录
.\New-DatasetSample.ps1 -RawsetRoot "dataset_root" -SubsetRoot "subset" -FileCount 200 -Random
```

 参数 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `-RawsetRoot` | ✓ | | 源数据集根目录 |
| `-SubsetRoot` | ✓ | | 子集输出根目录 |
| `-FileCount` | | 150 | 抽样数量 |
| `-Random` | | 关闭 | 启用随机抽样；不指定时使用均匀等距抽样 |

### 模式二：分步采样（加入人工二次筛选）

先对指定类型抽样，人工二次筛选后，再补全其他类型的数据。

**1. 初步抽样**

`Select-DatasetSample.ps1` 

在指定目录中抽样（均匀或随机），按照原有的相对路径结构复制到指定子集目录 `subset`。

```pwsh
# 从指定子目录中均匀抽取 150 个文件到子集目录 
.\Select-DatasetSample.ps1 -RawsetRoot "dataset_root" -SourcePath "left\rgb" -SubsetRoot "subset" -FileCount 150
```

 参数 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `-RawsetRoot` | ✓ | | 源数据集根目录 |
| `-SourcePath` | | `""` | 采样子路径，如 `left\rgb`；省略表示从根目录取样 |
| `-SubsetRoot` | ✓ | | 子集输出根目录 |
| `-FileCount` | | 150 | 抽样数量 |
| `-Filter` | | `*.*` | 筛选文件类型（后缀） |
| `-Random` | | 关闭 | 启用随机抽样；不指定时使用均匀等距抽样 |
    
**2. 人工筛选**

用户可以打开 `subset` 目录，手动剔除不符合要求的样本（如模糊、遮挡图片），也可以补充更多图片。

**3. 结构补全**

`Complete-DatasetSample.ps1`

扫描子集目录中已有文件的文件名，然后在源数据集中寻找所有同名文件（所有子文件夹、所有拓展名），并将它们按原始目录结构复制到子集目录中。

```pwsh
# 根据你最终保留的文件名，从源数据集中补全其他目录（如 disparity, radar 等）的对应文件
.\Complete-DatasetSample.ps1 -RawsetRoot "dataset_root" -SubsetRoot "subset"
```

 参数 | 必填 | 说明 |
|------|------|------|
| `-RawsetRoot` | ✓ | 源数据集根目录 |
| `-SubsetRoot` | ✓ | 子集输出根目录 |

## 数据集压缩包采样

对于有些数据集，压缩包体积就非常大，先解压再采样对空间要求很大。因此可以先导出压缩包文件列表，了解数据集内容和结构，再决定后续处理方案。

### 导出文件列表

`Export-ArchiveFileList.ps1`

扫描压缩包内部结构，生成详细的文件列表清单。  
压缩包格式：`zip` 和 `tar`（`tar.gz`、`tar.bz2`等）  
输入：压缩包文件路径，或含有压缩包的文件夹路径  
输出：可指定生成三种格式的文件列表（默认生成 txt 和 html）  
- `_filelist.txt`：纯文本路径列表，便于脚本阅读
    - 若该文件存在，脚本会复用以生成其他格式，避免重复扫描
- `_filelist.html`：可折叠交互式网页，便于用户阅读
- `_filetree.txt`：字符画风格的树状结构，介于二者之间

```pwsh
# 扫描单个压缩包，生成默认的 txt 和 html 文件
Export-ArchiveFileList -Path "D:\data\dataset.tar.gz"

# 递归扫描文件夹下所有压缩包，仅生成 txt 格式
Export-ArchiveFileList -Path "D:\archives" -Recurse -Txt

# 指定输出目录，仅生成 html 文件
Export-ArchiveFileList -Path "D:\data.zip" -OutputDir "D:\reports" -Html

# 扫描当前目录（非递归），生成所有三种格式的文件
Export-ArchiveFileShift -Tree
```

| 参数 | 默认 | 说明 |
| :--- | :--- | :--- |
| `-Path` | 当前工作目录 | 目标压缩文件路径或包含压缩文件的文件夹路径 |
| `-Recurse` | 关闭 | 当 `-Path` 为文件夹时，递归扫描子文件夹中的压缩文件 |
| `-OutputDir` | 压缩包所在目录 | 文件列表的输出目录 |
| `-Txt`  | 未指定 `-Html` 时开启 | 仅生成 `_filelist.txt` |
| `-Html` | 未指定 `-Txt ` 时开启 | 仅生成 `_filelist.html` |
| `-Tree` | 关闭 | 生成 `_filetree.txt` |

注：程序默认生成 txt 和 html 两种格式，只想生成其中一种时才需要指定 `-Txt` 或 `-Html`。

## 常见问题与提示

### 路径格式

建议使用 Windows 路径分隔符 反斜杠 `\`。  
也支持正斜杠 `/`。

### 执行策略限制
    
如果在 PowerShell 中运行脚本时提示"无法加载，因为在此系统上禁止运行脚本"，请以管理员身份运行 PowerShell 并执行以下命令开启权限：

```pwsh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```
### 路径结构保留

所有脚本在复制文件时，都会自动保留文件在源数据集中的相对路径，确保子集目录结构与源目录完全一致。

### 文件冲突处理

在执行补全操作时，如果目标目录中已经存在同名文件，脚本会自动跳过，不会重复复制或覆盖。

### 压缩文件支持

脚本目前仅支持 `zip` 和 `tar`（`tar.gz`、`tar.bz2`等）格式，因为PowerShell 原生支持 `tar` 和 `System.IO.Compression.ZipFile` 命令。其他格式需要额外安装依赖，因此暂时不支持。

---

## 版本历史

### 数据集压缩包采样
- Export-ArchiveFileList.ps1：导出压缩包文件列表

### 代码重构
- Copy-FilesEvenly / FindAndCopy 替换为 Select-DatasetSample / Complete-DatasetSample
- 新增 New-DatasetSample，自动完成采样
- 重构参数体系：RawsetRoot / SourcePath / SubsetRoot
- 新增随机采样模式
- 支持平铺数据集
- 统一输出格式，异常提示与统计

### 初始版本
- Copy-FilesEvenly：基于文件总数的均匀抽样
- FindAndCopy：基于文件名的多目录关联复制
