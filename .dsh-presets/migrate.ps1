$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path $env:USERPROFILE '.dsh\.agent-presets'
$dstRoot = 'F:\Projects\Web\csharp\.dsh-presets'

$bundles = @(
  @{ id = 'csharp';       pkg = '@local/dsh-csharp-preset';       order = 10 },
  @{ id = 'csharp-unity'; pkg = '@local/dsh-csharp-unity-preset'; order = 11 },
  @{ id = 'vue3-js';      pkg = '@local/dsh-vue3-js-preset';      order = 12 },
  @{ id = 'vue3-ts';      pkg = '@local/dsh-vue3-ts-preset';      order = 13 }
)

$utf8 = [System.Text.UTF8Encoding]::new($false)

foreach ($b in $bundles) {
  $id = $b.id
  $pkg = $b.pkg
  $src = Join-Path $srcRoot $id
  $dst = Join-Path $dstRoot $id

  # --- parse preset.yml for name / description ---
  $presetRaw = [System.IO.File]::ReadAllText((Join-Path $src 'preset.yml'))
  $name = ($presetRaw -split "`n" | Where-Object { $_ -match '^name:' } | Select-Object -First 1) -replace '^name:\s*', ''
  $desc = ($presetRaw -split "`n" | Where-Object { $_ -match '^description:' } | Select-Object -First 1) -replace '^description:\s*', ''

  # --- read composition, strip comment lines ---
  $compRaw = [System.IO.File]::ReadAllText((Join-Path $src 'agent.cordis.yml'))
  $compLines = $compRaw -split "`n"
  $kept = New-Object System.Collections.Generic.List[string]
  foreach ($line in $compLines) {
    $t = $line.TrimEnd("`r")
    if ($t -match '^\s*#') { continue }
    $kept.Add($t)
  }
  $pluginsRaw = ($kept -join "`n").Trim()

  # --- replace the customSkillDirs block (baseUrl -> package resolution) ---
  $oldDir = '    customSkillDirs:' + "`n" + '      - !!js "process.getBuiltinModule(''node:url'').fileURLToPath(new URL(''skills/'', baseUrl))"'
  $newDir = '    customSkillDirs:' + "`n" + "      - !!js process.getBuiltinModule('node:path').join(process.getBuiltinModule('node:path').dirname(process.getBuiltinModule('node:module').createRequire(baseUrl).resolve('$pkg/package.json')), 'skills')"
  if (-not $pluginsRaw.Contains('customSkillDirs:')) {
    throw "customSkillDirs block not found in $id"
  }
  $pluginsRaw = $pluginsRaw.Replace($oldDir, $newDir)

  # --- indent plugins 10 spaces ---
  $indented = (($pluginsRaw -split "`n") | ForEach-Object {
    if ($_.Trim() -eq '') { '' } else { '          ' + $_ }
  }) -join "`n"

  # --- assemble cordis.patch.yml ---
  $header = @(
    '- insert:'
    '    - id: preset-' + $id
    "      name: '@deepseek-ai/dsh-agent-preset'"
    '      config:'
    "        id: $id"
    "        name: `"$name`""
    "        description: `"$desc`""
    "        order: $($b.order)"
    '        plugins:'
  ) -join "`n"

  $patch = $header + "`n" + $indented + "`n"

  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dst 'cordis.patch.yml'), $patch, $utf8)

  # --- package.json ---
  $pkgJson = @"
{
  "name": "$pkg",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "files": ["cordis.patch.yml", "skills"],
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
"@
  [System.IO.File]::WriteAllText((Join-Path $dst 'package.json'), $pkgJson, $utf8)

  # --- copy skills ---
  if (Test-Path (Join-Path $src 'skills')) {
    Copy-Item -Path (Join-Path $src 'skills') -Destination $dst -Recurse -Force
  }

  Write-Output "generated $id -> $dst"
}
