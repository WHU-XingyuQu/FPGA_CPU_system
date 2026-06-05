`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/13 14:27:05
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module top(
input rstn,
input [4:0]btn_i,
input [15:0]sw_i,
input clk,
output [7:0]disp_an_o,
output [7:0]disp_seg_o,
output [15:0]led_o
    );
wire [15:0]u10_sw_o;
wire [4:0]u10_btn_o;//U10_Enter的输出

wire [31:0]u8_clkdiv;
wire u8_clk_locked;
wire cpu_reset;
wire cpu_reset_async;
wire u8_Clk_CPU;//U8_clk_div的输出

wire [31:0]u4_Cpu_data4bus;
wire [31:0]u4_Peripheral_in;
wire [31:0]u4_ram_data_in;
wire u4_counter_we;
wire u4_GPIOe0000000_we;
wire u4_GPIOf0000000_we;
//u4_MIO_BUS的输出

wire [1:0]u7_counter_set;
wire [15:0]u7_LED_out;//U7_SPIO的输出

wire u9_counter0_OUT;
wire u9_counter1_OUT;
wire u9_counter2_OUT;//U9_Counter_x的输出

wire u1_mem_w;
wire [31:0]u1_Data_in;
wire [31:0]u1_Data_out;
wire [31:0]u1_Addr_out;
wire [2:0]u1_dm_ctrl;
wire u1_CPU_MIO;
wire [31:0]u1_PC_out;//U1_SCPU的输出

wire [3:0] u3_wea_mem;
wire [9:0] u3_addra;
wire [31:0] u3_Data_write_to_dm;
wire [31:0] u3_douta;

wire [31:0] u2_spo;//u2_ROMD的输出

wire [7:0] u5_point_out;
wire [31:0] u5_Disp_num;
wire [7:0] u5_LE_out;//u5_Multi_8CH32的输出

wire [31:0] u4_counter_out;
wire [31:0] u1_inst_in;
wire [31:0] u1_int_debug;
wire        u1_ext_irq_ack;
wire [7:0]  u1_ext_irq_ack_cause;
wire        u11_irq_valid;
wire [7:0]  u11_irq_cause;
wire [7:0]  u11_irq_pending;
wire [7:0]  u11_irq_mask;
wire [15:0] u7_led_pin;
wire [31:0] irq_display_hex;
wire        irq_latched_source_active;
reg  [1:0]  exception_sw_d;
reg  [1:0]  exception_irq_pulse;
reg  [15:0] irq_led_latch;
reg         irq_display_active;
reg  [1:0]  cpu_reset_sync = 2'b11;
localparam [31:0] TRAP_VECTOR = 32'h1c09_0000;
localparam [31:0] ECALL_INST  = 32'h0000_0073;
localparam [31:0] ERET_INST   = 32'h1020_0073;
localparam [31:0] ERETN_INST  = 32'h3020_0073;
localparam [31:0] ILLEGAL_INST = 32'h0000_0000;
`ifdef SYNTHESIS
localparam IRQ_DEBOUNCE_BITS = 20;
localparam IRQ_HOLDOFF_BITS  = 20;
`else
localparam IRQ_DEBOUNCE_BITS = 2;
localparam IRQ_HOLDOFF_BITS  = 4;
`endif

assign cpu_reset_async = !rstn | !u8_clk_locked;
assign cpu_reset = cpu_reset_sync[1];

Enter U10_Enter(.clk(clk),.SW(sw_i),.BTN(btn_i),.SW_out(u10_sw_o),.BTN_out(u10_btn_o));


clk_div U8_clk_div(.clk(clk),.rst(!rstn),.SW2(sw_i[2]),.clkdiv(u8_clkdiv),.Clk_CPU(u8_Clk_CPU),.clk_locked(u8_clk_locked));

