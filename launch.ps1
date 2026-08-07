# -*- coding: utf-8 -*-
param([string]$Agent, [string]$Keyword)

$tsv = "$env:USERPROFILE\.oc-projects.tsv"
# 私有配置(不入库):Junction 别名由 ssh-projects-nav.config.ps1 提供,不假设任何个人路径
$altUserRoot = $null
$realUserRoot = $env:USERPROFILE
$cfg = "$PSScriptRoot\ssh-projects-nav.config.ps1"
if (Test-Path $cfg) {
    . $cfg
    $altUserRoot = $script:ocAltUserRoot
    $realUserRoot = $script:ocRealUserRoot
}
if (-not $realUserRoot) { $realUserRoot = $env:USERPROFILE }
# key 转义与解码:与 profile 保持一致(空格=_20、下划线=_5f、% =%25,先 % 后 _ 后空格,完全可逆)
function Get-KeyEnc { param([string]$K) ($K -replace '%', '%25') -replace '_', '_5f' -replace ' ', '_20' }
function Get-KeyDec { param([string]$K) ($K -replace '_20', ' ') -replace '_5f', '_' -replace '%25', '%' }
# 原子写盘:临时文件 + 替换
function Write-ProjectFileAtomicRaw {
    param([string]$Path, [string[]]$Content)
    $tmp = "$Path.oc.tmp.$(Get-Random)"
    try {
        $Content | Out-File -FilePath $tmp -Encoding utf8
        if (Test-Path $Path) { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
        Move-Item -Path $tmp -Destination $Path -Force
    } catch {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        throw
    }
}
$lines = @(Get-Content $tsv -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -match '#' } | ForEach-Object {
    $lp = $_ -split '#', 3
    if ($lp.Count -ge 2) {
        $cp = $lp[1]
        if ($altUserRoot -and $cp -like "$altUserRoot*") { $cp = $realUserRoot + $cp.Substring($altUserRoot.Length) }
        "{0}#{1}#{2}" -f (Get-KeyDec $lp[0]), $cp, $lp[2]
    } else { $_ }
})

if (-not $Keyword) {
    if ($lines.Count -eq 0) { Write-Host "列表为空,先运行 refresh" }
    else {
        $grouped = @{ 'cl' = @(); 'cx' = @(); 'oc' = @() }
        $lines | ForEach-Object {
            $p = $_ -split '#', 3
            $name = $p[0]
            $agent = if ($name -like 'cl-*') { 'cl' } elseif ($name -like 'cx-*') { 'cx' } else { 'oc' }
            $grouped[$agent] += ("{0} {1}   <- {2}" -f $agent, $name, $p[1])
        }
        foreach ($ag in @('oc', 'cl', 'cx')) {
            if ($grouped[$ag].Count -eq 0) { continue }
            $label = switch ($ag) { 'oc' { 'opencode' } 'cl' { 'Claude' } 'cx' { 'Codex' } }
            Write-Host ""
            Write-Host "=== $label ==="
            $grouped[$ag] | ForEach-Object { Write-Host $_ }
        }
    }
    Write-Host ""
    Write-Host "复制上面任意一行粘贴运行,即可进入并启动对应agent"
    exit 0
}

$dir = $null

# 输入容错:去首尾空格
$Keyword = $Keyword.Trim()
# 如果粘贴了整行 "oc oc-proj  <-  D:\...",提取第二个 token(跳过 oc/cl/cx 前缀)
$tokens = @($Keyword -split '\s+' | Where-Object { $_ })
$keywordFirst = $tokens[0]
$keywordSecond = if ($tokens.Count -gt 1 -and $tokens[0] -match '^(oc|cl|cx)$') { $tokens[1] } else { $null }
# 全角冒号转半角
$keywordNormal = $keywordFirst.Replace('：', ':')

# 候选列表: 完整key、第一个token、第二个token(去agent前缀)、去掉前缀的key、模糊
$candidates = @($Keyword, $keywordFirst, $keywordSecond, $keywordNormal) | Where-Object { $_ } | Select-Object -Unique

