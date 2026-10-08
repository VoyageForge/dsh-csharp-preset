<#
.SYNOPSIS
    把 .dsh-presets 下的四个人格分别发布成独立的 GitHub 仓库（一个仓库一个人格）。

.DESCRIPTION
    流程（每个预设独立执行，互不影响）：
      1. 在临时目录用 `git clone --shared` 从本仓库拉一份对象库共享的副本（不碰你的工作区）；
      2. 在副本里用 `git rm -r --cached` 摘掉其它预设与脚本，只留本预设 + .gitattributes；
      3. 生成该预设专属的 README.md；
      4. 提交到 main 分支；
      5. 用 `gh repo create VoyageForge/<仓库名> --source <副本> --push` 建远程仓库并推送。

    前置条件：`gh auth login` 已完成，且当前账号对 VoyageForge 组织有建仓权限。

.PARAMETER RepoOwner
    目标 GitHub 组织或用户，默认 VoyageForge。

.PARAMETER Visibility
    public 或 private，默认 public。

.PARAMETER Only
    只发布指定预设（可多个，取值 csharp / csharp-unity / vue3-js / vue3-ts）。留空表示全部。

.PARAMETER DryRun
    干跑：完成拆分与提交，打印将要执行的命令，但不创建远程仓库、不推送。

.EXAMPLE
    pwsh -File publish-presets.ps1 -DryRun
    先干跑验证拆分与 README 生成是否正确。

.EXAMPLE
    pwsh -File publish-presets.ps1
    正式建仓并推送四个人格。
#>
[CmdletBinding()]
param(
    [string]$RepoOwner = 'VoyageForge',
    [ValidateSet('public', 'private')]
    [string]$Visibility = 'public',
    [ValidateSet('csharp', 'csharp-unity', 'vue3-js', 'vue3-ts')]
    [string[]]$Only,
    [switch]$DryRun,
    # 主仓库根（含 .dsh-presets 的目录）。默认取脚本自身所在目录，便于把脚本放在仓库根直接运行。
    [string]$RepoRoot,
    # 推送用的 SSH 地址前缀。默认 git@github.com:<RepoOwner>；本机 HTTPS(443) 到 GitHub 不通。
    [string]$GitRemoteBase
)

$ErrorActionPreference = 'Stop'

# 本脚本默认放在仓库根（.dsh-presets 的上级）；-RepoRoot 可显式覆盖
$repoRoot = if ($RepoRoot) { (Resolve-Path -LiteralPath $RepoRoot).Path } else { $PSScriptRoot }

# 每个预设的发布信息：仓库名与 package.json 的包名同形（去掉 @local/ 前缀）
$presets = @(
    [pscustomobject]@{
        Dir  = '.dsh-presets/csharp'
        Repo = 'dsh-csharp-preset'
        Pkg  = 'dsh-csharp-preset'
    }
    [pscustomobject]@{
        Dir  = '.dsh-presets/csharp-unity'
        Repo = 'dsh-csharp-unity-preset'
        Pkg  = 'dsh-csharp-unity-preset'
    }
    [pscustomobject]@{
        Dir  = '.dsh-presets/vue3-js'
        Repo = 'dsh-vue3-js-preset'
        Pkg  = 'dsh-vue3-js-preset'
    }
    [pscustomobject]@{
        Dir  = '.dsh-presets/vue3-ts'
        Repo = 'dsh-vue3-ts-preset'
        Pkg  = 'dsh-vue3-ts-preset'
    }
)

if ($Only) {
    $presets = $presets | Where-Object { $Only -contains ($_.Dir -split '/')[-1] }
    if (-not $presets) { throw "Only 参数没有匹配到任何预设" }
}

# ---------------------------------------------------------------- 前置检查 ---
if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    throw "仓库根没有 .git：$repoRoot"
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "找不到 gh（GitHub CLI），请先安装"
}
# 干跑不接触远端，因此不强制登录，方便先验证拆分与 README 生成
if (-not $DryRun) {
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "gh 未登录。请先运行：gh auth login"
    }
}

# 记录当前分支，结束时恢复（本脚本本身不改动当前分支，只做保险）
$originalBranch = (git -C $repoRoot rev-parse --abbrev-ref HEAD).Trim()

<#
    从 cordis.patch.yml 里读出人格显示名与描述，供 README 使用。
    用 yaml 解析不可行（!!js 扩展类型），因此按行做简单提取。
#>
function Get-PresetMeta {
    param([string]$PatchPath)
    $lines = Get-Content -LiteralPath $PatchPath
    $name = ($lines | Where-Object { $_ -match '^\s+name:\s*"' } | Select-Object -First 1)
    $desc = ($lines | Where-Object { $_ -match '^\s+description:\s*"' } | Select-Object -First 1)
    [pscustomobject]@{
        Name = ($name -replace '^\s+name:\s*"', '' -replace '"\s*$', '')
        Desc = ($desc -replace '^\s+description:\s*"', '' -replace '"\s*$', '')
    }
}

<#
    列出该预设 skills/ 下的技能目录名，README 里逐个列出便于检索。
