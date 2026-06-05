`timescale 1ns / 1ps

module tb_board_irq_controller;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg timer_irq_i = 1'b0;
    reg manual_timer_i = 1'b0;
    reg [4:0] btn_i = 5'b0;
    reg [15:0] sw_i = 16'h0000;
    reg cpu_irq_ack = 1'b0;
    reg [7:0] cpu_irq_ack_cause = 8'h00;
    reg mem_w = 1'b0;
    reg [31:0] addr = 32'h0000_0000;
    reg [31:0] wdata = 32'h0000_0000;

    wire irq_valid;
    wire [7:0] irq_cause;
    wire [7:0] irq_pending;
    wire [7:0] irq_mask;

    always #5 clk = ~clk;

    task expect_state;
        input valid;
        input [7:0] cause;
        input [7:0] pending;
        input [7:0] mask;
        input [8*20-1:0] label;
        begin
            if ((irq_valid !== valid) ||
                (irq_cause !== cause) ||
                (irq_pending !== pending) ||
                (irq_mask !== mask)) begin
                $fatal(1,
                       "IRQ_CTRL_FAIL %-0s valid=%0d/%0d cause=%02h/%02h pending=%02h/%02h mask=%02h/%02h",
                       label, irq_valid, valid, irq_cause, cause,
                       irq_pending, pending, irq_mask, mask);
            end
        end
    endtask

    task mmio_write;
        input [31:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr = a;
            wdata = d;
            mem_w = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mem_w = 1'b0;
            addr = 32'h0000_0000;
            wdata = 32'h0000_0000;
        end
    endtask

    task pulse_switch13;
        begin
            @(negedge clk);
            sw_i[13] = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            sw_i[13] = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    task pulse_button0;
        begin
            @(negedge clk);
            btn_i[0] = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            btn_i[0] = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    task pulse_timer_and_switch;
        begin
            @(negedge clk);
            manual_timer_i = 1'b1;
            sw_i[13] = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            manual_timer_i = 1'b0;
            sw_i[13] = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        manual_timer_i = 1'b1;
        btn_i[0] = 1'b1;
        sw_i[13] = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (12) @(posedge clk);
        expect_state(1'b0, 8'h00, 8'h00, 8'h19, "boot_high_ignored");

        @(negedge clk);
        manual_timer_i = 1'b0;
        btn_i[0] = 1'b0;
        sw_i[13] = 1'b0;
        repeat (12) @(posedge clk);
        expect_state(1'b0, 8'h00, 8'h00, 8'h19, "armed_after_low");

        pulse_switch13();
        expect_state(1'b1, 8'h05, 8'h10, 8'h19, "switch_pending");

        @(negedge clk);
        cpu_irq_ack = 1'b1;
        cpu_irq_ack_cause = 8'h05;
        @(posedge clk);
        @(negedge clk);
        cpu_irq_ack = 1'b0;
        cpu_irq_ack_cause = 8'h00;
        expect_state(1'b0, 8'h00, 8'h00, 8'h19, "cpu_ack");

        mmio_write(32'hf000_0014, 32'h0000_0000);
        pulse_button0();
        expect_state(1'b0, 8'h00, 8'h08, 8'h00, "masked_button");

        mmio_write(32'hf000_0014, 32'h0000_0008);
        expect_state(1'b1, 8'h04, 8'h08, 8'h08, "unmasked_button");

        mmio_write(32'hf000_0018, 32'h0000_0008);
        expect_state(1'b0, 8'h00, 8'h00, 8'h08, "mmio_ack");

        mmio_write(32'hf000_0014, 32'h0000_0019);
        repeat (16) @(posedge clk);
        pulse_timer_and_switch();
        expect_state(1'b1, 8'h01, 8'h11, 8'h19, "priority_timer");

        @(negedge clk);
        cpu_irq_ack = 1'b1;
        cpu_irq_ack_cause = 8'h01;
        @(posedge clk);
        @(negedge clk);
        cpu_irq_ack = 1'b0;
        cpu_irq_ack_cause = 8'h00;
        expect_state(1'b1, 8'h05, 8'h10, 8'h19, "priority_fallthrough");

        $display("TB_PASS: board IRQ controller passed.");
        $finish;
    end

    board_irq_controller #(
        .DEBOUNCE_BITS(2),
        .HOLDOFF_BITS(4)
    ) uut(
        .clk(clk),
        .reset(reset),
        .timer_irq_i(timer_irq_i),
        .manual_timer_i(manual_timer_i),
        .btn_i(btn_i),
        .sw_i(sw_i),
        .cpu_irq_ack(cpu_irq_ack),
        .cpu_irq_ack_cause(cpu_irq_ack_cause),
        .mem_w(mem_w),
        .addr(addr),
        .wdata(wdata),
        .irq_valid(irq_valid),
        .irq_cause(irq_cause),
        .irq_pending_o(irq_pending),
        .irq_mask_o(irq_mask)
    );
endmodule