always @(posedge u8_Clk_CPU) begin
    if (cpu_reset_async) begin
        cpu_reset_sync <= 2'b11;
    end else begin
        cpu_reset_sync <= {cpu_reset_sync[0], 1'b0};
    end
end



//,GPIOf0去掉
SPIO U7_SPIO(.clk(u8_Clk_CPU),.rst(cpu_reset),.EN(u4_GPIOf0000000_we),.P_Data(u4_Peripheral_in),
.counter_set(u7_counter_set),.LED_out(u7_LED_out),.led(u7_led_pin));

assign led_o =
    u10_sw_o[10]  ? u10_sw_o :
    u10_sw_o[11]  ? {11'b0, u10_btn_o} :
                     u7_led_pin;


//,.counter_out被去掉
Counter_x U9_Counter_x(.clk(u8_Clk_CPU),.rst(cpu_reset),.clk0(u8_clkdiv[6]),.clk1(u8_clkdiv[9]),.clk2(u8_clkdiv[11]),.counter_we(u4_counter_we),
.counter_val(u4_Peripheral_in),.counter_ch(u7_counter_set),.counter0_OUT(u9_counter0_OUT),.counter1_OUT(u9_counter1_OUT),
.counter2_OUT(u9_counter2_OUT));


//data_ram_we去掉
MIO_BUS U4_MIO_BUS(.clk(clk),.rst(!rstn),.BTN(u10_btn_o),.SW(u10_sw_o),
.PC(u1_PC_out),.mem_w(u1_mem_w),.Cpu_data2bus(u1_Data_out),.addr_bus(u1_Addr_out),.ram_data_out(u3_douta),.led_out(u7_LED_out),
.counter_out(u4_counter_out),.counter0_out(u9_counter0_OUT),.counter1_out(u9_counter1_OUT),
.counter2_out(u9_counter2_OUT),.irq_pending(u11_irq_pending),.irq_mask(u11_irq_mask),.irq_cause(u11_irq_cause),
.Cpu_data4bus(u4_Cpu_data4bus),.ram_data_in(u4_ram_data_in),
.ram_addr(u3_addra),.GPIOf0000000_we(u4_GPIOf0000000_we),.GPIOe0000000_we(u4_GPIOe0000000_we),.counter_we(u4_counter_we),
.Peripheral_in(u4_Peripheral_in));


ram U3_RAM_B(.clka(u8_Clk_CPU),.wea(u3_wea_mem),.addra(u3_addra),.dina(u3_Data_write_to_dm),.douta(u3_douta));


dm_controller U3_dm_controller(.mem_w(u1_mem_w),.Addr_in(u1_Addr_out),.Data_write(u4_ram_data_in),
.dm_ctrl(u1_dm_ctrl),.Data_read_from_dm(u4_Cpu_data4bus),.Data_read(u1_Data_in),
.Data_write_to_dm(u3_Data_write_to_dm),.wea_mem(u3_wea_mem));

rom U2_ROMD(.a(u1_PC_out[11:2]),.spo(u2_spo));

board_irq_controller #(
    .DEBOUNCE_BITS(IRQ_DEBOUNCE_BITS),
    .HOLDOFF_BITS (IRQ_HOLDOFF_BITS)
) U11_IRQ(
    .clk              (u8_Clk_CPU),
    .reset            (cpu_reset),
    .timer_irq_i      (1'b0),
     .manual_timer_i   (u10_sw_o[12]),
    .btn_i            (u10_btn_o),
    .sw_i             (u10_sw_o),
    .cpu_irq_ack      (u1_ext_irq_ack),
    .cpu_irq_ack_cause(u1_ext_irq_ack_cause),
    .mem_w            (u1_mem_w),
    .addr             (u1_Addr_out),
    .wdata            (u1_Data_out),
    .irq_valid        (u11_irq_valid),
    .irq_cause        (u11_irq_cause),
    .irq_pending_o    (u11_irq_pending),
    .irq_mask_o       (u11_irq_mask)
);

assign irq_latched_source_active =
    (irq_led_latch[7:0] == 8'h01) ? u10_sw_o[12]  :
    (irq_led_latch[7:0] == 8'h04) ? (|u10_btn_o)  :
    (irq_led_latch[7:0] == 8'h05) ? u10_sw_o[13]  :
                                    1'b0;

always @(posedge u8_Clk_CPU or posedge cpu_reset) begin
    if (cpu_reset) begin
        irq_led_latch <= 16'h0000;
        irq_display_active <= 1'b0;
    end else if (u1_ext_irq_ack) begin
        irq_led_latch <= {8'ha0, u1_ext_irq_ack_cause};
        irq_display_active <= 1'b1;
    end else if (!irq_latched_source_active) begin
        irq_display_active <= 1'b0;
    end
end

// SW[14] and SW[15] remain debug-only exception injection controls.
always @(posedge u8_Clk_CPU or posedge cpu_reset) begin
    if (cpu_reset) begin
        exception_sw_d <= 2'b00;
        exception_irq_pulse <= 2'b00;
    end else begin
        exception_irq_pulse <= u10_sw_o[15:14] & ~exception_sw_d;
        exception_sw_d <= u10_sw_o[15:14];
    end
end

assign u1_inst_in =
    (u1_PC_out == TRAP_VECTOR) ? (((u1_int_debug[7:0] == 8'h01) ||
                                   (u1_int_debug[7:0] == 8'h04) ||
                                   (u1_int_debug[7:0] == 8'h05)) ? ERET_INST : ERETN_INST) :
    exception_irq_pulse[0]    ? ILLEGAL_INST :
    exception_irq_pulse[1]    ? ECALL_INST :
                                 u2_spo;

SCPU U1_SCPU(.clk(u8_Clk_CPU),.reset(cpu_reset),.MIO_ready(u1_CPU_MIO),
.inst_in(u1_inst_in),.Data_in(u1_Data_in),.mem_w(u1_mem_w),.PC_out(u1_PC_out),
.Addr_out(u1_Addr_out),.Data_out(u1_Data_out),.dm_ctrl(u1_dm_ctrl),
.CPU_MIO(u1_CPU_MIO),.INT(1'b0),.ext_irq_valid(u11_irq_valid),.ext_irq_cause(u11_irq_cause),
.ext_irq_ack(u1_ext_irq_ack),.ext_irq_ack_cause(u1_ext_irq_ack_cause),.int_debug(u1_int_debug));


//point_in是64位的？
Multi_8CH32 U5_Multi_8CH32(.clk(u8_Clk_CPU),.rst(cpu_reset),.EN(u4_GPIOe0000000_we),.Switch(u10_sw_o[7:5]),
.point_in(64'b0),
.LES(~64'b0),.data0(u4_Peripheral_in),.data1({1'b0,1'b0,u1_PC_out[31:2]}),.data2(u1_inst_in),
.data3(u1_int_debug),.data4(u1_Addr_out),.data5(u1_Data_out),.data6(u4_Cpu_data4bus),
.data7(u1_PC_out),.point_out(u5_point_out),.LE_out(u5_LE_out),.Disp_num(u5_Disp_num));

assign irq_display_hex = irq_display_active ? {16'h0000, irq_led_latch} : u5_Disp_num;

SSeg7 U6_SSeg7(.clk(clk),.rst(!rstn),.SW0(u10_sw_o[0]),
.flash(u8_clkdiv[10]),.Hexs(irq_display_hex),.point(u5_point_out),
.LES(u5_LE_out),.seg_an(disp_an_o),.seg_sout(disp_seg_o));
endmodule
