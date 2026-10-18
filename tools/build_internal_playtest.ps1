# Internal Windows/Android playtest builds. Godot 4.7.2, local machine.
[CmdletBinding()]
param(
    [ValidateSet('Windows', 'Android', 'Both')]
    [string] $Platform = 'Windows',
    [string] $DestinationRoot = 'D:\tmp',
    [string] $GodotEditor = 'D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string] $ExpectedCommit = '',
    [switch] $ValidateOnly,
    [switch] $SkipSmoke
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = Split-Path -Parent $PSScriptRoot
if (!(Test-Path -LiteralPath $GodotEditor)) { throw "Godot editor not found: $GodotEditor" }
if (!(Test-Path -LiteralPath (Join-Path $project 'export_presets.cfg'))) { throw 'Missing export_presets.cfg' }
if (!(Test-Path -LiteralPath $DestinationRoot)) { New-Item -Path $DestinationRoot -ItemType Directory -Force | Out-Null }

# 最终包绑定已合并SHA；开发预检仍可省略此参数，清单如实记录工作树差异。
$commit = (& git -C $project rev-parse HEAD).Trim()
$sourceChanges = @(& git -C $project diff --name-only HEAD)
$untrackedResources = @(& git -C $project ls-files --others --exclude-standard -- core data systems ui scenes addons project.godot export_presets.cfg)
if ($ExpectedCommit) {
    if ($commit -ne $ExpectedCommit) { throw "Expected source $ExpectedCommit, actual $commit" }
    if ($sourceChanges.Count -gt 0 -or $untrackedResources.Count -gt 0) {
        throw 'Exact-commit export requires committed source/configuration and no untracked production resources'
    }
}

# Godot writes non-fatal resource-cleanup notices to stderr even with export exit 0.
# Capture stderr to a diagnostic file and decide success by the actual process exit code.
function Invoke-BuildProcess([string] $label, [string] $program, [string[]] $arguments, [string] $transcript) {
    # Windows Godot is a GUI-subsystem executable: use -Wait, not bare &,
    # because PowerShell can otherwise return before the export file is finalized.
    $commandLine = ($arguments | ForEach-Object {
        $item = $_.Replace('"', '\"')
        if ($item -match '\s') { '"' + $item + '"' } else { $item }
    }) -join ' '
    $outPath = $transcript + '.stdout'
    $errPath = $transcript + '.stderr'
    $proc = Start-Process -FilePath $program -ArgumentList $commandLine -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath -ErrorAction Stop
    if ($proc.ExitCode -ne 0) {
        Write-Host ('FAILED ' + $label + ', exit=' + $proc.ExitCode)
        Get-Content -LiteralPath $errPath -Tail 20 -ErrorAction SilentlyContinue
        throw ('Process failed: ' + $label + ', exit=' + $proc.ExitCode)
    }
    Write-Host ('PASS ' + $label)
}
function Get-ArtifactRecord([string] $path) {
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.Length -lt 1024) { throw ('Output unexpectedly small: ' + $path) }
    return [ordered]@{
        filename = $item.Name
        bytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    }
}