foreach ($cand in $candidates) {
    foreach ($line in $lines) {
        $p = $line -split '#', 3
        if ($p[0] -eq $cand -or $p[1] -eq $cand) { $dir = $p[1]; break }
    }
    if ($dir) { break }
}

# 仍没找到:前缀优先(精确 prefix),子串兜底
if (-not $dir) {
    foreach ($cand in $candidates) {
        $base = ($cand -split '[-:]')[-1]
        if (-not $base) { continue }
        # 第一轮:key 或路径叶子以 base 开头
        foreach ($line in $lines) {
            $p = $line -split '#', 3
            $leaf = [System.IO.Path]::GetFileName($p[1])
            if ($p[0].StartsWith($base) -or $leaf.StartsWith($base)) { $dir = $p[1]; break }
        }
        if ($dir) { break }
    }
}
# 最后兜底:子串
if (-not $dir) {
    foreach ($cand in $candidates) {
        $base = ($cand -split '[-:]')[-1]
        if (-not $base) { continue }
        foreach ($line in $lines) {
            $p = $line -split '#', 3
            if ($p[0].Contains($base) -or $p[1].Contains($base)) { $dir = $p[1]; break }
        }
        if ($dir) { break }
    }
}

if (-not $dir) { Write-Host "没有找到与 '$Keyword' 匹配的项目"; exit 1 }
if (-not (Test-Path $dir)) {
    Write-Host "目录不存在: $dir"
    # 自动从库中移除失效路径(该路径对应行全部删除)
    $dirOff = $dir.TrimEnd('\')
    $alive = @($lines | Where-Object { ($_ -split '#', 3)[1].TrimEnd('\') -ne $dirOff })
    Write-ProjectFileAtomicRaw $tsv ($alive | ForEach-Object { $q = $_ -split '#', 3; "{0}#{1}#{2}" -f (Get-KeyEnc $q[0]), $q[1], $q[2] })
    Write-Host "已从项目库移除失效条目(剩余 $($alive.Count) 条)"
    exit 1
}

Set-Location $dir
Write-Host "已进入: $dir"

# 更新时间戳 + 重新排序:该路径在所有行里对应的时间置为现在,然后按时间倒序重写
$now = [int64]((Get-Date).ToUniversalTime() - [datetime]::new(1970,1,1,0,0,0,[datetimekind]::Utc)).TotalMilliseconds
$dirNorm = $dir.TrimEnd('\')
$newLines = $lines | ForEach-Object {
    $p = $_ -split '#', 3
    if ($p[1].TrimEnd('\') -eq $dirNorm) { "{0}#{1}#{2}" -f $p[0], $p[1], $now } else { $_ }
}

# 去重:按归一化路径(去尾斜杠+小写)保留时间戳最大者,再按 key 去重
$byPath = @{}
foreach ($l in $newLines) {
    $p = $l -split '#', 3
    $norm = $p[1].TrimEnd('\').ToLowerInvariant()
    if (-not $byPath.ContainsKey($norm)) { $byPath[$norm] = $l; continue }
    $lt = [int64]($byPath[$norm] -split '#', 3)[2]
    $ct = [int64]$p[2]
    if ($ct -gt $lt) { $byPath[$norm] = $l }
}
$byKey = @{}
foreach ($l in $byPath.Values) {
    $p = $l -split '#', 3
    if (-not $byKey.ContainsKey($p[0])) { $byKey[$p[0]] = $l; continue }
    $lt = [int64]($byKey[$p[0]] -split '#', 3)[2]
    $ct = [int64]$p[2]
    if ($ct -gt $lt) { $byKey[$p[0]] = $l }
}
$writeLines = @($byKey.Values | Sort-Object { [int64](($_ -split '#', 3)[2]) } -Descending | ForEach-Object {
    $w = $_ -split '#', 3
    "{0}#{1}#{2}" -f (Get-KeyEnc $w[0]), $w[1], $w[2]
})
Write-ProjectFileAtomicRaw $tsv $writeLines

switch ($Agent) {
    'oc' { opencode }
    'cl' { claude }
    'cx' { codex }
    default { }
}
