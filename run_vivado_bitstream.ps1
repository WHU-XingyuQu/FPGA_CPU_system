param(
    [string]$VivadoBin = "",
    [string]$StatusFile = ""
)

$ErrorActionPreference = "Stop"

$RootDir = $PSScriptRoot
$ArtifactsDir = Join-Path $RootDir "_artifacts"

function Resolve-VivadoBin {
    param([string]$RequestedBin)

    if ($RequestedBin) {
        if (-not (Test-Path (Join-Path $RequestedBin "vivado.bat"))) {
            throw "Vivado bin directory does not contain vivado.bat: $RequestedBin"
        }
        return (Resolve-Path $RequestedBin).Path
    }

    $cmd = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($cmd) {
        return (Split-Path $cmd.Source -Parent)
    }

    $candidate = "D:\Vivado\Vivado\2022.1\bin"
    if (Test-Path (Join-Path $candidate "vivado.bat")) {
        return $candidate
    }

    throw "Cannot find Vivado tools. Pass -VivadoBin <path-to-vivado-bin>."
}

try {
    $VivadoBin = Resolve-VivadoBin $VivadoBin
    $vivado = Join-Path $VivadoBin "vivado.bat"

    function Invoke-VivadoTcl {
        param([string]$Tcl)

        & $vivado -mode batch -notrace -nojournal -nolog -source $Tcl
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado failed for $Tcl with exit code $LASTEXITCODE."
        }
    }

    Push-Location $RootDir
    try {
        Invoke-VivadoTcl (Join-Path $ArtifactsDir "add_irq_source_to_project.tcl")
        Invoke-VivadoTcl (Join-Path $ArtifactsDir "run_vivado_synth_direct.tcl")
        Invoke-VivadoTcl (Join-Path $ArtifactsDir "run_vivado_impl_from_dcp.tcl")
    } finally {
        Pop-Location
    }

    if ($StatusFile) {
        Set-Content -Path $StatusFile -Value "0" -Encoding ASCII
    }
} catch {
    if ($StatusFile) {
        Set-Content -Path $StatusFile -Value "1" -Encoding ASCII
    }
    throw
}
