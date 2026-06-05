param(
    [string]$VivadoBin = "",
    [switch]$KeepBuild
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

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $Body
    Write-Host "PASS: $Name"
}

function Reset-XsimWorkdir {
    param([string]$Dir)

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Remove-Item -Recurse -Force (Join-Path $Dir "xsim.dir") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Dir "*.jou") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Dir "*.log") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Dir "*.pb") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Dir "*.wdb") -ErrorAction SilentlyContinue
}

function Invoke-XsimTest {
    param(
        [string]$Name,
        [string]$Top,
        [string]$Snapshot,
        [string[]]$Sources
    )

    $workDir = Join-Path $ArtifactsDir "vivado_xsim_$Name"
    Reset-XsimWorkdir $workDir

    Push-Location $workDir
    try {
        $sourceArgs = @("--sv", "-work", "xil_defaultlib")
        foreach ($src in $Sources) {
            $sourceArgs += (Join-Path "..\.." $src)
        }

        & $script:xvlog @sourceArgs
        & $script:xelab --debug typical --relax --mt 2 `
            -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -L xpm `
            "xil_defaultlib.$Top" -snapshot $Snapshot
        & $script:xsim $Snapshot -R -log simulate.log
    } finally {
        Pop-Location
    }

    if (-not $KeepBuild) {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }
}

$VivadoBin = Resolve-VivadoBin $VivadoBin
$vivado = Join-Path $VivadoBin "vivado.bat"
$script:xvlog = Join-Path $VivadoBin "xvlog.bat"
$script:xelab = Join-Path $VivadoBin "xelab.bat"
$script:xsim = Join-Path $VivadoBin "xsim.bat"

Push-Location $RootDir
try {
    Invoke-Step "Register board IRQ source in Vivado project" {
        & $vivado -mode batch -notrace -nojournal -nolog -source (Join-Path $ArtifactsDir "add_irq_source_to_project.tcl")
    }

    Invoke-Step "Vivado project behavioral simulation" {
        & $vivado -mode batch -notrace -nojournal -nolog -source (Join-Path $ArtifactsDir "run_vivado_behav_sim.tcl")
    }

    Invoke-Step "Vivado XSim board IRQ controller" {
        Invoke-XsimTest "irq_ctrl" "tb_board_irq_controller" "tb_board_irq_controller_behav" @(
            "tb_board_irq_controller.sv",
            "board_irq_controller.v"
        )
    }

    Invoke-Step "Vivado XSim top-level board IRQ loop" {
        Invoke-XsimTest "top_irq" "tb_top_irq_loop" "tb_top_irq_loop_behav" @(
            "tb_top_irq_loop.sv",
            "top.v",
            "board_irq_controller.v",
            "MIO_BUS.V",
            "SCPU.v",
            "ctrl.v",
            "EXT.v",
            "branch.v",
            "ALU.v",
            "RF.v",
            "dm_controller.v"
        )
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "VIVADO_REGRESSION_PASS"
