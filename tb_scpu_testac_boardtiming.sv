`timescale 1ns / 1ps

module tb_scpu_testac_boardtiming;
    localparam integer IMEM_SIZE  = 1024;
    localparam integer DMEM_WORDS = 1024;
    localparam integer DMEM_BYTES = DMEM_WORDS * 4;
    localparam integer MAX_CPU_CYCLES = 300000;

    localparam [31:0] MMIO_E000 = 32'hE000_0000;
    localparam [31:0] MMIO_F000 = 32'hF000_0000;
    localparam [31:0] FAIL_PC   = 32'h0000_0218;
    localparam [31:0] END_PC_68   = 32'h0000_0068;
    localparam [31:0] END_PC_6C   = 32'h0000_006C;
    localparam [31:0] END_PC_70   = 32'h0000_0070;
    localparam [31:0] END_PC_74   = 32'h0000_0074;
    localparam [31:0] END_INST_68 = 32'hFEC4_2783;
    localparam [31:0] END_INST_6C = 32'hFFF7_8713;
    localparam [31:0] END_INST_70 = 32'hFEE4_2623;
    localparam [31:0] END_INST_74 = 32'hFE07_9AE3;
    localparam integer ENDPOINT_WINDOW = 256;

    reg sys_clk;
    reg reset;
    reg MIO_ready;
    reg INT;
    reg cpu_clk;

    wire [31:0] inst_in;
    reg  [31:0] Data_in;
    wire        mem_w;
    wire [31:0] PC_out;
    wire [31:0] Addr_out;
    wire [31:0] Data_out;
    wire [2:0]  dm_ctrl;
    wire        CPU_MIO;

    reg [31:0] imem [0:IMEM_SIZE-1];
    reg [31:0] dmem_words [0:DMEM_WORDS-1];
    reg [7:0]  dmem [0:DMEM_BYTES-1];

    reg [31:0] gpioe_reg;
    reg [31:0] pending_read_data;
    reg [31:0] last_stage;

    integer cpu_cycle_count;
    integer fail_pc_hits;
    integer post_final_cycles;
    integer i;
    integer file_handle;
    reg saw_end_68;
    reg saw_end_6c;
    reg saw_end_70;
    reg saw_end_74;

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
                $display("BOARD_STAGE: cpu_cycle=%0d pc=%08h stage=%08h", cpu_cycle_count, PC_out, data);
            end else if ((addr & 32'hFFFF_0000) == MMIO_F000) begin
                // no modeled board inputs for this test
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

    task automatic load_mem_file;
        input integer which_file;
        begin
            if (which_file == 0) begin
                file_handle = $fopen("testac.mem", "r");
                if (file_handle != 0) begin
                    $fclose(file_handle);
                    $readmemh("testac.mem", imem);
                end else begin
                    $readmemh("../testac.mem", imem);
                end
            end else begin
                file_handle = $fopen("D_mem.mem", "r");
                if (file_handle != 0) begin
                    $fclose(file_handle);
                    $readmemh("D_mem.mem", dmem_words);
                end else begin
                    $readmemh("../D_mem.mem", dmem_words);
                end
            end
        end
    endtask

    assign inst_in = imem[PC_out[11:2]];

    always #5  sys_clk = ~sys_clk;
    // Keep the CPU clock running during reset so the synchronous-reset SCPU
    // can actually sample reset and initialize its pipeline registers.
    always #40 cpu_clk = ~cpu_clk;

    // System-side bus path, intentionally not clocked by cpu_clk.
    always @(posedge sys_clk) begin
        if (reset) begin
            Data_in <= 32'h0000_0000;
        end else begin
            Data_in <= pending_read_data;
        end
    end

    always @(negedge sys_clk) begin
        if (reset) begin
            pending_read_data <= 32'h0000_0000;
        end else begin
            pending_read_data <= read_bus_data(Addr_out, dm_ctrl);
            if (mem_w)
                write_bus_data(Addr_out, dm_ctrl, Data_out);
        end
    end

    always @(posedge cpu_clk) begin
        if (reset) begin
            cpu_cycle_count <= 0;
            fail_pc_hits <= 0;
        end else begin
            cpu_cycle_count <= cpu_cycle_count + 1;

            if (PC_out == FAIL_PC)
                fail_pc_hits <= fail_pc_hits + 1;

            if ((cpu_cycle_count < 150) || (PC_out == FAIL_PC) || mem_w) begin
                $display("BOARD_TRACE: cpu_cycle=%0d pc=%08h inst=%08h mem_w=%b addr=%08h dout=%08h din=%08h dm_ctrl=%03b x10=%08h x11=%08h x14=%08h x15=%08h",
                         cpu_cycle_count, PC_out, inst_in, mem_w, Addr_out, Data_out, Data_in, dm_ctrl,
                         uut.U_RF.rf[10], uut.U_RF.rf[11], uut.U_RF.rf[14], uut.U_RF.rf[15]);
            end

            if (last_stage == 32'hFFFF_FFFF) begin
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
                       "BOARD_FAIL: entered failure loop. last_stage=%08h x10=%08h x11=%08h x14=%08h x15=%08h",
                       last_stage, uut.U_RF.rf[10], uut.U_RF.rf[11], uut.U_RF.rf[14], uut.U_RF.rf[15]);
            end

            if (last_stage == 32'hFFFF_FFFF) begin
                if (saw_end_68 && saw_end_6c && saw_end_70 && saw_end_74) begin
                    $display("BOARD_PASS: final stage observed and endpoint loop verified. x10=%08h pc=%08h", uut.U_RF.rf[10], PC_out);
                    $finish;
                end

                if (post_final_cycles >= ENDPOINT_WINDOW) begin
                    $fatal(1,
                           "BOARD_FAIL: final stage reached but endpoint delay loop was not fully observed. end68=%0d end6c=%0d end70=%0d end74=%0d last_pc=%08h inst=%08h",
                           saw_end_68, saw_end_6c, saw_end_70, saw_end_74, PC_out, inst_in);
                end
            end

            if (cpu_cycle_count >= MAX_CPU_CYCLES)
                $fatal(1, "BOARD_TIMEOUT: pc=%08h last_stage=%08h", PC_out, last_stage);
        end
    end

    initial begin
        sys_clk = 1'b0;
        cpu_clk = 1'b0;
        reset = 1'b1;
        MIO_ready = 1'b1;
        INT = 1'b0;
        Data_in = 32'h0000_0000;
        pending_read_data = 32'h0000_0000;
        gpioe_reg = 32'h0000_0000;
        last_stage = 32'h0000_0000;
        cpu_cycle_count = 0;
        fail_pc_hits = 0;
        post_final_cycles = 0;
        saw_end_68 = 1'b0;
        saw_end_6c = 1'b0;
        saw_end_70 = 1'b0;
        saw_end_74 = 1'b0;

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

        #200;
        reset = 1'b0;
    end

    SCPU uut (
        .clk      (cpu_clk),
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
