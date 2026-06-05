`timescale 1ns / 1ps

module tb_top_testac_hw_quiet;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg [4:0] btn_i = 5'b0;
    reg [15:0] sw_i = 16'b0;

    wire [7:0] disp_an_o;
    wire [7:0] disp_seg_o;
    wire [15:0] led_o;

    integer cpu_cycle = 0;
    integer fail_hits = 0;
    integer e000_writes = 0;
    reg [31:0] last_e000 = 32'h0;

    top dut(
        .rstn(rstn),
        .btn_i(btn_i),
        .sw_i(sw_i),
        .clk(clk),
        .disp_an_o(disp_an_o),
        .disp_seg_o(disp_seg_o),
        .led_o(led_o)
    );

    always #5 clk = ~clk;

    initial begin
        sw_i = 16'h0000;
        rstn = 1'b0;
        repeat (40) @(posedge clk);
        rstn = 1'b1;
    end

    always @(posedge dut.u8_Clk_CPU or negedge rstn) begin
        if (!rstn) begin
            cpu_cycle <= 0;
            fail_hits <= 0;
            e000_writes <= 0;
            last_e000 <= 32'h0;
        end else begin
            cpu_cycle <= cpu_cycle + 1;

            if (dut.u1_PC_out == 32'h0000_0218) begin
                fail_hits <= fail_hits + 1;
                $display("TOP_FAIL_HIT cpu_cycle=%0d pc=%08h inst=%08h last_e000=%08h",
                         cpu_cycle, dut.u1_PC_out, dut.u2_spo, last_e000);
            end

            if (dut.u4_GPIOe0000000_we && (dut.u1_Addr_out == 32'he000_0000)) begin
                e000_writes <= e000_writes + 1;
                last_e000 <= dut.u1_Data_out;
                $display("TOP_E000 cpu_cycle=%0d pc=%08h data=%08h",
                         cpu_cycle, dut.u1_PC_out, dut.u1_Data_out);
            end

            if (fail_hits >= 8) begin
                $fatal(1, "TOP_TESTAC_FAIL: stuck in fail loop. cpu_cycle=%0d last_e000=%08h e000_writes=%0d",
                       cpu_cycle, last_e000, e000_writes);
            end

            if ((last_e000 == 32'hffff_ffff) && (dut.u1_PC_out == 32'h0000_0074)) begin
                $display("TOP_TESTAC_PASS: final marker observed. cpu_cycle=%0d pc=%08h", cpu_cycle, dut.u1_PC_out);
                $finish;
            end

            if (cpu_cycle > 500000) begin
                $fatal(1, "TOP_TESTAC_TIMEOUT: cpu_cycle=%0d pc=%08h last_e000=%08h",
                       cpu_cycle, dut.u1_PC_out, last_e000);
            end
        end
    end
endmodule
