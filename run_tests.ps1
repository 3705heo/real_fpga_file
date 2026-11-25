[CmdletBinding()]
param(
    [ValidateSet('Auto', 'XSim', 'Icarus')]
    [string]$Simulator = 'Auto',
    [string]$VivadoBin,
    [string]$BuildDir,
    [string[]]$Top
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$rtl = Join-Path $project 'rtl'
$designFiles = @(Get-ChildItem -LiteralPath $rtl -Filter '*.v' -File | Sort-Object Name)
$testFiles = @(Get-ChildItem -LiteralPath (Join-Path $project 'sim') -Filter 'tb_*.v' -File | Sort-Object Name)
if ($testFiles.Count -eq 0) { throw 'No testbenches found.' }
if ($Top) {
    foreach ($name in $Top) {
        if ($name -notin $testFiles.BaseName) { throw "Unknown testbench $name." }
    }
} else {
    $Top = $testFiles.BaseName
}
if (-not $BuildDir) { $BuildDir = Join-Path $project 'build/sim_tests' }

function Find-VivadoTool([string]$name) {
    if ($VivadoBin) {
        foreach ($suffix in '.bat', '.exe', '') {
            $candidate = Join-Path $VivadoBin "$name$suffix"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        return
    }
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    if ($env:XILINX_VIVADO) {
        foreach ($suffix in '.bat', '') {
            $candidate = Join-Path $env:XILINX_VIVADO "bin/$name$suffix"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
}

function Invoke-SimulationTool([string]$Executable, [string[]]$Arguments) {
    $output = & $Executable @Arguments | Out-String
    if ($output.Trim()) { Write-Host $output.TrimEnd() }
    if ($LASTEXITCODE -ne 0) { throw "$Executable exited with status $LASTEXITCODE." }
    return $output
}

$xvlog = Find-VivadoTool 'xvlog'
$xelab = Find-VivadoTool 'xelab'
$xsim = Find-VivadoTool 'xsim'
$iverilog = Get-Command 'iverilog' -ErrorAction SilentlyContinue
$vvp = Get-Command 'vvp' -ErrorAction SilentlyContinue
if ($Simulator -eq 'Auto') {
    if ($xvlog -and $xelab -and $xsim) { $Simulator = 'XSim' }
    elseif ($iverilog -and $vvp) { $Simulator = 'Icarus' }
    else { throw 'Set -VivadoBin to the Vivado 2024.1 bin directory or put Icarus Verilog on PATH.' }
}
if ($Simulator -eq 'XSim' -and (-not ($xvlog -and $xelab -and $xsim))) {
    throw 'XSim requires xvlog, xelab and xsim.'
}
if ($Simulator -eq 'Icarus' -and (-not ($iverilog -and $vvp))) {
    throw 'Icarus requires iverilog and vvp.'
}

$files = @($designFiles.FullName) + @($testFiles.FullName)
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$failures = @()
Push-Location -LiteralPath $BuildDir
try {
    if ($Simulator -eq 'XSim') {
        $null = Invoke-SimulationTool $xvlog (@('--include', $rtl) + $files)
    }
    foreach ($name in $Top) {
        Write-Host "=== $name ($Simulator) ==="
        try {
            if ($Simulator -eq 'XSim') {
                $snapshot = "${name}_snapshot"
                $null = Invoke-SimulationTool $xelab @("work.$name", '-debug', 'typical', '-s', $snapshot)
                $output = Invoke-SimulationTool $xsim @($snapshot, '-runall', '-log', "$name.log")
            } else {
                $binary = "$name.vvp"
                $null = Invoke-SimulationTool $iverilog.Source (@('-g2012', '-I', $rtl, '-s', $name, '-o', $binary) + $files)
                $output = Invoke-SimulationTool $vvp.Source @($binary)
            }
            if ($output -notmatch "(?m)^\s*PASS $name\b" -or $output -match '(?mi)^\s*(?:FATAL|ERROR):') {
                throw "Missing PASS marker or simulator errors in $name."
            }
        } catch {
            $failures += $name
            Write-Warning $_
        }
    }
} finally {
    Pop-Location
}
if ($failures.Count) { throw "Failed tests: $($failures -join ', ')." }
Write-Host "$($Top.Count) of $($Top.Count) testbenches passed ($Simulator)."
