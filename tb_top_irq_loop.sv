`timescale 1ns / 1ps

module tb_top_irq_loop;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg [4:0] btn_i = 5'b0;
    reg [15:0] sw_i = 16'h0000;

    wire [7:0] disp_an_o;
    wire [7:0] disp_seg_o;
    wire [15:0] led_o;

    always #5 clk = ~clk;

    top dut(
        .rstn(rstn),
        .btn_i(btn_i),
        .sw_i(sw_i),
        .clk(clk),
        .disp_an_o(disp_an_o),
        .disp_seg_o(disp_seg_o),
        .led_o(led_o)
    );

    task wait_irq_done;
        input [7:0] expected_count;
        input [7:0] expected_cause;
        input [8*12-1:0] label;
        integer timeout;
        reg saw_ack;
        begin
            saw_ack = 1'b0;
            for (timeout = 0; timeout < 400; timeout = timeout + 1) begin
                @(posedge dut.u8_Clk_CPU);
                if (dut.u1_ext_irq_ack && (dut.u1_ext_irq_ack_cause == expected_cause))
                    saw_ack = 1'b1;
                if (saw_ack &&
                    (dut.u1_int_debug[23:16] == expected_count) &&
                    (dut.u1_int_debug[15:8] == 8'h00) &&
                    (dut.u1_int_debug[7:0] == expected_cause) &&
                    dut.irq_display_active &&
                    (dut.irq_display_hex == {16'h0000, 8'ha0, expected_cause}) &&
                    (led_o == dut.u7_led_pin)) begin
                    $display("TOP_IRQ_PASS %-0s count=%0d cause=%02h display=%08h led=%04h pc=%08h",
                             label, dut.u1_int_debug[23:16], dut.u1_int_debug[7:0],
                             dut.irq_display_hex, led_o, dut.u1_PC_out);
                    timeout = 400;
                end
            end

            if (!saw_ack ||
                (dut.u1_int_debug[23:16] != expected_count) ||
                (dut.u1_int_debug[15:8] != 8'h00) ||
                (dut.u1_int_debug[7:0] != expected_cause) ||
                !dut.irq_display_active ||
                (dut.irq_display_hex != {16'h0000, 8'ha0, expected_cause}) ||
                (led_o != dut.u7_led_pin)) begin
                $fatal(1,
                       "TOP_IRQ_FAIL %-0s count=%0d cause=%02h status=%02h display=%08h led=%04h ack=%0d pc=%08h pending=%02h mask=%02h valid=%0d ext_cause=%02h",
                       label, dut.u1_int_debug[23:16], dut.u1_int_debug[7:0],
                       dut.u1_int_debug[15:8], dut.irq_display_hex, led_o,
                       saw_ack, dut.u1_PC_out,
                       dut.u11_irq_pending, dut.u11_irq_mask, dut.u11_irq_valid,
                       dut.u11_irq_cause);
            end
        end
    endtask

    task wait_display_restore;
        input [8*12-1:0] label;
        integer timeout;
        reg restored;
        begin
            restored = 1'b0;
            for (timeout = 0; timeout < 40; timeout = timeout + 1) begin
                @(posedge dut.u8_Clk_CPU);
                if (!dut.irq_display_active &&
                    (dut.irq_display_hex == dut.u5_Disp_num)) begin
                    restored = 1'b1;
                    $display("TOP_IRQ_RESTORE %-0s display=%08h pc=%08h",
                             label, dut.irq_display_hex, dut.u1_PC_out);
                    timeout = 40;
                end
            end

            if (!restored) begin
                $fatal(1,
                       "TOP_IRQ_RESTORE_FAIL %-0s active=%0d display=%08h base=%08h pc=%08h",
                       label, dut.irq_display_active, dut.irq_display_hex,
                       dut.u5_Disp_num, dut.u1_PC_out);
            end
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        rstn = 1'b1;
        repeat (20) @(posedge dut.u8_Clk_CPU);

        @(negedge dut.u8_Clk_CPU);
        sw_i[12] = 1'b1;
        repeat (8) @(posedge dut.u8_Clk_CPU);
        wait_irq_done(8'd1, 8'h01, "manual_timer");
        @(negedge dut.u8_Clk_CPU);
        sw_i[12] = 1'b0;
        wait_display_restore("manual_timer");

        repeat (8) @(posedge dut.u8_Clk_CPU);
        @(negedge dut.u8_Clk_CPU);
        btn_i[0] = 1'b1;
        repeat (8) @(posedge dut.u8_Clk_CPU);
        wait_irq_done(8'd2, 8'h04, "button");
        @(negedge dut.u8_Clk_CPU);
        btn_i[0] = 1'b0;
        wait_display_restore("button");

        repeat (8) @(posedge dut.u8_Clk_CPU);
        @(negedge dut.u8_Clk_CPU);
        sw_i[13] = 1'b1;
        repeat (8) @(posedge dut.u8_Clk_CPU);
        wait_irq_done(8'd3, 8'h05, "switch");
        @(negedge dut.u8_Clk_CPU);
        sw_i[13] = 1'b0;
        wait_display_restore("switch");

        $display("TB_PASS: top-level board interrupt loop passed.");
        $finish;
    end
endmodule

module Enter(
    input clk,
    input [4:0] BTN,
    input [15:0] SW,
    output [4:0] BTN_out,
    output [15:0] SW_out
);
    assign BTN_out = BTN;
    assign SW_out = SW;
    wire unused_ok = clk;
endmodule

module clk_div(
    input clk,
    input rst,
    input SW2,
    output reg [31:0] clkdiv,
    output Clk_CPU,
    output clk_locked
);
    assign Clk_CPU = clk;
    assign clk_locked = 1'b1;

    always @(posedge clk or posedge rst) begin
        if (rst)
            clkdiv <= 32'h0000_0000;
        else
            clkdiv <= clkdiv + 32'd1;
    end

    wire unused_ok = SW2;
endmodule

module Counter_x(
    input clk,
    input rst,
    input clk0,
    input clk1,
    input clk2,
    input counter_we,
    input [31:0] counter_val,
    input [1:0] counter_ch,
    output counter0_OUT,
    output counter1_OUT,
    output counter2_OUT,
    output [31:0] counter_out
);
    assign counter0_OUT = 1'b0;
    assign counter1_OUT = 1'b0;
    assign counter2_OUT = 1'b0;
    assign counter_out = 32'h0000_0000;
    wire unused_ok = clk ^ rst ^ clk0 ^ clk1 ^ clk2 ^ counter_we ^
                     counter_val[0] ^ counter_ch[0];
endmodule

module SPIO(
    input clk,
    input rst,
    input EN,
    input [31:0] P_Data,
    output [1:0] counter_set,
    output reg [15:0] LED_out,
    output [15:0] led,
    output [13:0] GPIOf0
);
    assign counter_set = P_Data[1:0];
    assign led = LED_out;
    assign GPIOf0 = 14'h0000;

    always @(posedge clk or posedge rst) begin
        if (rst)
            LED_out <= 16'h0000;
        else if (EN)
            LED_out <= P_Data[15:0];
    end
endmodule

module Multi_8CH32(
    input clk,
    input rst,
    input EN,
    input [2:0] Switch,
    input [63:0] point_in,
    input [63:0] LES,
    input [31:0] data0,
    input [31:0] data1,
    input [31:0] data2,
    input [31:0] data3,
    input [31:0] data4,
    input [31:0] data5,
    input [31:0] data6,
    input [31:0] data7,
    output [7:0] point_out,
    output [7:0] LE_out,
    output reg [31:0] Disp_num
);
    assign point_out = point_in[7:0];
    assign LE_out = LES[7:0];

    always @(*) begin
        case (Switch)
            3'd0: Disp_num = data0;
            3'd1: Disp_num = data1;
            3'd2: Disp_num = data2;
            3'd3: Disp_num = data3;
            3'd4: Disp_num = data4;
            3'd5: Disp_num = data5;
            3'd6: Disp_num = data6;
            default: Disp_num = data7;
        endcase
    end

    wire unused_ok = clk ^ rst ^ EN;
endmodule

module SSeg7(
    input clk,
    input rst,
    input SW0,
    input flash,
    input [31:0] Hexs,
    input [7:0] point,
    input [7:0] LES,
    output [7:0] seg_an,
    output [7:0] seg_sout
);
    assign seg_an = 8'hff;
    assign seg_sout = 8'hff;
    wire unused_ok = clk ^ rst ^ SW0 ^ flash ^ Hexs[0] ^ point[0] ^ LES[0];
endmodule

module rom(
    input [9:0] a,
    output [31:0] spo
);
    assign spo = 32'h0000_0013;
    wire unused_ok = a[0];
endmodule

module ram(
    input clka,
    input [3:0] wea,
    input [9:0] addra,
    input [31:0] dina,
    output reg [31:0] douta
);
    reg [31:0] mem [0:1023];
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0000_0000;
    end

    always @(posedge clka) begin
        if (wea[0])
            mem[addra][7:0] <= dina[7:0];
        if (wea[1])
            mem[addra][15:8] <= dina[15:8];
        if (wea[2])
            mem[addra][23:16] <= dina[23:16];
        if (wea[3])
            mem[addra][31:24] <= dina[31:24];
        douta <= mem[addra];
    end
endmodule