#>
function Get-SkillNames {
    param([string]$SkillsDir)
    if (-not (Test-Path $SkillsDir)) { return @() }
    Get-ChildItem $SkillsDir -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
}

<#
    生成一个预设仓库的 README.md 正文。
    内容保持事实性：目录结构、如何挂载、CodeGraph 行为规则、技能清单、重新生成方式。
#>
function New-PresetReadme {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string[]]$Skills,
        [string]$RepoName
    )
    $skillLines = if ($Skills.Count) {
        ($Skills | ForEach-Object { "- ``$_``" }) -join "`n"
    } else {
        '- （无）'
    }

    @"
# $DisplayName

$Description

这是 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）的一个 **agent 预设（persona preset）** bundle，供 ``dsh-agent-preset`` 装载：配置一个人格身份、一套工具组合，以及一组按需加载的 Skill。

## 内容

| 文件 | 说明 |
|---|---|
| ``cordis.patch.yml`` | 预设定义：persona 文案 + 工具装配 + 技能目录 |
| ``package.json`` | bundle 清单（``dsh.bundle.patch`` 指向上面的 patch） |
| ``skills/`` | 该人格自带的 Skill，每个子目录一份 ``SKILL.md`` |

## 内置的 Skill

$skillLines

## persona 里内置的 CodeGraph 行为规则

``cordis.patch.yml`` 的 ``persona.prefix`` 中写有代码图谱（CodeGraph MCP）的使用规则，让 agent 不用被提示就自己去用：

- 结构性问题（某功能怎么实现、某符号在哪、改动会影响什么）优先调用 ``codegraph_explore``，而不是先跑一轮 grep/read；
- 调用前自查当前工程有没有 ``.codegraph/`` 索引，**按需**提议建立（一个工程只提一次，不反复念）；
- 建立索引、安装 CLI 都必须先取得用户同意才执行；
- ``codegraph`` 命令报错时先判断 CLI 是否缺失，缺失则询问是否安装（含 Windows / macOS / Linux 三平台命令）。

未安装 CodeGraph 或未建索引时，以上规则不影响其它工具的正常使用。

## 目录结构

``````
.
├── cordis.patch.yml
├── package.json
└── skills/
``````

## 如何挂载

本仓库根目录即预设包本身（根下有 ``package.json`` 与 ``cordis.patch.yml``）。在 DSH profile 的 ``package.json`` 里把它作为依赖加入，并登记进 ``dsh.profile.bundles``：

``````json
{
  "dependencies": {
    "$RepoName": "link:path/to/$RepoName"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "$RepoName"
      ]
    }
  }
}
``````

``link:`` 指向 clone 下来的仓库根目录即可；``bundles`` 里写根 ``package.json`` 中的 ``name``。

## 重新生成 ``cordis.patch.yml``

它是由原始预设（``~/.dsh/.agent-presets``）经脚本转换而来：把 ``preset.yml`` 的 name/description、``agent.cordis.yml`` 的 plugins 组装成 bundle 形态，并把 ``customSkillDirs`` 改成基于包名解析的写法。转换脚本见同目录的 ``migrate.ps1``。

## License

内部工程，未声明开源许可证。
"@
}

# ------------------------------------------------------------------ 主流程 ---
$results = @()

