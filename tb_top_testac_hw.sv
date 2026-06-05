`timescale 1ns / 1ps

module tb_top_testac_hw;
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

`ifdef SYNTH_NETLIST
    wire dut_mem_w = (|dut.u3_wea_mem) | dut.u4_GPIOe0000000_we;
    wire [31:0] dut_data_in = dut.u4_Cpu_data4bus;
    wire [2:0] dut_dm_ctrl = 3'b000;
    wire [9:0] dut_ram_addr = dut.u1_Addr_out[11:2];
    wire [31:0] dut_periph = dut.u1_Data_out;
`else
    wire dut_mem_w = dut.u1_mem_w;
    wire [31:0] dut_data_in = dut.u1_Data_in;
    wire [2:0] dut_dm_ctrl = dut.u1_dm_ctrl;
    wire [9:0] dut_ram_addr = dut.u3_addra;
    wire [31:0] dut_periph = dut.u4_Peripheral_in;
`endif

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
        sw_i = 16'h0000;       // sw_i[2]=0 selects the fast board mode.
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
                $display("TOP_FAIL_HIT cpu_cycle=%0d pc=%08h inst=%08h last_e000=%08h data_in=%08h addr=%08h data_out=%08h wea=%b ram_addr=%03h ram_dout=%08h",
                         cpu_cycle, dut.u1_PC_out, dut.u2_spo, last_e000,
                         dut_data_in, dut.u1_Addr_out, dut.u1_Data_out,
                         dut.u3_wea_mem, dut_ram_addr, dut.u3_douta);
            end

            if (dut_mem_w && (dut.u1_Addr_out == 32'he000_0000)) begin
                e000_writes <= e000_writes + 1;
                last_e000 <= dut.u1_Data_out;
                $display("TOP_E000 cpu_cycle=%0d pc=%08h data=%08h gpioe_we=%b periph=%08h",
                         cpu_cycle, dut.u1_PC_out, dut.u1_Data_out,
                         dut.u4_GPIOe0000000_we, dut_periph);
            end

            if ((cpu_cycle < 120) || dut_mem_w || (dut.u1_PC_out == 32'h0000_0218)) begin
                $display("TOP_TRACE cpu_cycle=%0d pc=%08h inst=%08h mem_w=%b addr=%08h dout=%08h din=%08h dm_ctrl=%03b wea=%b ram_addr=%03h ram_din=%08h ram_dout=%08h",
                         cpu_cycle, dut.u1_PC_out, dut.u2_spo, dut_mem_w,
                         dut.u1_Addr_out, dut.u1_Data_out, dut_data_in,
                         dut_dm_ctrl, dut.u3_wea_mem, dut_ram_addr,
                         dut.u3_Data_write_to_dm, dut.u3_douta);
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
