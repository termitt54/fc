param(
    [string]$Godot = '',
    [ValidateRange(2, 10000)][int]$Clubs = 100,
    [ValidateRange(1, 1000)][int]$Seasons = 2,
    [ValidateRange(2, 40)][int]$LeagueSize = 10,
    [ValidateRange(25, 100)][int]$PlayersPerClub = 50,
    [int]$Seed = 4242,
    [ValidateRange(10, 86400)][int]$MaxSeconds = 900,
    [switch]$EmptyStart,
    [switch]$MatchOnly,
    [switch]$MarketOnly,
    [switch]$Sliced,
    [ValidateRange(1, 5)][int]$MarketDays = 5,
    [switch]$ContinueOnSquadErrors,
    [switch]$PrepareOnly,
    [string]$TestScene = ''
)
$ErrorActionPreference = 'Stop'
$benchmarkRoot = Split-Path -Parent $PSScriptRoot
$benchmarkRuntime = Join-Path $PSScriptRoot '.benchmark-runtime'
$benchmarkProject = Join-Path $benchmarkRuntime 'project'
if (!$Godot) {
    $benchmarkCandidates = @(
        (Join-Path $env:USERPROFILE 'Downloads/Godot_v4.7.1-stable_win64_console.exe'),
        (Join-Path $env:USERPROFILE 'Desktop/Godot_v4.7.1-stable_win64.exe')
    )
    $benchmarkCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($benchmarkCommand) { $benchmarkCandidates += $benchmarkCommand.Source }
    $Godot = $benchmarkCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (!$Godot -or !(Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Pass -Godot with the Godot console executable path.' }
New-Item -ItemType Directory -Force -Path $benchmarkProject | Out-Null
# The parent is ignored by the working project, not by the isolated child project.
Set-Content -LiteralPath (Join-Path $benchmarkRuntime '.gdignore') -Value ''
foreach ($benchmarkFolder in @('game','autoload','database','scenes','ui','tests','addons','assets','flags','logos')) {
    Copy-Item -LiteralPath (Join-Path $benchmarkRoot $benchmarkFolder) -Destination $benchmarkProject -Recurse -Force
}
$benchmarkConfig = @'
config_version=5
[application]
config/name="FC Load Benchmark"
config/use_custom_user_dir=true
config/custom_user_dir_name="fc-load-benchmark"
run/main_scene="res://tests/performance/load_benchmark.tscn"
[autoload]
DatabaseManager="*res://autoload/database_manager.gd"
WorldDatabase="*res://autoload/world_database.gd"
GameSession="*res://game/game_session.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
'@
Set-Content -LiteralPath (Join-Path $benchmarkProject 'project.godot') -Value $benchmarkConfig -Encoding utf8
$benchmarkResults = Join-Path $benchmarkRoot 'tests/performance/results'
New-Item -ItemType Directory -Force -Path $benchmarkResults | Out-Null
Write-Output "Isolated project: $benchmarkProject"
& $Godot --headless --quiet --path $benchmarkProject --import --log-file (Join-Path $benchmarkRuntime 'import.log')
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
if (Select-String -LiteralPath (Join-Path $benchmarkRuntime 'import.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Godot import reported errors; inspect import.log.' }
if ($PrepareOnly) { return }
if ($TestScene) {
    if ($TestScene -notmatch '^res://tests/(game|database)/test_[a-z_]+\.tscn$') { throw 'TestScene must be an existing test scene under res://tests/game or database.' }
    & $Godot --headless --path $benchmarkProject --scene $TestScene --log-file (Join-Path $benchmarkRuntime 'regression.log')
    if ($LASTEXITCODE -ne 0) { throw "Regression failed ($LASTEXITCODE)." }
    $benchmarkRegressionErrors = Select-String -LiteralPath (Join-Path $benchmarkRuntime 'regression.log') -Pattern 'SCRIPT ERROR:|ERROR:'
    foreach ($benchmarkRegressionError in $benchmarkRegressionErrors) {
        # This test deliberately makes SQLite reject INSERT and COMMIT to verify rollback.
        $benchmarkExpectedSqlFault = $TestScene -eq 'res://tests/game/test_save_history.tscn' -and $benchmarkRegressionError.Line -match '^ERROR:  --> SQL error: (forced history failure|forced save failure|FOREIGN KEY constraint failed)$'
        if (!$benchmarkExpectedSqlFault) { throw 'Regression reported unexpected Godot errors; inspect regression.log.' }
    }
    return
}
$benchmarkStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$benchmarkReport = Join-Path $benchmarkResults "clubs-$Clubs-seasons-$Seasons-$benchmarkStamp.json"
$benchmarkLog = Join-Path $benchmarkResults "clubs-$Clubs-seasons-$Seasons-$benchmarkStamp.log"
$benchmarkArguments = @('--headless','--path',$benchmarkProject,'--log-file',$benchmarkLog,'--',
    "--clubs=$Clubs", "--seasons=$Seasons", "--league-size=$LeagueSize", "--players-per-club=$PlayersPerClub",
    "--seed=$Seed", "--max-seconds=$MaxSeconds", "--report=$benchmarkReport")
if ($EmptyStart) { $benchmarkArguments += '--empty-start' }
if ($MatchOnly) { $benchmarkArguments += '--match-only' }
if ($MarketOnly) { $benchmarkArguments += @('--market-only', "--market-days=$MarketDays") }
if ($Sliced) { $benchmarkArguments += '--sliced' }
if ($ContinueOnSquadErrors) { $benchmarkArguments += '--continue-squad-errors' }
& $Godot @benchmarkArguments
$benchmarkExit = $LASTEXITCODE
Write-Output "Report: $benchmarkReport"
Write-Output "Log: $benchmarkLog"
if ($benchmarkExit -ne 0) { throw "Benchmark stopped or failed ($benchmarkExit); inspect its report and log." }
if (!(Test-Path -LiteralPath $benchmarkReport)) { throw 'Benchmark did not produce a report.' }
$benchmarkData = Get-Content -LiteralPath $benchmarkReport -Raw | ConvertFrom-Json
if ($benchmarkData.status -ne 'passed') { throw "Benchmark status: $($benchmarkData.status)" }
if (Select-String -LiteralPath $benchmarkLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Godot reported errors; inspect the benchmark log.' }
