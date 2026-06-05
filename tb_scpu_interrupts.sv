`timescale 1ns / 1ps

module tb_scpu_interrupts;
    localparam integer IMEM_SIZE = 1024;
    localparam [31:0] NOP         = 32'h0000_0013;
    localparam [31:0] ECALL_INST  = 32'h0000_0073;
    localparam [31:0] ERET_INST   = 32'h1020_0073;
    localparam [31:0] ERETN_INST  = 32'h3020_0073;
    localparam [31:0] ILLEGAL_INST = 32'h0000_0000;
    localparam [31:0] TRAP_VECTOR = 32'h1c09_0000;
    localparam [7:0]  CAUSE_TIMER   = 8'h01;
    localparam [7:0]  CAUSE_ILLEGAL = 8'h02;
    localparam [7:0]  CAUSE_SYSCALL = 8'h03;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg MIO_ready = 1'b1;
    reg INT = 1'b0;
    reg ext_irq_valid = 1'b0;
    reg [7:0] ext_irq_cause = 8'h00;
    reg inject_illegal = 1'b0;
    reg inject_syscall = 1'b0;
    reg [31:0] Data_in = 32'h0000_0000;

    wire [31:0] inst_in;
    wire [31:0] rom_inst;
    wire mem_w;
    wire [31:0] PC_out;
    wire [31:0] Addr_out;
    wire [31:0] Data_out;
    wire [2:0]  dm_ctrl;
    wire CPU_MIO;
    wire ext_irq_ack;
    wire [7:0] ext_irq_ack_cause;
    wire [31:0] int_debug;

    reg [31:0] imem [0:IMEM_SIZE-1];
    integer i;

    assign rom_inst = imem[PC_out[11:2]];
    assign inst_in =
        (PC_out == TRAP_VECTOR) ? (((int_debug[7:0] == CAUSE_TIMER) ||
                                    (int_debug[7:0] == 8'h04) ||
                                    (int_debug[7:0] == 8'h05)) ? ERET_INST : ERETN_INST) :
        inject_illegal          ? ILLEGAL_INST :
        inject_syscall          ? ECALL_INST :
                                  rom_inst;

    always #5 clk = ~clk;

    task wait_trap_done;
        input [7:0] expected_count;
        input [7:0] expected_cause;
        input [8*12-1:0] label;
        integer timeout;
        reg saw_vector;
        begin
            saw_vector = 1'b0;
            for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
                @(posedge clk);
                if (PC_out == TRAP_VECTOR)
                    saw_vector = 1'b1;
                if (saw_vector &&
                    (int_debug[23:16] == expected_count) &&
                    (int_debug[7:0] == expected_cause) &&
                    (int_debug[15:8] == 8'h00) &&
                    (PC_out != TRAP_VECTOR)) begin
                    $display("INT_PASS %-0s count=%0d cause=%02h pc=%08h debug=%08h",
                             label, int_debug[23:16], int_debug[7:0], PC_out, int_debug);
                    timeout = 200;
                end
            end

            if (!saw_vector ||
                (int_debug[23:16] != expected_count) ||
                (int_debug[7:0] != expected_cause) ||
                (int_debug[15:8] != 8'h00)) begin
                $fatal(1, "INT_FAIL %-0s count=%0d cause=%02h status=%02h pc=%08h debug=%08h saw_vector=%0d",
                       label, int_debug[23:16], int_debug[7:0], int_debug[15:8],
                       PC_out, int_debug, saw_vector);
            end
        end
    endtask

    initial begin
        for (i = 0; i < IMEM_SIZE; i = i + 1)
            imem[i] = NOP;

        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (10) @(posedge clk);

        INT = 1'b1;
        @(posedge clk);
        INT = 1'b0;
        wait_trap_done(8'd1, CAUSE_TIMER, "timer");

        repeat (4) @(posedge clk);
        inject_illegal = 1'b1;
        @(posedge clk);
        inject_illegal = 1'b0;
        wait_trap_done(8'd2, CAUSE_ILLEGAL, "illegal");

        repeat (4) @(posedge clk);
        inject_syscall = 1'b1;
        @(posedge clk);
        inject_syscall = 1'b0;
        wait_trap_done(8'd3, CAUSE_SYSCALL, "syscall");

        repeat (4) @(posedge clk);
        ext_irq_valid = 1'b1;
        ext_irq_cause = 8'h04;
        wait (ext_irq_ack);
        @(posedge clk);
        ext_irq_valid = 1'b0;
        ext_irq_cause = 8'h00;
        wait_trap_done(8'd4, 8'h04, "external");

        $display("TB_PASS: all interrupt/exception paths passed.");
        $finish;
    end

    SCPU uut (
        .clk      (clk),
        .reset    (reset),
        .MIO_ready(MIO_ready),
        .inst_in  (inst_in),
        .Data_in  (Data_in),
        .mem_w    (mem_w),
        .PC_out   (PC_out),
        .Addr_out (Addr_out),
        .Data_out (Data_out),
        .dm_ctrl  (dm_ctrl),
        .CPU_MIO  (CPU_MIO),
        .INT      (INT),
        .ext_irq_valid(ext_irq_valid),
        .ext_irq_cause(ext_irq_cause),
        .ext_irq_ack(ext_irq_ack),
        .ext_irq_ack_cause(ext_irq_ack_cause),
        .int_debug(int_debug)
    );
endmodule
