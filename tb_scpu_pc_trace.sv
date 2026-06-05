`timescale 1ns / 1ps

module tb_scpu_pc_trace;
    localparam integer IMEM_SIZE = 32;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_IMM    = 7'b0010011;

    reg clk;
    reg reset;
    reg MIO_ready;
    reg INT;

    wire [31:0] inst_in;
    reg  [31:0] Data_in;
    wire mem_w;
    wire [31:0] PC_out;
    wire [31:0] Addr_out;
    wire [31:0] Data_out;
    wire [2:0]  dm_ctrl;
    wire CPU_MIO;

    reg [31:0] imem [0:IMEM_SIZE-1];
    integer i;
    integer cycle_count;
    integer drain_count;
    reg seen_pc_0c;
    reg seen_pc_18;
    reg seen_pc_1c;
    reg seen_pc_20;
    reg stop_seen;

    function [31:0] enc_i;
        input [11:0] imm12;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] enc_b;
        input integer offset;
        input [4:0] rs1;
        input [4:0] rs2;
        input [2:0] funct3;
        reg [12:0] imm13;
        begin
            imm13 = offset[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, funct3, imm13[4:1], imm13[11], OP_BRANCH};
        end
    endfunction

    function [31:0] enc_j;
        input integer offset;
        input [4:0] rd;
        reg [20:0] imm21;
        begin
            imm21 = offset[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, OP_JAL};
        end
    endfunction

    assign inst_in = imem[PC_out[11:2]];

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            cycle_count <= cycle_count + 1;

            if (PC_out == 32'h0000_000C) seen_pc_0c <= 1'b1;
            if (PC_out == 32'h0000_0018) seen_pc_18 <= 1'b1;
            if (PC_out == 32'h0000_001C) seen_pc_1c <= 1'b1;
            if (PC_out == 32'h0000_0020) seen_pc_20 <= 1'b1;

            $display("PC_TRACE cycle=%0d pc=%08h inst=%08h", cycle_count, PC_out, inst_in);

            if (!stop_seen && (PC_out == 32'h0000_0020)) begin
                stop_seen <= 1'b1;
                drain_count <= 8;
            end else if (stop_seen && (drain_count > 0)) begin
                drain_count <= drain_count - 1;
                if (drain_count == 1) begin
                    if (!seen_pc_0c) $fatal(1, "jal target was never observed");
                    if (!seen_pc_18) $fatal(1, "branch target was never observed");
                    if (!seen_pc_1c) $fatal(1, "jalr target was never observed");
                    if (!seen_pc_20) $fatal(1, "stop PC was never observed");
                    if (uut.U_RF.rf[5]  !== 32'h0000_0008) $fatal(1, "jal link x5 wrong: %h", uut.U_RF.rf[5]);
                    if (uut.U_RF.rf[7]  !== 32'h0000_001C) $fatal(1, "jalr link x7 wrong: %h", uut.U_RF.rf[7]);
                    if (uut.U_RF.rf[8]  !== 32'h0000_0008) $fatal(1, "post-jalr body x8 wrong: %h", uut.U_RF.rf[8]);
                    if (uut.U_RF.rf[2]  !== 32'h0000_0000) $fatal(1, "skipped addi x2 executed unexpectedly: %h", uut.U_RF.rf[2]);
                    if (uut.U_RF.rf[4]  !== 32'h0000_0000) $fatal(1, "skipped addi x4 executed unexpectedly: %h", uut.U_RF.rf[4]);
                    $display("TB_PASS: PC + jump semantics matched byte-addressed PC / word-addressed ROM.");
                    $finish;
                end
            end

            if (cycle_count > 80)
                $fatal(1, "TB_TIMEOUT: control-flow test did not finish.");
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'b0;
        cycle_count = 0;
        drain_count = 0;
        seen_pc_0c = 1'b0;
        seen_pc_18 = 1'b0;
        seen_pc_1c = 1'b0;
        seen_pc_20 = 1'b0;
        stop_seen = 1'b0;

        for (i = 0; i < IMEM_SIZE; i = i + 1)
            imem[i] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OP_IMM);

        imem[0] = enc_i(12'd28, 5'd0, 3'b000, 5'd6, OP_IMM);   // addi x6, x0, 28
        imem[1] = enc_j(8, 5'd5);                              // jal x5, +8 -> 0x000C
        imem[2] = enc_i(12'd2, 5'd0, 3'b000, 5'd2, OP_IMM);    // skipped
        imem[3] = enc_i(12'd3, 5'd0, 3'b000, 5'd3, OP_IMM);    // addi x3, x0, 3
        imem[4] = enc_b(8, 5'd3, 5'd3, 3'b000);                // beq x3, x3, +8 -> 0x0018
        imem[5] = enc_i(12'd4, 5'd0, 3'b000, 5'd4, OP_IMM);    // skipped
        imem[6] = enc_i(12'd0, 5'd6, 3'b000, 5'd7, OP_JALR);   // jalr x7, 0(x6) -> 0x001C
        imem[7] = enc_i(12'd8, 5'd0, 3'b000, 5'd8, OP_IMM);    // addi x8, x0, 8
        imem[8] = enc_j(0, 5'd0);                              // stop

        #20;
        reset = 1'b0;
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
        .ext_irq_valid(1'b0),
        .ext_irq_cause(8'h00)
    );

endmodule
