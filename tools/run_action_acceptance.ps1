param([switch]$FullSuite, [switch]$SkipAudit, [ValidateSet("v3","v4")][string]$Version="v3")
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$project=Join-Path $root 'tools/.benchmark-runtime/project'
$godot=Join-Path $env:USERPROFILE 'Downloads/Godot_v4.7.1-stable_win64.exe'
$logs=Join-Path $root 'tools/.native-runtime'
$results=Join-Path $root 'tests/performance/results'
function Run-Audit([string]$name,[string]$scene,[string[]]$extra,[int]$timeout=300) {
 $arguments=@('--headless','--path',('"'+$project+'"'),('res://tests/performance/'+$scene+'.tscn'),'--')+$extra
 $p=Start-Process $godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs ($name+'.stdout.log')) -RedirectStandardError (Join-Path $logs ($name+'.stderr.log'))
 if (!$p.WaitForExit($timeout*1000)) { $p.Kill(); throw ($name+' timed out') }
 $errorText=[IO.File]::ReadAllText((Join-Path $logs ($name+'.stderr.log')))
 if ($p.ExitCode -ne 0 -or $errorText.Contains('SCRIPT ERROR:')) { throw ($name+' failed; inspect logs') }
 Write-Output ('PASS '+$name)
}
if (!$SkipAudit) { Run-Audit 'final-action-audit' 'action_pitch_audit' @(('"'+(Join-Path $results ('action-pitch-'+$Version+'-audit.json'))+'"')) }
$snapshot=Join-Path $root 'tools/.benchmark-runtime/user-performance-oct18-snapshot'
Run-Audit 'final-action-day' 'user_day_performance' @(('"'+$snapshot+'"'))
Copy-Item -LiteralPath (Join-Path $snapshot 'day-performance.json') -Destination (Join-Path $results ('action-pitch-'+$Version+'-day.json')) -Force
Run-Audit 'final-action-frames60' 'user_day_performance' @(('"'+$snapshot+'"'),'frames60')
Copy-Item -LiteralPath (Join-Path $snapshot 'day-performance-frames60.json') -Destination (Join-Path $results ('action-pitch-'+$Version+'-day-frames60.json')) -Force
Run-Audit 'final-action-generations' 'football_generations_acceptance' @(('"'+(Join-Path $results ('action-pitch-'+$Version+'-generations.json'))+'"'),'10','100') 600
if ($FullSuite) { & (Join-Path $root 'tools/run_native_tests.ps1') -TimeoutSeconds 900 }
