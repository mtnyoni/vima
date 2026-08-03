param(
    [ValidateSet("Release", "Debug")]
    [string]$Mode = "Release",
    [ValidatePattern("^[0-9]+(\.[0-9]+)*-[0-9]+$")]
    [string]$Version = "0.1.0-3",
    [string]$SDL3Root = $env:SDL3_DIR,
    [string]$SDL3TtfRoot = $env:SDL3_TTF_DIR,
    [switch]$PortableOnly
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

function Find-InnoCompiler {
    $command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $searchRoots = @(
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles,
        (Join-Path $env:LOCALAPPDATA "Programs")
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $searchRoots) {
        $compiler = Get-ChildItem -Path $root -Filter "ISCC.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "Inno Setup" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($compiler) {
            return $compiler.FullName
        }
    }

    return $null
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

if (-not $PortableOnly) {
    $InnoCompiler = Find-InnoCompiler
    if (-not $InnoCompiler) {
        throw "Inno Setup was not found. Install it with: winget install --id JRSoftware.InnoSetup -e -s winget -i"
    }

    $InstallerDir = Join-Path $ProjectDir "build\installer"
    $InstallerScript = Join-Path $ProjectDir "packaging\windows\vima.iss"
    New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null

    & $InnoCompiler "/DMyAppVersion=$Version" "/O$InstallerDir" $InstallerScript
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $Installer = Join-Path $InstallerDir "Vima-$Version-Setup.exe"
    if (-not (Test-Path $Installer)) {
        throw "Inno Setup completed without producing $Installer."
    }
    Write-Host "Built $Installer"
}
