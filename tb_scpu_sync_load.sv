`timescale 1ns / 1ps

module tb_scpu_sync_load;
    localparam [6:0] OP_LOAD  = 7'b0000011;
    localparam [6:0] OP_STORE = 7'b0100011;
    localparam [6:0] OP_IMM   = 7'b0010011;
    localparam [6:0] OP_JAL   = 7'b1101111;

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

    reg [31:0] imem [0:31];
    reg [31:0] mem [0:31];
    reg [31:0] pending_read_data;
    integer i;
    integer cycles;
    integer drain_count;
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

    // Model a synchronous read path: CPU sees the previous cycle's addressed word.
    always @(posedge clk) begin
        if (reset) begin
            pending_read_data <= 32'h0;
            Data_in <= 32'h0;
        end else begin
            Data_in <= pending_read_data;
            pending_read_data <= mem[Addr_out[6:2]];
            if (mem_w)
                mem[Addr_out[6:2]] <= Data_out;
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles <= cycles + 1;
            $display("SYNC_LOAD pc=%08h inst=%08h addr=%08h din=%08h dout=%08h x1=%08h x2=%08h x3=%08h",
                     PC_out, inst_in, Addr_out, Data_in, Data_out,
                     uut.U_RF.rf[1], uut.U_RF.rf[2], uut.U_RF.rf[3]);

            if (!stop_seen && (PC_out == 32'd12)) begin
                stop_seen <= 1'b1;
                drain_count <= 8;
            end else if (stop_seen && (drain_count > 0)) begin
                drain_count <= drain_count - 1;
                if (drain_count == 1) begin
                    #1;
                    if (uut.U_RF.rf[2] !== 32'h11223344)
                        $fatal(1, "TB_FAIL: synchronous load still broken, x2=%h", uut.U_RF.rf[2]);
                    if (mem[1] !== 32'h11223344)
                        $fatal(1, "TB_FAIL: stored word wrong, mem[1]=%h", mem[1]);
                    $display("TB_PASS: synchronous memory load completed correctly, x2=%h", uut.U_RF.rf[2]);
                    $finish;
                end
            end

            if (cycles > 40)
                $fatal(1, "TB_TIMEOUT: pc=%h x1=%h x2=%h", PC_out, uut.U_RF.rf[1], uut.U_RF.rf[2]);
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'h0;
        pending_read_data = 32'h0;
        cycles = 0;
        drain_count = 0;
        stop_seen = 1'b0;

        for (i = 0; i < 32; i = i + 1) begin
            imem[i] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OP_IMM);
            mem[i] = 32'h0;
        end

        mem[0] = 32'h1122_3344;

        imem[0] = enc_i(12'd0, 5'd0, 3'b010, 5'd1, OP_LOAD);   // lw x1, 0(x0)
        imem[1] = enc_i(12'd0, 5'd0, 3'b010, 5'd2, OP_LOAD);   // lw x2, 0(x0)
        imem[2] = enc_s(12'd4, 5'd2, 5'd0, 3'b010, OP_STORE);  // sw x2, 4(x0)
        imem[3] = enc_j(0, 5'd0);                              // stop

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
