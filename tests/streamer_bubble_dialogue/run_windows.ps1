param(
    [Parameter(Mandatory = $true)][string]$GodotExe
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$harnessRoot = Join-Path $repoRoot '.godot/sd01/harness'
$outputRoot = Join-Path $repoRoot '.godot/sd01'

# 纯数据测试隔离 Autoload；临时工程及测试输出均留在本工作树的忽略目录。
New-Item -ItemType Directory -Force "$harnessRoot/data/streamer_bubble_dialogue", "$harnessRoot/tests/streamer_bubble_dialogue" | Out-Null
Copy-Item -LiteralPath "$repoRoot/data/streamer_bubble_dialogue/bubble_dialogue_entry.gd", "$repoRoot/data/streamer_bubble_dialogue/bubble_dialogue_config.gd", "$repoRoot/data/streamer_bubble_dialogue/bubble_dialogue_config.tres" -Destination "$harnessRoot/data/streamer_bubble_dialogue"
Copy-Item -LiteralPath "$PSScriptRoot/test_bubble_dialogue_config.gd" -Destination "$harnessRoot/tests/streamer_bubble_dialogue"
[System.IO.File]::WriteAllText("$harnessRoot/project.godot", "config_version=5`n[application]`nconfig/features=PackedStringArray(`"4.7`")`n")

# 等待图形子系统 exe 真实退出，检查进程码及脚本错误，避免只读到启动头。
function Invoke-GodotCheck([string]$Name, [string]$Arguments) {
    $stdout = Join-Path $outputRoot "$Name.stdout"
    $stderr = Join-Path $outputRoot "$Name.stderr"
    $engineLog = Join-Path $outputRoot "$Name.engine.log"
    $process = Start-Process -FilePath $GodotExe -ArgumentList "$Arguments --log-file `"$engineLog`"" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $resultText = (Get-Content -LiteralPath $stdout, $stderr -Raw -Encoding UTF8) -join "`n"
    Write-Host $resultText
    Write-Host "$Name EXIT=$($process.ExitCode)"
    if ($process.ExitCode -ne 0 -or $resultText -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        throw "$Name failed; see $outputRoot"
    }
    return $resultText
}

$version = Invoke-GodotCheck 'version' '--version'
if (($version -join "`n") -notmatch '4\.7\.2\.stable') { throw 'Requires Godot 4.7.2 stable.' }
# 实际运行会编译测试及其 preload 依赖，避免逐文件解析重复同一检查。
$runtime = Invoke-GodotCheck 'runtime' "--headless --path `"$harnessRoot`" --script res://tests/streamer_bubble_dialogue/test_bubble_dialogue_config.gd"
$runtime | Out-Null
if (($runtime -join "`n") -notmatch 'SD-01 RESULT: PASS failures=0') { throw 'Missing SD-01 runtime PASS.' }
Write-Output 'SD-01 Windows headless verification complete.'