foreach ($p in $presets) {
    $srcDir = Join-Path $repoRoot $p.Dir
    if (-not (Test-Path $srcDir)) {
        Write-Warning "跳过 $($p.Repo)：找不到 $srcDir"
        continue
    }

    Write-Host "`n=== $($p.Repo) ===" -ForegroundColor Cyan

    # 1. 临时副本（--shared 复用对象库，秒级完成）
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("preset-publish-" + $p.Repo + "-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    git clone --quiet --shared $repoRoot $tmp
    # clone 后 HEAD 已在 main 上，用 -B 保证存在且指向干净起点（-b 会因分支已存在而报错）
    git -C $tmp checkout --quiet -B main

    # 2. 只保留本预设，并把它提升到仓库根（独立仓库里预设本身就是根，clone 后可直接被 link: 引用）
    $keep = $p.Dir + '/'

    # 2a. 物理删除其它预设与顶层脚本的工作区文件（索引留到最后用 git add -A 统一结算）
    foreach ($d in @('.dsh-presets/csharp', '.dsh-presets/csharp-unity', '.dsh-presets/vue3-js', '.dsh-presets/vue3-ts')) {
        $abs = Join-Path $tmp $d
        if ($d -ne $p.Dir -and (Test-Path $abs)) { Remove-Item -LiteralPath $abs -Recurse -Force }
    }
    foreach ($f in @('migrate.ps1', 'publish-presets.ps1')) {
        $abs = Join-Path $tmp ".dsh-presets/$f"
        if (Test-Path $abs) { Remove-Item -LiteralPath $abs -Force }
    }

    # 2b. 确保本预设文件在磁盘上（前面若被其它清理动作波及则从索引恢复）
    git -C $tmp checkout --quiet -- $keep

    # 2c. 上提到根：git mv 不会自动创建目标目录，因此先建目录再移动文件，
    #     最后交给 git add -A 识别为 rename（比依赖 git mv 更稳）。
    $mine = git -C $tmp ls-files | Where-Object { $_.StartsWith($keep) }
    foreach ($f in $mine) {
        $rel = $f.Substring($keep.Length)
        $from = Join-Path $tmp $f
        $to = Join-Path $tmp $rel
        $toDir = Split-Path -Parent $to
        if (-not (Test-Path $toDir)) { New-Item -ItemType Directory -Force -Path $toDir | Out-Null }
        Move-Item -LiteralPath $from -Destination $to -Force
    }

    # 2d. 上提后 .dsh-presets 只剩空目录，删掉它（只删这一个，避免误伤别处）
    $leftover = Join-Path $tmp '.dsh-presets'
    if (Test-Path $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force -ErrorAction SilentlyContinue }

    # 3. 生成 README
    $meta = Get-PresetMeta -PatchPath (Join-Path $srcDir 'cordis.patch.yml')
    $skills = Get-SkillNames -SkillsDir (Join-Path $srcDir 'skills')
    $readme = New-PresetReadme -DisplayName $meta.Name -Description $meta.Desc -Skills $skills -RepoName $p.Repo
    Set-Content -LiteralPath (Join-Path $tmp 'README.md') -Value $readme -Encoding utf8 -NoNewline

    # 4. 提交（git add -A 结算上提产生的重命名与其它预设的删除）
    git -C $tmp add -A
    $filesInRepo = git -C $tmp ls-files
    git -C $tmp -c core.autocrlf=false commit --quiet -m @"
feat: $($meta.Name) —— DSH agent 预设

$($meta.Desc)

由主仓库拆分而来，仅包含该人格的 cordis.patch.yml、package.json 与 skills/。
"@
    $head = (git -C $tmp rev-parse --short HEAD).Trim()
    Write-Host "  提交 $head  文件 $($filesInRepo.Count) 个  技能 $($skills.Count) 份" -ForegroundColor Green

    # 5. 建远程仓库并推送
    #    clone 出来的副本自带 origin（指向主仓库），必须先删掉，否则 --remote origin 会报
    #    "Unable to add remote origin"，导致仓库建好了却没有推送。
    git -C $tmp remote remove origin 2>$null | Out-Null

    # 远端地址固定用 SSH：本机 HTTPS(443) 到 github.com 不通（Connection reset），
    # SSH(22) 正常，与 gh 配置的 git_protocol=ssh 也一致。
    if (-not $GitRemoteBase) {
        $GitRemoteBase = "git@github.com:$RepoOwner"
    }
    $full = "$RepoOwner/$($p.Repo)"
    $remoteUrl = "$GitRemoteBase/$($p.Repo).git"

    if ($DryRun) {
        Write-Host "  [干跑] 远端将使用: $remoteUrl" -ForegroundColor Yellow
        Write-Host "  [干跑] 将执行: git remote add origin <ssh-url> ; git push -u origin main" -ForegroundColor Yellow
        Write-Host "  [干跑] 仓库不存在时还会执行: gh repo create $full --$Visibility" -ForegroundColor Yellow
        $url = "(干跑，未推送)"
    } else {
        # 幂等：仓库若已存在（例如上次建仓成功但推送失败），跳过建仓直接推
        gh api "repos/$full" --silent 2>$null
        $repoExists = ($LASTEXITCODE -eq 0)

        if ($repoExists) {
            Write-Host "  仓库已存在，跳过建仓，直接推送" -ForegroundColor Yellow
        } else {
            # 不带 --source/--push：只负责建仓，推送统一走下面的 SSH 远端
            gh repo create $full --$Visibility --description $meta.Desc
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  建仓失败：$full"
                $results += [pscustomobject]@{ 预设 = $p.Repo; 状态 = '建仓失败'; 地址 = ''; 提交 = $head }
                continue
            }
            Write-Host "  已建仓: https://github.com/$full" -ForegroundColor Green
        }

        git -C $tmp remote add origin $remoteUrl
        # 这四个仓库是「从主仓库重新生成」的产物：每次发布都会重建一份独立历史，
        # 与远端没有共同祖先，普通 push 会被拒（non-fast-forward）。强推即可。
        git -C $tmp push --quiet --force -u origin main
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  推送失败：$full"
            $results += [pscustomobject]@{ 预设 = $p.Repo; 状态 = '推送失败'; 地址 = "https://github.com/$full"; 提交 = $head }
            continue
        }

        $url = "https://github.com/$full"
        Write-Host "  已推送: $url" -ForegroundColor Green
    }

    $results += [pscustomobject]@{ 预设 = $p.Repo; 状态 = $(if ($DryRun) { '干跑通过' } else { '已发布' }); 地址 = $url; 提交 = $head }

    # 6. 清理临时副本
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 保险：确保仍在原分支
$nowBranch = (git -C $repoRoot rev-parse --abbrev-ref HEAD).Trim()
if ($nowBranch -ne $originalBranch) {
    Write-Warning "当前分支为 $nowBranch，与开始时的 $originalBranch 不同，请检查"
}

Write-Host "`n=== 结果 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
