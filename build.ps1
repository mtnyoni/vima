param(
    [ValidateSet("Release", "Debug")]
    [string]$Mode = "Release",
    [string]$SDL3Root = $env:SDL3_DIR,
    [string]$SDL3TtfRoot = $env:SDL3_TTF_DIR
)

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
$OutputDir = Join-Path $ProjectDir "build\windows"
$Output = Join-Path $OutputDir "vima.exe"

if (-not (Get-Command odin -ErrorAction SilentlyContinue)) {
    throw "Odin is not installed or is not on PATH."
}

if ([string]::IsNullOrWhiteSpace($SDL3Root)) {
    throw "Set SDL3_DIR to the extracted SDL3 development package directory."
}

if ([string]::IsNullOrWhiteSpace($SDL3TtfRoot)) {
    throw "Set SDL3_TTF_DIR to the extracted SDL3_ttf development package directory."
}

function Find-DependencyFile {
    param(
        [string]$Root,
        [string]$Name
    )

    $file = Get-ChildItem -Path $Root -Filter $Name -File -Recurse |
        Select-Object -First 1
    if (-not $file) {
        throw "Could not find $Name below $Root."
    }
    return $file
}

$SDL3Lib = Find-DependencyFile -Root $SDL3Root -Name "SDL3.lib"
$SDL3TtfLib = Find-DependencyFile -Root $SDL3TtfRoot -Name "SDL3_ttf.lib"
$SDL3Dll = Find-DependencyFile -Root $SDL3Root -Name "SDL3.dll"
$SDL3TtfDll = Find-DependencyFile -Root $SDL3TtfRoot -Name "SDL3_ttf.dll"

$FontPath = "C:\Windows\Fonts\segoeui.ttf"
if (-not (Test-Path $FontPath)) {
    throw "The expected Windows font was not found at $FontPath."
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$LinkerFlags = "/LIBPATH:`"$($SDL3Lib.DirectoryName)`" /LIBPATH:`"$($SDL3TtfLib.DirectoryName)`""
$OdinArgs = @(
    "build",
    $ProjectDir,
    "-out:$Output",
    "-extra-linker-flags:$LinkerFlags"
)

if ($Mode -eq "Debug") {
    $OdinArgs += "-debug"
} else {
    $OdinArgs += "-o:speed"
}

& odin @OdinArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

# Copy SDL and any companion runtime DLLs shipped beside them.
@($SDL3Dll.DirectoryName, $SDL3TtfDll.DirectoryName) |
    Select-Object -Unique |
    ForEach-Object {
        Get-ChildItem -Path $_ -Filter "*.dll" -File |
            Copy-Item -Destination $OutputDir -Force
    }

Write-Host "Built $Output"