# 导出成功只说明 Godot 能生成文件；正式内容不齐时必须在创建包目录前终止。
$preflightDirectory = Join-Path $DestinationRoot ('INT-15_Preflight_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -Path $preflightDirectory -ItemType Directory -ErrorAction Stop | Out-Null
$preflightLog = Join-Path $preflightDirectory 'production_catalog.log'
Invoke-BuildProcess 'Godot project import for production preflight' $GodotEditor @(
    '--headless', '--editor', '--path', $project, '--import',
    '--log-file', (Join-Path $preflightDirectory 'godot_import.log')
) (Join-Path $preflightDirectory 'godot_import_cli.log')
Invoke-BuildProcess 'production catalog preflight' $GodotEditor @(
    '--headless', '--path', $project, '--quit-after', '2',
    '--script', 'res://tests/integration/int_15_production_catalog_preflight.gd',
    '--log-file', $preflightLog
) (Join-Path $preflightDirectory 'production_catalog_cli.log')
if (!(Select-String -LiteralPath (Join-Path $preflightDirectory 'production_catalog_cli.log.stdout') -SimpleMatch 'PASS INT-15 production catalog' -Quiet)) {
    throw 'Production catalog preflight exited successfully without its PASS record'
}

# 等待根流程合入时可独立验资源；此模式不会把旧流程导出成最终试玩包。
Invoke-BuildProcess 'production delivery resources' $GodotEditor @(
    '--headless', '--path', $project,
    '--script', 'res://tests/data_export/r26_e_importer_audit.gd'
) (Join-Path $preflightDirectory 'delivery_resources.log')
if (!(Select-String -LiteralPath (Join-Path $preflightDirectory 'delivery_resources.log.stdout') -SimpleMatch 'INT-17E RESOURCE SMOKE PASS' -Quiet)) {
    throw 'Production delivery resources lack their PASS record'
}
if ($ValidateOnly) {
    Write-Host ('VALIDATION_OK ' + $preflightDirectory)
    Write-Host ('SOURCE_COMMIT ' + $commit)
    return
}

$buildDir = Join-Path $DestinationRoot ('GameJam_InternalPlaytest_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -Path $buildDir -ItemType Directory -ErrorAction Stop | Out-Null
$report = [ordered]@{
    kind = 'internal-playtest'
    build_time = (Get-Date).ToString('o')
    git_commit = $commit
    source_changes = $sourceChanges
    untracked_production_resources = $untrackedResources
    engine = 'Godot 4.7.2'
    production_catalog_preflight = 'passed'
    artifacts = @{}
}

if ($Platform -in @('Windows', 'Both')) {
    $exe = Join-Path $buildDir 'GameJam_Playtest.exe'
    $pck = Join-Path $buildDir 'GameJam_Playtest.pck'
    $exportLog = Join-Path $buildDir 'windows_export.log'
    Write-Host '[Windows] Export release...'
    Invoke-BuildProcess 'Windows export' $GodotEditor @(
        '--headless', '--path', $project, '--export-release', 'Windows Desktop',
        $exe, '--log-file', $exportLog
    ) (Join-Path $buildDir 'windows_export_cli.log')
    if (!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath $pck)) { throw 'Missing EXE/PCK after export' }

    # 从构建目录挂载实际PCK；脚本在包外，证明通过不依赖被排除的tests资源。
    $resourceSmoke = Join-Path $buildDir 'production_resource_smoke.gd'
    Copy-Item -LiteralPath (Join-Path $project 'tests/data_export/r26_e_importer_audit.gd') -Destination $resourceSmoke
    $previousResourceAppData = $env:APPDATA
    try {
        $env:APPDATA = Join-Path $buildDir 'resource_smoke_userdata'
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        Push-Location $buildDir
        try {
            Invoke-BuildProcess 'exported PCK resources' $GodotEditor @(
                '--headless', '--path', $buildDir, '--main-pack', $pck,
                '--script', $resourceSmoke, '--', '--verify-pack'
            ) (Join-Path $buildDir 'packed_resources.log')
        } finally { Pop-Location }
    } finally { $env:APPDATA = $previousResourceAppData }
    if (!(Select-String -LiteralPath (Join-Path $buildDir 'packed_resources.log.stdout') -SimpleMatch 'INT-18E PACK CONTENTS PASS' -Quiet)) {
        throw 'Exported PCK lacks its successful resource/content verification record'
    }

    # 旧审计覆盖正式 source_tables；PB-10 另核对新增的五份 Plan B 原始 CSV。
    $planBCsvSmoke = Join-Path $buildDir 'planb_packed_csv_smoke.gd'
    Copy-Item -LiteralPath (Join-Path $project 'tests/plan_b/pb10_packed_data_smoke.gd') -Destination $planBCsvSmoke
    Invoke-BuildProcess 'packed Plan B CSV resources' $GodotEditor @(
        '--headless', '--path', $buildDir, '--main-pack', $pck,
        '--script', $planBCsvSmoke
    ) (Join-Path $buildDir 'planb_packed_csv_smoke.log')
    if (!(Select-String -LiteralPath (Join-Path $buildDir 'planb_packed_csv_smoke.log.stdout') -SimpleMatch 'PASS PB-10 packed Plan B CSV: 5 original files opened' -Quiet)) {
        throw 'Exported PCK lacks the five readable Plan B CSV files'
    }

    $smokeStatus = 'skipped'
    if (!$SkipSmoke) {
        $previousAppData = $env:APPDATA
        $smokeData = Join-Path $buildDir 'smoke_userdata'
        New-Item -Path $smokeData -ItemType Directory -Force | Out-Null
        try {
            $env:APPDATA = $smokeData
            Push-Location $buildDir
            try {
                Write-Host '[Windows] Smoke-test exported game...'
                $smokeLog = Join-Path $buildDir 'windows_smoke.log'
                Invoke-BuildProcess 'Windows smoke' $exe @(
                    '--headless', '--quit-after', '300', '--log-file', $smokeLog
                ) (Join-Path $buildDir 'windows_smoke_cli.log')
            } finally { Pop-Location }
        } finally { $env:APPDATA = $previousAppData }
        if (!(Test-Path -LiteralPath $smokeLog)) { throw 'Missing smoke log' }
        if (Select-String -LiteralPath $smokeLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet) {
            throw 'Windows smoke log contains runtime errors'
        }
        $smokeStatus = 'passed'
    }

    $stage = Join-Path $buildDir 'Windows_Release'
    New-Item -Path $stage -ItemType Directory -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $exe, $pck -Destination $stage -ErrorAction Stop
    $engineLicense = Join-Path (Split-Path -Parent $GodotEditor) 'LICENSE.txt'
    if (Test-Path -LiteralPath $engineLicense) {
        Copy-Item -LiteralPath $engineLicense -Destination (Join-Path $stage 'Godot_ENGINE_LICENSE.txt') -ErrorAction Stop
    }
    $instructions = @(
        '2026 TapTap GameJam - Internal Playtest'
        ('Source commit: ' + $commit)
        'Windows 10/11 x64: Unzip ALL files then run GameJam_Playtest.exe.'
        'Keep GameJam_Playtest.pck in the SAME folder as GameJam_Playtest.exe.'
        'Default display is a centered 1280x720 window using a 1920x1080 logical canvas; toggle fullscreen in Settings.'
        'In Plan B battle, choose one of 3 speech cards with keys 1-3 or click a card; then click any valid point inside the central board.'
        'Speech strength deploys 2, 4, or 8 units. Each used card refreshes independently after 5 seconds; the other slots remain available.'
        'Same-team pieces repeating the same word share one speech bubble while remaining separate pieces.'
        'At PK 100%, follow the on-screen prompt for the original six-choice charge-shot contradiction phase.'
        'First launch may play the opening comic, followed by the main menu.'
        'Internal build only. Please report reproduction steps and screenshots for bugs.'
    )
    [System.IO.File]::WriteAllLines((Join-Path $stage 'README_PLAYTEST.txt'), $instructions, [System.Text.UTF8Encoding]::new($false))
    $winInfo = [ordered]@{
        exe = Get-ArtifactRecord $exe
        pck = Get-ArtifactRecord $pck
        smoke = $smokeStatus
        packed_resources = 'passed'
        plan_b_csvs = 'passed'
    }
    $winInfo | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stage 'manifest.json') -Encoding UTF8
    $zip = Join-Path $buildDir 'GameJam_InternalPlaytest_win64.zip'
    Write-Host '[Windows] Compressing ZIP...'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
    if (!(Test-Path -LiteralPath $zip)) { throw 'Windows ZIP not created' }
    $report.artifacts.windows = [ordered]@{ zip = Get-ArtifactRecord $zip; details = $winInfo }
}

