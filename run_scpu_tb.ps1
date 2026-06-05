param(
    [switch]$Dump
)

$ErrorActionPreference = "Stop"

$build = "tb_scpu_core_$PID.out"

iverilog -g2012 -Wall -o $build -s tb_scpu_core `
    tb_scpu_core.sv `
    SCPU.v ctrl.v EXT.v branch.v ALU.v RF.v

if ($Dump) {
    vvp $build +dump
} else {
    vvp $build
}

Remove-Item $build -ErrorAction SilentlyContinue
