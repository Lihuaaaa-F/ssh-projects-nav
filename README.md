# ssh-projects-nav

PowerShell 项目导航器:自动发现本机所有 AI 编码项目,让你从 iPad/手机 SSH 远程**列出 → 复制一行 → 粘贴**,即可进入任意项目并启动 opencode / Claude Code / Codex。

## 快速开始

```bash
go            # 列出全部项目(按最近使用倒序)
oc 项目名      # 进入项目并启动 opencode
cl 项目名      # 进入项目并启动 Claude Code
cx 项目名      # 进入项目并启动 Codex
refresh       # 手动全量重扫(go 每次列出也会自动重扫)
```

名称支持完整 key、路径片段、或项目目录名前缀,如 `cl-dual`、`webapp-main`。

```bash
$ go
已刷新: 12 项(自动最多60,手动不淘汰)
=== opencode ===
oc oc-app1-main   <- D:\projects\app1
oc oc-my-project  <- D:\workspace\my-project

# 复制任意一行粘贴回车,即进入该项目并打开对应 AI 工具
oc oc-app1-main   <- D:\projects\app1
```

## 工作原理

```
 ┌─命令层──────────┐  oc/cl/cx/go.cmd
 ├─跳转层───────────┘  launch.ps1  [匹配 → 校验 → 进目录 → 更新时间戳 → 启动 agent]
 ├─库层─────────────┘  .oc-projects.tsv   项目库(时间倒序)
 └─采集层───────────┘  profile 函数自动发现项目
```

- **发现来源**:Claude 会话文件、Codex SQLite + 会话、opencode.db、`scanRoots` 目录按工程标记(`.git`/`.uvprojx`/`package.json`…)扫描
- **上限 60 条**:超出的按时间戳淘汰,手动添加的项目永远保留
- **去重**:按路径和 key 双去重,手动条目优先
- **路径归一化**:登录用户名与用户目录名不同时(Windows Junction),自动把两套路径视为同一目录
- **失败清理**:目录已消失的条目自动从库中移除
- **原子写盘**:库文件临时文件+改名写入,不会写坏

## 隐私 & 配置

你的个人数据**只在你自己机器上,永不提交**:

- `ssh-projects-nav.config.ps1` — 扫描目录、排除路径、路径别名(已 gitignore)
- `.oc-projects.tsv` / `.oc-manual.txt` — 项目库与手动清单(已 gitignore)

克隆后在本机创建配置即可用:

```powershell
# ssh-projects-nav.config.ps1(个人私有,勿提交)
$scanRoots      = @('D:\Projects')            # 要从哪些目录挖掘仓库
$excludePaths   = @($env:USERPROFILE)         # 这些路径永远不收
$ocAltUserRoot  = $null                        # 登录名 != 目录名时填别名根
$ocRealUserRoot = $env:USERPROFILE
```

## 组件

| 路径 | 作用 |
|---|---|
| `.oc-tools\launch.ps1` | 核心:匹配 → 进目录 → 更新时间戳 → 启动 agent |
| `.oc-tools\{oc,cl,cx,go,refresh}.cmd` | 薄封装 |
| `.oc-tools\ssh-projects-nav.config.ps1` | 你的私有配置(不入库) |
| `Microsoft.PowerShell_profile.ps1` | 扫描器 / 去重 / 更新函数 |

## 维护

| 做法 | 命令 |
|---|---|
| 全量重扫(跳过缓存) | `go-refresh -Force` |
| 清理重复项 | `go-dedup -Fix` |
| 手动锁定项目(不淘汰) | `go-add 名称 路径` |
| 取消锁定 | `go-rm 名称` |
| 追加扫描目录 | `go-roots D:\xxx` |

## 更新日志

历次变更见 [CHANGELOG.md](CHANGELOG.md)。
