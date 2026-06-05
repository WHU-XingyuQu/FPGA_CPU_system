`timescale 1ns / 1ps

module tb_scpu_testac_vivado;
    localparam integer IMEM_SIZE  = 1024;
    localparam integer DMEM_WORDS = 1024;
    localparam integer DMEM_BYTES = DMEM_WORDS * 4;
    localparam integer MAX_CYCLES = 300000;

    localparam [31:0] MMIO_E000   = 32'hE000_0000;
    localparam [31:0] MMIO_F000   = 32'hF000_0000;
    localparam [31:0] FAIL_PC     = 32'h0000_0218;
    localparam [31:0] FAIL_WRITE_PC = 32'h0000_0214;
    localparam [31:0] PASS_WRITE_PC = 32'h0000_01F0;
    localparam [31:0] STAGE_1     = 32'h0011_1100;
    localparam [31:0] STAGE_2     = 32'h0022_2200;
    localparam [31:0] STAGE_3     = 32'h0033_3300;
    localparam [31:0] STAGE_4     = 32'h0044_4400;
    localparam [31:0] STAGE_5     = 32'h0055_5500;
    localparam [31:0] STAGE_6     = 32'h0066_6600;
    localparam [31:0] STAGE_PASS  = 32'hFFFF_FFFF;
    localparam [31:0] STAGE_1_PC  = 32'h0000_025C;
    localparam [31:0] STAGE_2_PC  = 32'h0000_02F0;
    localparam [31:0] STAGE_3_PC  = 32'h0000_0434;
    localparam [31:0] STAGE_4_PC  = 32'h0000_04C8;
    localparam [31:0] STAGE_5_PC  = 32'h0000_066C;
    localparam [31:0] STAGE_6_PC  = 32'h0000_0A38;
    localparam [31:0] END_PC_68   = 32'h0000_0068;
    localparam [31:0] END_PC_6C   = 32'h0000_006C;
    localparam [31:0] END_PC_70   = 32'h0000_0070;
    localparam [31:0] END_PC_74   = 32'h0000_0074;
    localparam [31:0] END_INST_68 = 32'hFEC4_2783;
    localparam [31:0] END_INST_6C = 32'hFFF7_8713;
    localparam [31:0] END_INST_70 = 32'hFEE4_2623;
    localparam [31:0] END_INST_74 = 32'hFE07_9AE3;
    localparam integer ENDPOINT_WINDOW = 256;

    reg         clk;
    reg         reset;
    reg         MIO_ready;
    reg         INT;
    reg  [31:0] Data_in;

    wire [31:0] inst_in;
    wire        mem_w;
    wire [31:0] PC_out;
    wire [31:0] Addr_out;
    wire [31:0] Data_out;
    wire [2:0]  dm_ctrl;
    wire        CPU_MIO;

    reg [31:0] imem [0:IMEM_SIZE-1];
    reg [31:0] dmem_words [0:DMEM_WORDS-1];
    reg [7:0]  dmem [0:DMEM_BYTES-1];

    reg [31:0] pending_read_data;
    reg [31:0] gpioe_reg;
    reg [31:0] last_stage;

    integer cycle_count;
    integer fail_pc_hits;
    integer i;
    integer file_handle;

    reg saw_stage_1;
    reg saw_stage_2;
    reg saw_stage_3;
    reg saw_stage_4;
    reg saw_stage_5;
    reg saw_stage_6;
    reg saw_final_stage;
    reg saw_end_68;
    reg saw_end_6c;
    reg saw_end_70;
    reg saw_end_74;
    integer post_final_cycles;

    wire [31:0] x1;
    wire [31:0] x2;
    wire [31:0] x9;
    wire [31:0] x10;
    wire [31:0] x11;
    wire [31:0] x12;
    wire [31:0] x13;
    wire [31:0] x14;
    wire [31:0] x15;

    wire        mmio_e000_write;
    wire        in_fail_loop;

    assign x1  = uut.U_RF.rf[1];
    assign x2  = uut.U_RF.rf[2];
    assign x9  = uut.U_RF.rf[9];
    assign x10 = uut.U_RF.rf[10];
    assign x11 = uut.U_RF.rf[11];
    assign x12 = uut.U_RF.rf[12];
    assign x13 = uut.U_RF.rf[13];
    assign x14 = uut.U_RF.rf[14];
    assign x15 = uut.U_RF.rf[15];

    assign mmio_e000_write = mem_w && (Addr_out == MMIO_E000);
    assign in_fail_loop    = (PC_out == FAIL_PC);

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

    function [31:0] stage_store_pc;
        input [31:0] stage_value;
        begin
            case (stage_value)
                STAGE_1:    stage_store_pc = STAGE_1_PC;
                STAGE_2:    stage_store_pc = STAGE_2_PC;
                STAGE_3:    stage_store_pc = STAGE_3_PC;
                STAGE_4:    stage_store_pc = STAGE_4_PC;
                STAGE_5:    stage_store_pc = STAGE_5_PC;
                STAGE_6:    stage_store_pc = STAGE_6_PC;
                STAGE_PASS: stage_store_pc = PASS_WRITE_PC;
                default:    stage_store_pc = 32'hFFFF_FFFF;
            endcase
        end
    endfunction

    task automatic load_mem_file;
        input integer which_file;
        begin
            if (which_file == 0) begin
                file_handle = $fopen("testac.mem", "r");
                if (file_handle != 0) begin
                    $fclose(file_handle);
                    $readmemh("testac.mem", imem);
                    $display("TB_INFO: loaded instruction memory from testac.mem");
                end else begin
                    $readmemh("../testac.mem", imem);
                    $display("TB_INFO: loaded instruction memory from ../testac.mem");
                end
            end else begin
                file_handle = $fopen("D_mem.mem", "r");
                if (file_handle != 0) begin
                    $fclose(file_handle);
                    $readmemh("D_mem.mem", dmem_words);
                    $display("TB_INFO: loaded data memory from D_mem.mem");
                end else begin
                    $readmemh("../D_mem.mem", dmem_words);
                    $display("TB_INFO: loaded data memory from ../D_mem.mem");
                end
            end
        end
    endtask

    task automatic update_stage_flags;
        input [31:0] stage_value;
        begin
            case (stage_value)
                STAGE_1: saw_stage_1 <= 1'b1;
                STAGE_2: saw_stage_2 <= 1'b1;
                STAGE_3: saw_stage_3 <= 1'b1;
                STAGE_4: saw_stage_4 <= 1'b1;
                STAGE_5: saw_stage_5 <= 1'b1;
                STAGE_6: saw_stage_6 <= 1'b1;
                STAGE_PASS: saw_final_stage <= 1'b1;
                default: begin
                end
            endcase
        end
    endtask

    task automatic write_bus_data;
        input [31:0] addr;
        input [2:0]  ctrl;
        input [31:0] data;
        reg [11:0] a;
        reg [31:0] expected_stage_pc;
        begin
            if (addr == MMIO_E000) begin
                expected_stage_pc = stage_store_pc(data);
                gpioe_reg  <= data;
                last_stage <= data;
                update_stage_flags(data);
                $display("TB_STAGE: cycle=%0d fetch_pc=%08h stage=%08h store_pc=%08h",
                         cycle_count, PC_out, data, expected_stage_pc);
            end else if ((addr & 32'hFFFF_0000) == MMIO_F000) begin
                // testac self-check does not require external inputs here.
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

    // Board-like data path:
    // 1. byte-addressed writes
    // 2. one-cycle read latency
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
            fail_pc_hits <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (in_fail_loop)
                fail_pc_hits <= fail_pc_hits + 1;

            if ((cycle_count < 150) || mmio_e000_write || in_fail_loop) begin
                $display("TB_TRACE: cycle=%0d pc=%08h inst=%08h mem_w=%b addr=%08h dout=%08h din=%08h dm_ctrl=%03b x1=%08h x2=%08h x9=%08h x10=%08h x11=%08h x14=%08h x15=%08h",
                         cycle_count, PC_out, inst_in, mem_w, Addr_out, Data_out, Data_in, dm_ctrl,
                         x1, x2, x9, x10, x11, x14, x15);
            end

            if (saw_final_stage) begin
                post_final_cycles <= post_final_cycles + 1;

                if ((PC_out == END_PC_68) && (inst_in == END_INST_68))
                    saw_end_68 <= 1'b1;
                if ((PC_out == END_PC_6C) && (inst_in == END_INST_6C))
                    saw_end_6c <= 1'b1;
                if ((PC_out == END_PC_70) && (inst_in == END_INST_70))
                    saw_end_70 <= 1'b1;
                if ((PC_out == END_PC_74) && (inst_in == END_INST_74))
                    saw_end_74 <= 1'b1;
            end

            if (fail_pc_hits >= 8) begin
                $fatal(1,
                       "TESTAC_FAIL: entered failure loop at 0x0218. last_stage=%08h x10=%08h x11=%08h x12=%08h x13=%08h x14=%08h x15=%08h",
                       last_stage, x10, x11, x12, x13, x14, x15);
            end

            if (saw_final_stage) begin
                if (!(saw_stage_1 && saw_stage_2 && saw_stage_3 &&
                      saw_stage_4 && saw_stage_5 && saw_stage_6)) begin
                    $fatal(1,
                           "TESTAC_FAIL: final stage reached but some intermediate stage markers were missing. last_stage=%08h",
                           last_stage);
                end

                if (saw_end_68 && saw_end_6c && saw_end_70 && saw_end_74) begin
                    $display("TESTAC_PASS: all stage markers observed. last_stage=%08h x10=%08h pc=%08h",
                             last_stage, x10, PC_out);
                    $display("TESTAC_ENDPOINT: observed delay-loop PCs/instructions at 0x68/0x6c/0x70/0x74");
                    $display("TESTAC_SUMMARY: stage1=%0d stage2=%0d stage3=%0d stage4=%0d stage5=%0d stage6=%0d final=%0d end68=%0d end6c=%0d end70=%0d end74=%0d",
                             saw_stage_1, saw_stage_2, saw_stage_3, saw_stage_4,
                             saw_stage_5, saw_stage_6, saw_final_stage,
                             saw_end_68, saw_end_6c, saw_end_70, saw_end_74);
                    $finish;
                end

                if (post_final_cycles >= ENDPOINT_WINDOW) begin
                    $fatal(1,
                           "TESTAC_FAIL: final stage reached but endpoint delay loop was not fully observed. end68=%0d end6c=%0d end70=%0d end74=%0d last_pc=%08h inst=%08h",
                           saw_end_68, saw_end_6c, saw_end_70, saw_end_74, PC_out, inst_in);
                end
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
        last_stage = 32'h0000_0000;
        cycle_count = 0;
        fail_pc_hits = 0;
        saw_stage_1 = 1'b0;
        saw_stage_2 = 1'b0;
        saw_stage_3 = 1'b0;
        saw_stage_4 = 1'b0;
        saw_stage_5 = 1'b0;
        saw_stage_6 = 1'b0;
        saw_final_stage = 1'b0;
        saw_end_68 = 1'b0;
        saw_end_6c = 1'b0;
        saw_end_70 = 1'b0;
        saw_end_74 = 1'b0;
        post_final_cycles = 0;

        for (i = 0; i < IMEM_SIZE; i = i + 1)
            imem[i] = 32'h0000_0013;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            dmem_words[i] = 32'h0000_0000;
        for (i = 0; i < DMEM_BYTES; i = i + 1)
            dmem[i] = 8'h00;

        load_mem_file(0);
        load_mem_file(1);
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
