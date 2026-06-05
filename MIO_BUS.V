`timescale 1ns / 1ps

module MIO_BUS(
    input         clk,
    input         rst,
    input  [4:0]  BTN,
    input  [15:0] SW,
    input  [31:0] PC,
    input         mem_w,
    input  [31:0] Cpu_data2bus,
    input  [31:0] addr_bus,
    input  [31:0] ram_data_out,
    input  [15:0] led_out,
    input  [31:0] counter_out,
    input         counter0_out,
    input         counter1_out,
    input         counter2_out,
    input  [7:0]  irq_pending,
    input  [7:0]  irq_mask,
    input  [7:0]  irq_cause,
    output reg [31:0] Cpu_data4bus,
    output [31:0] ram_data_in,
    output [9:0]  ram_addr,
    output        data_ram_we,
    output        GPIOf0000000_we,
    output        GPIOe0000000_we,
    output        counter_we,
    output [31:0] Peripheral_in
);

    wire is_ram     = (addr_bus[31:12] == 20'h00000);
    wire is_gpio_e  = (addr_bus == 32'he000_0000);
    wire is_gpio_f  = (addr_bus == 32'hf000_0000);
    wire is_counter = (addr_bus[31:4] == 28'hf000000);
    wire is_irq_pending = (addr_bus == 32'hf000_0010);
    wire is_irq_mask    = (addr_bus == 32'hf000_0014);
    wire is_irq_cause   = (addr_bus == 32'hf000_001c);

    assign ram_addr = addr_bus[11:2];
    assign ram_data_in = Cpu_data2bus;
    assign Peripheral_in = Cpu_data2bus;

    assign data_ram_we = mem_w & is_ram;
    assign GPIOe0000000_we = mem_w & is_gpio_e;
    assign GPIOf0000000_we = mem_w & is_gpio_f;
    assign counter_we = mem_w & is_counter & ~is_gpio_f;

    always @(*) begin
        if (is_ram) begin
            Cpu_data4bus = ram_data_out;
        end else if (is_irq_pending) begin
            Cpu_data4bus = {24'b0, irq_pending};
        end else if (is_irq_mask) begin
            Cpu_data4bus = {24'b0, irq_mask};
        end else if (is_irq_cause) begin
            Cpu_data4bus = {24'b0, irq_cause};
        end else if (addr_bus[31:28] == 4'he) begin
            Cpu_data4bus = {16'b0, led_out};
        end else if (addr_bus[31:28] == 4'hf) begin
            Cpu_data4bus = counter_out |
                           {29'b0, counter0_out, counter1_out, counter2_out} |
                           {11'b0, BTN, SW};
        end else begin
            Cpu_data4bus = 32'b0;
        end
    end

    wire unused_ok = clk ^ rst ^ PC[0];

endmodule
