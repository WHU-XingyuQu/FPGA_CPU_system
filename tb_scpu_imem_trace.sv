`timescale 1ns / 1ps

module tb_scpu_imem_trace;
    localparam integer IMEM_SIZE = 256;
    localparam integer MAX_CYCLES = 80;

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
    integer cycle_count;
    integer idx;
    integer loaded_words;

    assign inst_in = imem[PC_out[11:2]];

    always #5 clk = ~clk;

    task load_imem_from_mem;
        begin
            for (idx = 0; idx < IMEM_SIZE; idx = idx + 1)
                imem[idx] = 32'h0000_0013;
            $readmemh("../I_mem.mem", imem);

            loaded_words = 0;
            for (idx = 0; idx < IMEM_SIZE; idx = idx + 1)
                if (imem[idx] !== 32'h0000_0013)
                    loaded_words = idx + 1;

            $display("TRACE_INFO: loaded %0d instructions from I_mem.mem", loaded_words);
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            $display("TRACE cycle=%0d pc=%08h idx=%0d inst=%08h mem_w=%0b addr=%08h data=%08h",
                     cycle_count, PC_out, PC_out[11:2], inst_in, mem_w, Addr_out, Data_out);

            if (PC_out >= 32'd128) begin
                $display("TRACE_REACHED_GT32: pc=%08h idx=%0d at cycle=%0d",
                         PC_out, PC_out[11:2], cycle_count);
                $finish;
            end

            if (cycle_count >= MAX_CYCLES) begin
                $fatal(1, "TRACE_TIMEOUT: PC never reached instruction index 32.");
            end
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'b0;
        cycle_count = 0;
        load_imem_from_mem();

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