if ($Platform -in @('Android', 'Both')) {
    $apk = Join-Path $buildDir 'GameJam_Playtest_Android_debug.apk'
    Write-Host '[Android] Export ARM64 debug APK...'
    Invoke-BuildProcess 'Android export' $GodotEditor @(
        '--headless', '--path', $project, '--export-debug', 'Android',
        $apk, '--log-file', (Join-Path $buildDir 'android_export.log')
    ) (Join-Path $buildDir 'android_export_cli.log')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $apkZip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $contents = @($apkZip.Entries | ForEach-Object { $_.FullName })
        if ($contents -notcontains 'AndroidManifest.xml') { throw 'APK missing AndroidManifest.xml' }
        if (@($contents | Where-Object { $_ -like 'lib/arm64-v8a/*' }).Count -eq 0) {
            throw 'APK missing ARM64 native libraries'
        }
        # APK内资源按assets目录交付；验证实际条目，避免只相信export_filter。
        if (@($contents | Where-Object { $_ -match '^assets/(tests/|data/test_only/|scenes/demos/|docs/|tools/|addons/godot_mcp/(native_mcp|tools|ui|utils|translations)/)|^assets/.*/tests/|^assets/data/source_tables/.*\.translation$' }).Count -gt 0) {
            throw 'APK includes TEST_ONLY or development resources'
        }
        if (@($contents | Where-Object { $_ -like 'assets/data/source_tables/*.csv' }).Count -ne 27) {
            throw 'APK must include all 27 production CSV files'
        }
        if (@($contents | Where-Object { $_ -match '^lib/(armeabi-v7a|x86|x86_64)/' }).Count -gt 0) {
            throw 'APK unexpectedly includes a non-ARM64 ABI'
        }
    } finally { $apkZip.Dispose() }
    $report.artifacts.android = [ordered]@{
        apk = Get-ArtifactRecord $apk
        abi = 'arm64-v8a'
        signing = 'debug'
        physical_device_test = 'not_run'
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $buildDir 'build_manifest.json') -Encoding UTF8
Write-Host ('BUILD_OK ' + $buildDir)
Write-Host ('SOURCE_COMMIT ' + $commit)
Get-ChildItem -LiteralPath $buildDir -File | Select-Object Name, Length | Format-Table -AutoSize
