param(
    [switch]$Bootstrap,
    [ValidateRange(1, 64)][int]$Jobs = 8,
    [string]$Python = '',
    [ValidatePattern('^[a-z0-9_]+$')][string]$LibraryName = 'fc_sim_core_v5_attraction'
)
$ErrorActionPreference = 'Stop'
$nativeProject = Split-Path -Parent $PSScriptRoot
$nativeRoot = Join-Path $nativeProject 'native'
$nativeRuntime = Join-Path $PSScriptRoot '.native-runtime'
$nativeLock = Get-Content -LiteralPath (Join-Path $nativeRoot 'toolchain.lock.json') -Raw | ConvertFrom-Json
if (!$Python) {
    $nativeBundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (Test-Path -LiteralPath $nativeBundledPython) { $Python = $nativeBundledPython }
    else { $Python = (Get-Command python -ErrorAction Stop).Source }
}
New-Item -ItemType Directory -Path $nativeRuntime -Force | Out-Null
Set-Content -LiteralPath (Join-Path $nativeRuntime '.gdignore') -Value ''
Set-Content -LiteralPath (Join-Path $nativeRuntime '.gitignore') -Value "*`n!.gitignore`n!.gdignore"
$nativeSdk = Join-Path $nativeRuntime 'godot-cpp'
$nativeCompiler = Join-Path $nativeRuntime $nativeLock.compiler_directory
$nativePythonPackages = Join-Path $nativeRuntime 'python'
if ($Bootstrap) {
    if (!(Test-Path -LiteralPath (Join-Path $nativeSdk '.git'))) {
        & git clone --branch $nativeLock.godot_cpp_branch --single-branch $nativeLock.godot_cpp_repository $nativeSdk
        if ($LASTEXITCODE -ne 0) { throw 'godot-cpp download failed.' }
        & git -C $nativeSdk checkout --detach $nativeLock.godot_cpp_commit
        if ($LASTEXITCODE -ne 0) { throw 'Pinned godot-cpp revision is unavailable.' }
    }
    if (!(Test-Path -LiteralPath (Join-Path $nativeCompiler 'bin/clang++.exe'))) {
        $nativeArchive = Join-Path $nativeRuntime 'llvm-mingw.zip'
        Invoke-WebRequest -Uri $nativeLock.compiler_url -OutFile $nativeArchive
        if ((Get-FileHash -LiteralPath $nativeArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nativeLock.compiler_sha256) {
            throw 'Compiler checksum does not match toolchain.lock.json.'
        }
        Expand-Archive -LiteralPath $nativeArchive -DestinationPath $nativeRuntime -Force
    }
    if (!(Test-Path -LiteralPath (Join-Path $nativePythonPackages 'SCons'))) {
        & $Python -m pip install --target $nativePythonPackages "scons==$($nativeLock.scons_version)"
        if ($LASTEXITCODE -ne 0) { throw 'SCons installation failed.' }
    }
}
if (!(Test-Path -LiteralPath (Join-Path $nativeCompiler 'bin/clang++.exe')) -or !(Test-Path -LiteralPath (Join-Path $nativePythonPackages 'SCons'))) {
    throw 'Build dependencies are missing. Run tools/build_native.ps1 -Bootstrap once.'
}
$nativeRevision = & git -C $nativeSdk rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $nativeRevision.Trim() -ne $nativeLock.godot_cpp_commit) { throw 'Unexpected godot-cpp revision.' }
# LLVM 23 requires the standard declaration of realloc/free in this SDK source.
$nativeSdkSource = Join-Path $nativeSdk 'src/godot.cpp'
$nativeSdkText = [IO.File]::ReadAllText($nativeSdkSource)
if (!$nativeSdkText.Contains('#include <cstdlib>')) {
    [IO.File]::WriteAllText($nativeSdkSource, "#include <cstdlib>`n" + $nativeSdkText)
}
$nativeOldPath = $env:PATH
$nativeOldPythonPath = $env:PYTHONPATH
try {
    $env:PATH = "$(Join-Path $nativeCompiler 'bin');$nativeOldPath"
    $env:PYTHONPATH = $nativePythonPackages
    & $Python -m SCons -C $nativeRoot platform=windows target=template_release use_mingw=yes use_llvm=yes "mingw_prefix=$nativeCompiler" "library_name=$LibraryName" "build_profile=$(Join-Path $nativeRoot 'build_profile.json')" -j $Jobs
    if ($LASTEXITCODE -ne 0) { throw "Native build failed ($LASTEXITCODE). No new module was installed." }
} finally {
    $env:PATH = $nativeOldPath
    $env:PYTHONPATH = $nativeOldPythonPath
}
Write-Output "Native module built: $(Join-Path $nativeProject "addons/fc_sim_core/bin/$LibraryName.windows.template_release.x86_64.dll")"
