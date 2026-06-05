`timescale 1ns / 1ps

module tb_scpu_core;
    localparam integer IMEM_SIZE = 64;
    localparam integer DMEM_SIZE = 256;
    localparam [31:0] STOP_PC    = 32'd220;

    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_IMM    = 7'b0010011;
    localparam [6:0] OP_REG    = 7'b0110011;

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
    reg [7:0]  dmem [0:DMEM_SIZE-1];

    integer cycle_count;
    integer fail_count;
    integer i;
    integer drain_count;
    reg     finished;
    reg     stop_seen;

    wire [7:0] daddr = Addr_out[7:0];

    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

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

    function [31:0] enc_s;
        input [11:0] imm12;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            enc_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode};
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

    function [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_u = {imm20, rd, opcode};
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

    task expect_reg;
        input [4:0] idx;
        input [31:0] expected;
        begin
            if (uut.U_RF.rf[idx] !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL REG x%0d expected=%h got=%h", idx, expected, uut.U_RF.rf[idx]);
            end
        end
    endtask

    task expect_mem8;
        input [7:0] addr;
        input [7:0] expected;
        begin
            if (dmem[addr] !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL MEM[%0d] expected=%h got=%h", addr, expected, dmem[addr]);
            end
        end
    endtask

    task load_program;
        begin
            for (i = 0; i < IMEM_SIZE; i = i + 1)
                imem[i] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OP_IMM);

            imem[0]  = enc_i(12'd5,    5'd0, 3'b000, 5'd1,  OP_IMM);    // addi x1, x0, 5
            imem[1]  = enc_i(12'd10,   5'd0, 3'b000, 5'd2,  OP_IMM);    // addi x2, x0, 10
            imem[2]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3,  OP_REG); // add
            imem[3]  = enc_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4,  OP_REG); // sub
            imem[4]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd5,  OP_REG); // slt
            imem[5]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd6,  OP_REG); // sltu
            imem[6]  = enc_r(7'b0000000, 5'd2, 5'd3, 3'b111, 5'd7,  OP_REG); // and
            imem[7]  = enc_r(7'b0000000, 5'd4, 5'd1, 3'b110, 5'd8,  OP_REG); // or
            imem[8]  = enc_r(7'b0000000, 5'd2, 5'd3, 3'b100, 5'd9,  OP_REG); // xor
            imem[9]  = enc_r(7'b0000000, 5'd1, 5'd1, 3'b001, 5'd10, OP_REG); // sll
            imem[10] = enc_r(7'b0000000, 5'd1, 5'd10,3'b101, 5'd11, OP_REG); // srl
            imem[11] = enc_i(12'hFF0,  5'd0, 3'b000, 5'd12, OP_IMM);  // addi x12, -16
            imem[12] = enc_i(12'd2,    5'd0, 3'b000, 5'd13, OP_IMM);  // addi x13, 2
            imem[13] = enc_r(7'b0100000, 5'd13,5'd12,3'b101, 5'd14, OP_REG); // sra
            imem[14] = enc_s(12'd0,    5'd3, 5'd0, 3'b010, OP_STORE); // sw
            imem[15] = enc_i(12'd0,    5'd0, 3'b010, 5'd15, OP_LOAD); // lw
            imem[16] = enc_s(12'd4,    5'd1, 5'd0, 3'b000, OP_STORE); // sb
            imem[17] = enc_i(12'd4,    5'd0, 3'b000, 5'd16, OP_LOAD); // lb
            imem[18] = enc_i(12'hFFF,  5'd0, 3'b000, 5'd17, OP_IMM);  // addi x17, -1
            imem[19] = enc_s(12'd5,    5'd17,5'd0, 3'b000, OP_STORE); // sb
            imem[20] = enc_i(12'd5,    5'd0, 3'b100, 5'd18, OP_LOAD); // lbu
            imem[21] = enc_i(12'd5,    5'd0, 3'b000, 5'd19, OP_LOAD); // lb
            imem[22] = enc_s(12'd6,    5'd2, 5'd0, 3'b001, OP_STORE); // sh
            imem[23] = enc_i(12'd6,    5'd0, 3'b101, 5'd20, OP_LOAD); // lhu
            imem[24] = enc_i(12'd6,    5'd0, 3'b001, 5'd21, OP_LOAD); // lh
            imem[25] = enc_i(12'd7,    5'd3, 3'b111, 5'd22, OP_IMM);  // andi
            imem[26] = enc_i(12'd8,    5'd22,3'b110, 5'd23, OP_IMM);  // ori
            imem[27] = enc_i(12'd15,   5'd23,3'b100, 5'd24, OP_IMM);  // xori
            imem[28] = enc_i(12'd6,    5'd1, 3'b010, 5'd25, OP_IMM);  // slti
            imem[29] = enc_i(12'd1,    5'd17,3'b011, 5'd26, OP_IMM);  // sltiu
            imem[30] = enc_i(12'd2,    5'd2, 3'b001, 5'd27, OP_IMM);  // slli
            imem[31] = enc_i(12'd1,    5'd27,3'b101, 5'd28, OP_IMM);  // srli
            imem[32] = enc_i(12'h401,  5'd17,3'b101, 5'd29, OP_IMM);  // srai
            imem[33] = enc_b(8,        5'd15,5'd3,  3'b000);          // beq
            imem[34] = enc_i(12'd111,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[35] = enc_b(8,        5'd15,5'd1,  3'b001);          // bne
            imem[36] = enc_i(12'd222,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[37] = enc_b(8,        5'd17,5'd0,  3'b100);          // blt
            imem[38] = enc_i(12'd333,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[39] = enc_b(8,        5'd1, 5'd1,  3'b101);          // bge
            imem[40] = enc_i(12'd444,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[41] = enc_b(8,        5'd1, 5'd2,  3'b110);          // bltu
            imem[42] = enc_i(12'd555,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[43] = enc_b(8,        5'd18,5'd16, 3'b111);          // bgeu
            imem[44] = enc_i(12'd666,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[45] = enc_j(8,        5'd29);                        // jal
            imem[46] = enc_i(12'd777,  5'd0, 3'b000, 5'd30, OP_IMM);  // skip
            imem[47] = enc_i(12'd212,  5'd0, 3'b000, 5'd30, OP_IMM);  // jalr target
            imem[48] = enc_i(12'd0,    5'd30,3'b000, 5'd28, OP_JALR); // jalr
            imem[49] = enc_i(12'd99,   5'd0, 3'b000, 5'd1,  OP_IMM);  // skip
            imem[50] = enc_i(12'd99,   5'd0, 3'b000, 5'd2,  OP_IMM);  // skip
            imem[51] = enc_i(12'd99,   5'd0, 3'b000, 5'd3,  OP_IMM);  // skip
            imem[52] = enc_i(12'd99,   5'd0, 3'b000, 5'd4,  OP_IMM);  // skip
            imem[53] = enc_u(20'h12345, 5'd30, OP_LUI);               // lui
            imem[54] = enc_u(20'h00001, 5'd31, OP_AUIPC);             // auipc
            imem[55] = enc_j(0,        5'd0);                         // stop
        end
    endtask

    task run_checks;
        begin
            expect_reg(5'd0,  32'h0000_0000);
            expect_reg(5'd1,  32'h0000_0005);
            expect_reg(5'd2,  32'h0000_000A);
            expect_reg(5'd3,  32'h0000_000F);
            expect_reg(5'd4,  32'h0000_0005);
            expect_reg(5'd5,  32'h0000_0001);
            expect_reg(5'd6,  32'h0000_0001);
            expect_reg(5'd7,  32'h0000_000A);
            expect_reg(5'd8,  32'h0000_0005);
            expect_reg(5'd9,  32'h0000_0005);
            expect_reg(5'd10, 32'h0000_00A0);
            expect_reg(5'd11, 32'h0000_0005);
            expect_reg(5'd12, 32'hFFFF_FFF0);
            expect_reg(5'd13, 32'h0000_0002);
            expect_reg(5'd14, 32'hFFFF_FFFC);
            expect_reg(5'd15, 32'h0000_000F);
            expect_reg(5'd16, 32'h0000_0005);
            expect_reg(5'd17, 32'hFFFF_FFFF);
            expect_reg(5'd18, 32'h0000_00FF);
            expect_reg(5'd19, 32'hFFFF_FFFF);
            expect_reg(5'd20, 32'h0000_000A);
            expect_reg(5'd21, 32'h0000_000A);
            expect_reg(5'd22, 32'h0000_0007);
            expect_reg(5'd23, 32'h0000_000F);
            expect_reg(5'd24, 32'h0000_0000);
            expect_reg(5'd25, 32'h0000_0001);
            expect_reg(5'd26, 32'h0000_0000);
            expect_reg(5'd27, 32'h0000_0028);
            expect_reg(5'd28, 32'h0000_00C4);
            expect_reg(5'd29, 32'h0000_00B8);
            expect_reg(5'd30, 32'h1234_5000);
            expect_reg(5'd31, 32'h0000_10D8);

            expect_mem8(8'd0, 8'h0F);
            expect_mem8(8'd1, 8'h00);
            expect_mem8(8'd2, 8'h00);
            expect_mem8(8'd3, 8'h00);
            expect_mem8(8'd4, 8'h05);
            expect_mem8(8'd5, 8'hFF);
            expect_mem8(8'd6, 8'h0A);
            expect_mem8(8'd7, 8'h00);

            if (CPU_MIO !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("FAIL CPU_MIO expected=1 got=%b", CPU_MIO);
            end
        end
    endtask

    assign inst_in = imem[PC_out[11:2]];

    always @(*) begin
        case (dm_ctrl)
            3'b011: Data_in = {{24{dmem[daddr][7]}}, dmem[daddr]};
            3'b100: Data_in = {24'd0, dmem[daddr]};
            3'b001: Data_in = {{16{dmem[daddr + 8'd1][7]}}, dmem[daddr + 8'd1], dmem[daddr]};
            3'b010: Data_in = {16'd0, dmem[daddr + 8'd1], dmem[daddr]};
            default: Data_in = {dmem[daddr + 8'd3], dmem[daddr + 8'd2], dmem[daddr + 8'd1], dmem[daddr]};
        endcase
    end

    always @(posedge clk) begin
        if (!reset && mem_w) begin
            case (dm_ctrl)
                3'b011,
                3'b100: dmem[daddr] <= Data_out[7:0];
                3'b001,
                3'b010: begin
                    dmem[daddr] <= Data_out[7:0];
                    dmem[daddr + 8'd1] <= Data_out[15:8];
                end
                default: begin
                    dmem[daddr] <= Data_out[7:0];
                    dmem[daddr + 8'd1] <= Data_out[15:8];
                    dmem[daddr + 8'd2] <= Data_out[23:16];
                    dmem[daddr + 8'd3] <= Data_out[31:24];
                end
            endcase
        end
    end

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    always @(posedge clk) begin
        if (!reset && !finished) begin
            if (!stop_seen && (PC_out == STOP_PC)) begin
                stop_seen <= 1'b1;
                drain_count <= 8;
            end else if (stop_seen && (drain_count > 0)) begin
                drain_count <= drain_count - 1;
                if (drain_count == 1) begin
                    finished = 1'b1;
                    #1;
                    run_checks();
                    if (fail_count == 0) begin
                        $display("TB_PASS: SCPU regression passed at cycle %0d.", cycle_count);
                        $finish;
                    end else begin
                        $fatal(1, "TB_FAIL: %0d checks failed.", fail_count);
                    end
                end
            end
        end

        if (!reset && cycle_count > 400)
            $fatal(1, "TB_TIMEOUT: PC did not reach stop marker.");
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'b0;
        cycle_count = 0;
        fail_count = 0;
        drain_count = 0;
        finished = 1'b0;
        stop_seen = 1'b0;

        for (i = 0; i < DMEM_SIZE; i = i + 1)
            dmem[i] = 8'h00;

        load_program();

        if ($test$plusargs("dump")) begin
            $dumpfile("tb_scpu_core.vcd");
            $dumpvars(0, tb_scpu_core);
        end

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
