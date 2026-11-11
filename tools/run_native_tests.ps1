param(
    [string]$Godot = '',
    [ValidateRange(30, 900)][int]$TimeoutSeconds = 600,
    [switch]$ReferenceOnly,
    [string[]]$Scenes = @()
)
$ErrorActionPreference = 'Stop'
$nativeTestRoot = Split-Path -Parent $PSScriptRoot
if (!$Godot) {
    $Godot = Join-Path $env:USERPROFILE 'Downloads/Godot_v4.7.1-stable_win64.exe'
}
$nativeImportGodot = $Godot -replace '(?<!_console)\.exe$', '_console.exe'
if (!(Test-Path -LiteralPath $nativeImportGodot)) { $nativeImportGodot = $Godot }
& (Join-Path $PSScriptRoot 'run_load_benchmark.ps1') -Godot $nativeImportGodot -PrepareOnly
$nativeTestProject = Join-Path $PSScriptRoot '.benchmark-runtime/project'
$nativeTestLogs = Join-Path $PSScriptRoot '.native-runtime'
New-Item -ItemType Directory -Path $nativeTestLogs -Force | Out-Null
$nativeTestScenes = @(
    'team_model','tactic_types','action_pitch','compact_player','match_engine','match_rotation','match_coaching','match_simulation_config',
    'match_performance_cache','match_stability','lineup_roles','match_day','day_work',
    'national_teams','player_generator','player_development','player_market',
    'player_offer','player_stats','contract_renewal','transfer_market','coach_market',
    'season_preview','season_reputation','potential_rarity','starting_generation',
    'youth_talent_tools','youth_intake','historical_profiles','save_history'
)
if ($Scenes.Count) {
    foreach ($compactScene in $Scenes) { if ($compactScene -notmatch '^[a-z_]+$') { throw 'Invalid test scene name' } }
    $nativeTestScenes = $Scenes
}
if (!$ReferenceOnly -and !$Scenes.Count) { $nativeTestScenes = @('native_simulation') + $nativeTestScenes }
$nativeTestOldBackend = $env:FC_SIMULATION_BACKEND
$nativeTestFailed = @()
try {
    if ($ReferenceOnly) { $env:FC_SIMULATION_BACKEND = 'gdscript' }
    else { $env:FC_SIMULATION_BACKEND = 'native' }
    foreach ($nativeTestScene in $nativeTestScenes) {
        $nativeTestOut = Join-Path $nativeTestLogs "suite-$nativeTestScene.stdout.log"
        $nativeTestErr = Join-Path $nativeTestLogs "suite-$nativeTestScene.stderr.log"
        $nativeTestArgs = @('--headless','--path',('"' + $nativeTestProject + '"'),"res://tests/game/test_$nativeTestScene.tscn")
        $nativeTestProcess = Start-Process -FilePath $Godot -ArgumentList $nativeTestArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $nativeTestOut -RedirectStandardError $nativeTestErr
        # Windows PowerShell 5.1 reports a null ExitCode unless the handle is opened while the process runs.
        $null = $nativeTestProcess.Handle
        $nativeTestTimer = [Diagnostics.Stopwatch]::StartNew()
        $nativeTestFinished = $false
        while ($nativeTestTimer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if ($nativeTestProcess.WaitForExit(1000)) { $nativeTestFinished = $true; break }
            $nativeTestLiveText = ''
            if (Test-Path -LiteralPath $nativeTestErr) {
                $nativeTestLiveReader = $null
                try {
                    $nativeTestLiveReader = [IO.StreamReader]::new([IO.File]::Open($nativeTestErr, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite))
                    $nativeTestLiveText = $nativeTestLiveReader.ReadToEnd()
                } catch [IO.IOException] { }
                finally { if ($null -ne $nativeTestLiveReader) { $nativeTestLiveReader.Dispose() } }
            }
            if ($nativeTestLiveText.Contains('SCRIPT ERROR:')) {
                $nativeTestProcess.Kill()
                $nativeTestProcess.WaitForExit()
                $nativeTestFinished = $true
                break
            }
        }
        if (!$nativeTestFinished) {
            $nativeTestProcess.Kill()
            $nativeTestProcess.WaitForExit()
            $nativeTestFailed += "$nativeTestScene (timeout)"
            continue
        }
        $nativeTestText = [IO.File]::ReadAllText($nativeTestOut) + [IO.File]::ReadAllText($nativeTestErr)
        if ($nativeTestScene -eq 'save_history') {
            $nativeTestText = $nativeTestText -replace '(?m)^ERROR:  --> SQL error: (forced history failure|forced save failure|FOREIGN KEY constraint failed)\r?$', ''
        }
        if ($nativeTestProcess.ExitCode -ne 0 -or $nativeTestText -match '(?m)^\s*FAIL[: ]|SCRIPT ERROR:|^ERROR:|\b[1-9]\d* failed\b') {
            $nativeTestFailed += $nativeTestScene
            Write-Output "FAIL: $nativeTestScene; inspect $nativeTestOut and $nativeTestErr"
        } else {
            Write-Output "PASS: $nativeTestScene"
        }
    }
} finally {
    $env:FC_SIMULATION_BACKEND = $nativeTestOldBackend
}
if ($nativeTestFailed.Count) { throw ('Native regression failures: ' + ($nativeTestFailed -join ', ')) }
Write-Output 'All simulation regressions passed in the isolated project.'
