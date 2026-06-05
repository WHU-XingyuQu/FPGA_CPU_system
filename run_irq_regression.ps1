param(
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"

function Run-IverilogTest {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$Sources
    )

    $build = "$Name`_$PID.out"
    try {
        iverilog -g2012 -Wall -o $build -s $Top @Sources
        vvp $build
    } finally {
        if (-not $KeepBuild) {
            Remove-Item $build -ErrorAction SilentlyContinue
        }
    }
}

Run-IverilogTest "tb_scpu_core" "tb_scpu_core" @(
    "tb_scpu_core.sv",
    "SCPU.v", "ctrl.v", "EXT.v", "branch.v", "ALU.v", "RF.v"
)

Run-IverilogTest "tb_irq_ctrl" "tb_board_irq_controller" @(
    "tb_board_irq_controller.sv",
    "board_irq_controller.v"
)

Run-IverilogTest "tb_interrupts" "tb_scpu_interrupts" @(
    "tb_scpu_interrupts.sv",
    "SCPU.v", "ctrl.v", "EXT.v", "branch.v", "ALU.v", "RF.v"
)

Run-IverilogTest "tb_top_irq_loop" "tb_top_irq_loop" @(
    "tb_top_irq_loop.sv",
    "top.v", "board_irq_controller.v", "MIO_BUS.V", "SCPU.v",
    "ctrl.v", "EXT.v", "branch.v", "ALU.v", "RF.v", "dm_controller.v"
)

Run-IverilogTest "tb_testac" "tb_scpu_testac" @(
    "tb_scpu_testac.sv",
    "SCPU.v", "ctrl.v", "EXT.v", "branch.v", "ALU.v", "RF.v"
)
