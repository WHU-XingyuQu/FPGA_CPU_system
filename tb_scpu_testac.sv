`timescale 1ns / 1ps

module tb_scpu_testac;
    localparam integer IMEM_SIZE  = 1024;
    localparam integer DMEM_WORDS = 1024;
    localparam integer DMEM_BYTES = DMEM_WORDS * 4;
    localparam integer MAX_CYCLES = 300000;

    localparam [31:0] MMIO_E000 = 32'hE000_0000;
    localparam [31:0] MMIO_F000 = 32'hF000_0000;

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
    reg [31:0] dmem_words [0:DMEM_WORDS-1];
    reg [7:0]  dmem [0:DMEM_BYTES-1];

    reg [31:0] pending_read_data;
    reg [31:0] gpioe_reg;
    integer cycle_count;
    integer i;
    integer zero_pc_hits;
    integer fail_pc_hits;
    reg [31:0] last_stage;
    reg        saw_final_stage;

    function [11:0] mask_addr12;
        input [31:0] addr;
        begin
            mask_addr12 = addr[11:0];
        end
    endfunction

    function [31:0] read_bus_data;
        input [31:0] addr;
        input [2:0]  ctrl;
        reg [11:0] a;
        reg [31:0] word;
        begin
            if (addr == MMIO_E000) begin
                read_bus_data = gpioe_reg;
            end else if ((addr & 32'hFFFF_0000) == MMIO_F000) begin
                read_bus_data = 32'h0000_0000;
            end else begin
                a = mask_addr12(addr);
                word = {dmem[(a + 12'd3) & 12'hFFF], dmem[(a + 12'd2) & 12'hFFF],
                        dmem[(a + 12'd1) & 12'hFFF], dmem[a]};
                case (ctrl)
                    3'b011: read_bus_data = {{24{dmem[a][7]}}, dmem[a]};
                    3'b100: read_bus_data = {24'd0, dmem[a]};
                    3'b001: read_bus_data = {{16{dmem[(a + 12'd1) & 12'hFFF][7]}},
                                             dmem[(a + 12'd1) & 12'hFFF], dmem[a]};
                    3'b010: read_bus_data = {16'd0, dmem[(a + 12'd1) & 12'hFFF], dmem[a]};
                    default: read_bus_data = word;
                endcase
            end
        end
    endfunction

    task automatic write_bus_data;
        input [31:0] addr;
        input [2:0]  ctrl;
        input [31:0] data;
        reg [11:0] a;
        begin
            if (addr == MMIO_E000) begin
                gpioe_reg <= data;
                last_stage <= data;
                if (data == 32'hFFFF_FFFF)
                    saw_final_stage <= 1'b1;
                $display("MMIO_E000_WRITE cycle=%0d pc=%08h data=%08h", cycle_count, PC_out, data);
            end else if ((addr & 32'hFFFF_0000) == MMIO_F000) begin
                // No external inputs are modeled for this self-test.
            end else begin
                a = mask_addr12(addr);
                case (ctrl)
                    3'b011,
                    3'b100: dmem[a] <= data[7:0];
                    3'b001,
                    3'b010: begin
                        dmem[a] <= data[7:0];
                        dmem[(a + 12'd1) & 12'hFFF] <= data[15:8];
                    end
                    default: begin
                        dmem[a] <= data[7:0];
                        dmem[(a + 12'd1) & 12'hFFF] <= data[15:8];
                        dmem[(a + 12'd2) & 12'hFFF] <= data[23:16];
                        dmem[(a + 12'd3) & 12'hFFF] <= data[31:24];
                    end
                endcase
            end
        end
    endtask

    assign inst_in = imem[PC_out[11:2]];

    always #5 clk = ~clk;

    // Model the board RAM path: one-cycle read latency, byte-addressed writes.
    always @(posedge clk) begin
        if (reset) begin
            pending_read_data <= 32'h0000_0000;
            Data_in <= 32'h0000_0000;
        end else begin
            Data_in <= pending_read_data;
            pending_read_data <= read_bus_data(Addr_out, dm_ctrl);
            if (mem_w)
                write_bus_data(Addr_out, dm_ctrl, Data_out);
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
            zero_pc_hits <= 0;
            fail_pc_hits <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (PC_out == 32'h0000_0000)
                zero_pc_hits <= zero_pc_hits + 1;

            if (PC_out == 32'h0000_0218)
                fail_pc_hits <= fail_pc_hits + 1;

            if ((cycle_count < 200) || (PC_out == 32'h0000_0218) || (PC_out == 32'h0000_0204)) begin
                $display("TESTAC_TRACE cycle=%0d pc=%08h inst=%08h addr=%08h din=%08h dout=%08h dm_ctrl=%03b x10=%08h x11=%08h x12=%08h x13=%08h",
                         cycle_count, PC_out, inst_in, Addr_out, Data_in, Data_out, dm_ctrl,
                         uut.U_RF.rf[10], uut.U_RF.rf[11], uut.U_RF.rf[12], uut.U_RF.rf[13]);
            end

            if (fail_pc_hits >= 8) begin
                $fatal(1,
                       "TESTAC_FAIL: entered failure loop at 0x0218. last_stage=%08h x10=%08h x11=%08h x12=%08h x13=%08h x14=%08h x15=%08h",
                       last_stage, uut.U_RF.rf[10], uut.U_RF.rf[11], uut.U_RF.rf[12],
                       uut.U_RF.rf[13], uut.U_RF.rf[14], uut.U_RF.rf[15]);
            end

            if (saw_final_stage) begin
                $display("TESTAC_PASS: reached final stage marker. last_stage=%08h x10=%08h pc=%08h",
                         last_stage, uut.U_RF.rf[10], PC_out);
                $finish;
            end

            if (cycle_count >= MAX_CYCLES)
                $fatal(1, "TESTAC_TIMEOUT: pc=%08h last_stage=%08h", PC_out, last_stage);
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'h0000_0000;
        pending_read_data = 32'h0000_0000;
        gpioe_reg = 32'h0000_0000;
        cycle_count = 0;
        zero_pc_hits = 0;
        fail_pc_hits = 0;
        last_stage = 32'h0000_0000;
        saw_final_stage = 1'b0;

        for (i = 0; i < IMEM_SIZE; i = i + 1)
            imem[i] = 32'h0000_0013;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            dmem_words[i] = 32'h0000_0000;
        for (i = 0; i < DMEM_BYTES; i = i + 1)
            dmem[i] = 8'h00;

        $readmemh("testac.mem", imem);
        $readmemh("D_mem.mem", dmem_words);
        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            dmem[i * 4 + 0] = dmem_words[i][7:0];
            dmem[i * 4 + 1] = dmem_words[i][15:8];
            dmem[i * 4 + 2] = dmem_words[i][23:16];
            dmem[i * 4 + 3] = dmem_words[i][31:24];
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
