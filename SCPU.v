`timescale 1ns / 1ps

module SCPU(
    input         clk,
    input         reset,
    input         MIO_ready,
    input  [31:0] inst_in,
    input  [31:0] Data_in,
    output        mem_w,
    output [31:0] PC_out,
    output [31:0] Addr_out,
    output [31:0] Data_out,
    output [2:0]  dm_ctrl,
    output        CPU_MIO,
    input         INT,
    input         ext_irq_valid,
    input  [7:0]  ext_irq_cause,
    output        ext_irq_ack,
    output [7:0]  ext_irq_ack_cause,
    output [31:0] int_debug
);
    localparam [31:0] NOP = 32'h0000_0013;
    localparam [31:0] ECALL_INST = 32'h0000_0073;
    localparam [31:0] ERET_INST  = 32'h1020_0073;
    localparam [31:0] ERETN_INST = 32'h3020_0073;
    localparam [31:0] TRAP_VECTOR = 32'h1c09_0000;

    localparam [6:0]  OP_LOAD   = 7'b0000011;
    localparam [6:0]  OP_IMM    = 7'b0010011;
    localparam [6:0]  OP_AUIPC  = 7'b0010111;
    localparam [6:0]  OP_STORE  = 7'b0100011;
    localparam [6:0]  OP_REG    = 7'b0110011;
    localparam [6:0]  OP_LUI    = 7'b0110111;
    localparam [6:0]  OP_BRANCH = 7'b1100011;
    localparam [6:0]  OP_JALR   = 7'b1100111;
    localparam [6:0]  OP_JAL    = 7'b1101111;
    localparam [6:0]  OP_SYSTEM = 7'b1110011;

    localparam [7:0]  CAUSE_NONE    = 8'h00;
    localparam [7:0]  CAUSE_TIMER   = 8'h01;
    localparam [7:0]  CAUSE_ILLEGAL = 8'h02;
    localparam [7:0]  CAUSE_SYSCALL = 8'h03;
    localparam [7:0]  CAUSE_BUTTON  = 8'h04;
    localparam [7:0]  CAUSE_SWITCH  = 8'h05;

    localparam [1:0]  FWD_NONE = 2'b00;
    localparam [1:0]  FWD_WB   = 2'b10;

    wire rstn;
    wire [15:0] sw_i;

    reg [31:0] pc_reg;

    reg [31:0] if2_pc;
    reg [31:0] if2_inst;
    reg        if2_valid;

    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;

    reg [31:0] id2_pc;
    reg [31:0] id2_rs1_data;
    reg [31:0] id2_rs2_data;
    reg [31:0] id2_imm;
    reg [4:0]  id2_rs1;
    reg [4:0]  id2_rs2;
    reg [4:0]  id2_rd;
    reg [2:0]  id2_funct3;
    reg [4:0]  id2_alu_op;
    reg [2:0]  id2_dm_ctrl;
    reg [1:0]  id2_wd_sel;
    reg        id2_reg_write;
    reg        id2_mem_write;
    reg        id2_mem_read;
    reg        id2_alu_src;
    reg        id2_branch;
    reg        id2_jal;
    reg        id2_jalr;
    reg        id2_is_lui;
    reg        id2_is_auipc;
    reg [7:0]  id2_trap_cause;
    reg        id2_is_eret;
    reg        id2_is_eretn;
    reg        id2_valid;

    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [4:0]  id_ex_alu_op;
    reg [2:0]  id_ex_dm_ctrl;
    reg [1:0]  id_ex_wd_sel;
    reg        id_ex_reg_write;
    reg        id_ex_mem_write;
    reg        id_ex_mem_read;
    reg        id_ex_alu_src;
    reg        id_ex_branch;
    reg        id_ex_jal;
    reg        id_ex_jalr;
    reg        id_ex_is_lui;
    reg        id_ex_is_auipc;
    reg [7:0]  id_ex_trap_cause;
    reg        id_ex_is_eret;
    reg        id_ex_is_eretn;
    reg [1:0]  id_ex_rs1_fwd_sel;
    reg [1:0]  id_ex_rs2_fwd_sel;
    reg        id_ex_valid;

    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_rs2_data;
    reg [31:0] ex_mem_pc_plus4;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_dm_ctrl;
    reg [1:0]  ex_mem_wd_sel;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_write;
    reg        ex_mem_mem_read;
    reg        ex_mem_valid;

    reg [31:0] mem_wb_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg        mem_wb_valid;

    reg mem_wait_pending;
    reg mem_wait_wb;
    reg mem_wait_data_ready;
    reg reset_pending;
    reg int_prev;
    reg timer_irq_pending;
    reg ext_irq_pending;
    reg [7:0] ext_irq_cause_pending;
    reg [31:0] sepc;
    reg [7:0]  scause;
    reg [7:0]  status;
    reg [7:0]  intmask;
    reg [7:0]  trap_count;

    wire [6:0] id_op;
    wire [6:0] id_funct7;
    wire [2:0] id_funct3;
    wire [4:0] id_rs1;
    wire [4:0] id_rs2;
    wire [4:0] id_rd;

    wire [11:0] id_iimm;
    wire [11:0] id_simm;
    wire [4:0]  id_iimm_shamt;
    wire [11:0] id_bimm;
    wire [19:0] id_uimm;
    wire [19:0] id_jimm;

    wire       dec_reg_write;
    wire       dec_mem_write;
    wire [5:0] dec_ext_op;
    wire [4:0] dec_alu_op;
    wire       dec_alu_src;
    wire [2:0] dec_dm_ctrl;
    wire [1:0] dec_wd_sel;
    wire       dec_branch;
    wire       dec_jal;
    wire       dec_jalr;
    wire [31:0] dec_imm;
    wire id_rtype_valid;
    wire id_itype_alu_valid;
    wire id_load_valid;
    wire id_store_valid;
    wire id_branch_valid;
    wire id_jalr_valid;
    wire id_system_valid;
    wire id_is_ecall;
    wire id_is_eret;
    wire id_is_eretn;
    wire id_legal_inst;
    wire [7:0] id_trap_cause;

    wire [31:0] rf_rd1_raw;
    wire [31:0] rf_rd2_raw;

    wire        wb_regwrite;
    wire [31:0] wb_data;

    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    wire        id2_pending_rs1;
    wire        id2_pending_rs2;
    wire        id2_uses_rs1;
    wire        id2_ex_pending_rs1;
    wire        id_ex_load_pending_rs1;
    wire        id_ex_load_pending_rs2;
    wire        ex_mem_load_pending_rs1;
    wire        ex_mem_load_pending_rs2;
    wire        id_source_stall;
    wire [31:0] ex_wb_value;
    wire [31:0] ex_mem_wb_value;
    wire        ex_can_bypass_to_id;
    wire        ex_mem_can_bypass_to_id;
    wire [31:0] id_rs1_resolved;
    wire [31:0] id_rs2_resolved;
    wire [31:0] id2_rs1_to_ex;
    wire [31:0] id2_rs2_to_ex;
    wire        held_id2_rs1_wb_hit;
    wire        held_id2_rs2_wb_hit;
    wire        held_rs1_wb_hit;
    wire        held_rs2_wb_hit;
    wire        load_complete_id2_rs1_hit;
    wire        load_complete_id2_rs2_hit;
    wire        load_complete_rs1_hit;
    wire        load_complete_rs2_hit;
    wire [31:0] ex_rs1_forwarded;
    wire [31:0] ex_rs2_forwarded;

    wire [31:0] ex_alu_in1;
    wire [31:0] ex_alu_in2;
    wire [7:0]  ex_zero_bus;
    wire [31:0] ex_alu_result;
    wire        ex_branch_condition;
    wire [31:0] id2_rs1_control;
    wire [31:0] id2_jalr_sum;
    wire        id2_control_resolved;
    wire        id2_redirect_taken;
    wire [31:0] id2_redirect_target;

    wire        ex_active;
    wire        ex_redirect_taken;
    wire [31:0] ex_redirect_target;
    wire [7:0]  ex_scause;
    wire        ex_trap_taken;
    wire        ex_return_taken;
    wire [31:0] ex_return_target;
    wire        exception_exl_set;
    wire        exception_int_signal;
    wire [2:0]  exception_pend;
    wire        ext_irq_latchable;
    wire        mem_store_active;
    wire        mem_stage_busy;
    wire        id_uses_rs1;
    wire        id_uses_rs2;

    assign rstn = !reset;
    assign sw_i = 16'h0000;

    assign PC_out = pc_reg;

    assign id_op     = if_id_inst[6:0];
    assign id_funct7 = if_id_inst[31:25];
    assign id_funct3 = if_id_inst[14:12];
    assign id_rs1    = if_id_inst[19:15];
    assign id_rs2    = if_id_inst[24:20];
    assign id_rd     = if_id_inst[11:7];

    assign id_iimm       = if_id_inst[31:20];
    assign id_simm       = {if_id_inst[31:25], if_id_inst[11:7]};
    assign id_iimm_shamt = if_id_inst[24:20];
    assign id_bimm       = {if_id_inst[31], if_id_inst[7], if_id_inst[30:25], if_id_inst[11:8]};
    assign id_uimm       = if_id_inst[31:12];
    assign id_jimm       = {if_id_inst[31], if_id_inst[19:12], if_id_inst[20], if_id_inst[30:21]};

    // ID阶段识别异常
    assign id_is_ecall = (if_id_inst == ECALL_INST);
    assign id_is_eret  = (if_id_inst == ERET_INST);
    assign id_is_eretn = (if_id_inst == ERETN_INST);

    assign id_rtype_valid =
        (id_op == OP_REG) &&
        (((id_funct7 == 7'b0000000) &&
          ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
           (id_funct3 == 3'b010) || (id_funct3 == 3'b011) ||
           (id_funct3 == 3'b100) || (id_funct3 == 3'b101) ||
           (id_funct3 == 3'b110) || (id_funct3 == 3'b111))) ||
         ((id_funct7 == 7'b0100000) &&
          ((id_funct3 == 3'b000) || (id_funct3 == 3'b101))));

    assign id_itype_alu_valid =
        (id_op == OP_IMM) &&
        ((id_funct3 == 3'b000) || (id_funct3 == 3'b010) ||
         (id_funct3 == 3'b011) || (id_funct3 == 3'b100) ||
         (id_funct3 == 3'b110) || (id_funct3 == 3'b111) ||
         ((id_funct3 == 3'b001) && (id_funct7 == 7'b0000000)) ||
         ((id_funct3 == 3'b101) &&
          ((id_funct7 == 7'b0000000) || (id_funct7 == 7'b0100000))));

    assign id_load_valid =
        (id_op == OP_LOAD) &&
        ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
         (id_funct3 == 3'b010) || (id_funct3 == 3'b100) ||
         (id_funct3 == 3'b101));

    assign id_store_valid =
        (id_op == OP_STORE) &&
        ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
         (id_funct3 == 3'b010));

    assign id_branch_valid =
        (id_op == OP_BRANCH) &&
        ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
         (id_funct3 == 3'b100) || (id_funct3 == 3'b101) ||
         (id_funct3 == 3'b110) || (id_funct3 == 3'b111));

    assign id_jalr_valid = (id_op == OP_JALR) && (id_funct3 == 3'b000);
    assign id_system_valid = (id_op == OP_SYSTEM) && (id_is_ecall || id_is_eret || id_is_eretn);

    assign id_legal_inst =
        id_rtype_valid || id_itype_alu_valid || id_load_valid || id_store_valid ||
        id_branch_valid || id_jalr_valid || id_system_valid ||
        (id_op == OP_LUI) || (id_op == OP_AUIPC) || (id_op == OP_JAL);

    assign id_trap_cause =
        id_is_ecall ? CAUSE_SYSCALL :
        (!id_legal_inst && if_id_valid) ? CAUSE_ILLEGAL :
                                          CAUSE_NONE;

    assign id_uses_rs1 =
        id_rtype_valid || id_itype_alu_valid || id_load_valid ||
        id_store_valid || id_branch_valid || id_jalr_valid;

    assign id_uses_rs2 =
        id_rtype_valid || id_store_valid || id_branch_valid;

    assign id2_uses_rs1 =
        id2_valid &&
        (id2_branch || id2_jalr || id2_mem_read || id2_mem_write ||
         (id2_reg_write && !id2_is_lui && !id2_is_auipc && !id2_jal));

    assign wb_data = mem_wb_data;

    assign wb_regwrite = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0);

    assign id_rs1_data =
        (wb_regwrite && (mem_wb_rd == id_rs1) && (id_rs1 != 5'd0)) ? wb_data : rf_rd1_raw;

    assign id_rs2_data =
        (wb_regwrite && (mem_wb_rd == id_rs2) && (id_rs2 != 5'd0)) ? wb_data : rf_rd2_raw;

    assign ex_wb_value =
        (id_ex_wd_sel == 2'b10) ? (id_ex_pc + 32'd4) : ex_alu_result;

    assign ex_mem_wb_value =
        (ex_mem_wd_sel == 2'b10) ? ex_mem_pc_plus4 : ex_mem_alu_result;

    assign ex_can_bypass_to_id =
        id_ex_valid && id_ex_reg_write && !id_ex_mem_read && (id_ex_rd != 5'd0) &&
        !(ex_trap_taken || ex_return_taken);

    assign ex_mem_can_bypass_to_id =
        ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read && (ex_mem_rd != 5'd0);

    assign id2_ex_pending_rs1 =
        id2_uses_rs1 && id_ex_valid && id_ex_reg_write &&
        (id_ex_rd == id2_rs1) && (id2_rs1 != 5'd0);

    assign id2_pending_rs1 =
        if_id_valid && id_uses_rs1 && id2_valid && id2_reg_write && id2_mem_read &&
        (id2_rd == id_rs1) && (id_rs1 != 5'd0);

    assign id2_pending_rs2 =
        if_id_valid && id_uses_rs2 && id2_valid && id2_reg_write && id2_mem_read &&
        (id2_rd == id_rs2) && (id_rs2 != 5'd0);

    assign id_ex_load_pending_rs1 =
        if_id_valid && id_uses_rs1 && id_ex_valid && id_ex_reg_write && id_ex_mem_read &&
        (id_ex_rd == id_rs1) && (id_rs1 != 5'd0);

    assign id_ex_load_pending_rs2 =
        if_id_valid && id_uses_rs2 && id_ex_valid && id_ex_reg_write && id_ex_mem_read &&
        (id_ex_rd == id_rs2) && (id_rs2 != 5'd0);

    assign ex_mem_load_pending_rs1 =
        if_id_valid && id_uses_rs1 && ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id_rs1) && (id_rs1 != 5'd0);

    assign ex_mem_load_pending_rs2 =
        if_id_valid && id_uses_rs2 && ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id_rs2) && (id_rs2 != 5'd0);

    assign id_source_stall =
        id2_pending_rs1 || id2_pending_rs2 ||
        id_ex_load_pending_rs1 || id_ex_load_pending_rs2 ||
        ex_mem_load_pending_rs1 || ex_mem_load_pending_rs2;

    assign id_rs1_resolved =
        (id_uses_rs1 && ex_mem_can_bypass_to_id && (ex_mem_rd == id_rs1) && (id_rs1 != 5'd0)) ? ex_mem_wb_value :
                                                                                                 id_rs1_data;

    assign id_rs2_resolved =
        (id_uses_rs2 && ex_mem_can_bypass_to_id && (ex_mem_rd == id_rs2) && (id_rs2 != 5'd0)) ? ex_mem_wb_value :
                                                                                                 id_rs2_data;

    assign id2_rs1_to_ex =
        (id2_valid && ex_can_bypass_to_id && (id_ex_rd == id2_rs1) && (id2_rs1 != 5'd0)) ? ex_wb_value :
        (id2_valid && ex_mem_can_bypass_to_id && (ex_mem_rd == id2_rs1) && (id2_rs1 != 5'd0)) ? ex_mem_wb_value :
        (id2_valid && held_id2_rs1_wb_hit) ? wb_data :
                                             id2_rs1_data;

    assign id2_rs2_to_ex =
        (id2_valid && ex_can_bypass_to_id && (id_ex_rd == id2_rs2) && (id2_rs2 != 5'd0)) ? ex_wb_value :
        (id2_valid && ex_mem_can_bypass_to_id && (ex_mem_rd == id2_rs2) && (id2_rs2 != 5'd0)) ? ex_mem_wb_value :
        (id2_valid && held_id2_rs2_wb_hit) ? wb_data :
                                             id2_rs2_data;

    assign id2_rs1_control =
        (id2_valid && ex_mem_can_bypass_to_id && (ex_mem_rd == id2_rs1) && (id2_rs1 != 5'd0)) ? ex_mem_wb_value :
        (id2_valid && held_id2_rs1_wb_hit) ? wb_data :
                                             id2_rs1_data;

    assign held_id2_rs1_wb_hit =
        wb_regwrite && (mem_wb_rd == id2_rs1) && (id2_rs1 != 5'd0);

    assign held_id2_rs2_wb_hit =
        wb_regwrite && (mem_wb_rd == id2_rs2) && (id2_rs2 != 5'd0);

    assign held_rs1_wb_hit =
        wb_regwrite && (mem_wb_rd == id_ex_rs1) && (id_ex_rs1 != 5'd0);

    assign held_rs2_wb_hit =
        wb_regwrite && (mem_wb_rd == id_ex_rs2) && (id_ex_rs2 != 5'd0);

    assign load_complete_id2_rs1_hit =
        mem_wait_pending && mem_wait_wb && mem_wait_data_ready &&
        ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id2_rs1) && (id2_rs1 != 5'd0);

    assign load_complete_id2_rs2_hit =
        mem_wait_pending && mem_wait_wb && mem_wait_data_ready &&
        ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id2_rs2) && (id2_rs2 != 5'd0);

    assign load_complete_rs1_hit =
        mem_wait_pending && mem_wait_wb && mem_wait_data_ready &&
        ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id_ex_rs1) && (id_ex_rs1 != 5'd0);

    assign load_complete_rs2_hit =
        mem_wait_pending && mem_wait_wb && mem_wait_data_ready &&
        ex_mem_valid && ex_mem_reg_write && ex_mem_mem_read &&
        (ex_mem_rd == id_ex_rs2) && (id_ex_rs2 != 5'd0);

    assign ex_rs1_forwarded =
        (id_ex_rs1_fwd_sel == FWD_WB) ? wb_data :
                                        id_ex_rs1_data;

    assign ex_rs2_forwarded =
        (id_ex_rs2_fwd_sel == FWD_WB) ? wb_data :
                                        id_ex_rs2_data;

    assign ex_alu_in1 =
        id_ex_is_auipc ? id_ex_pc :
        id_ex_is_lui   ? 32'h0000_0000 :
                         ex_rs1_forwarded;

    assign ex_alu_in2 =
        (id_ex_is_lui || id_ex_is_auipc || id_ex_alu_src) ? id_ex_imm : ex_rs2_forwarded;

    assign ex_active = id_ex_valid && !mem_stage_busy;

    assign ex_redirect_taken = ex_active && ((id_ex_branch && ex_branch_condition) || id_ex_jal || id_ex_jalr);

    assign ex_redirect_target =
        id_ex_jalr ? {ex_alu_result[31:1], 1'b0} :
                     (id_ex_pc + id_ex_imm);

    assign id2_jalr_sum = id2_rs1_control + id2_imm;

    assign id2_control_resolved =
        id2_valid && !mem_stage_busy && !timer_irq_pending && !ext_irq_pending &&
        (id2_trap_cause == CAUSE_NONE) && !(id2_is_eret || id2_is_eretn) &&
        (id2_jal || (id2_jalr && !id2_ex_pending_rs1));

    assign id2_redirect_taken = id2_control_resolved;

    assign id2_redirect_target =
        id2_jalr ? {id2_jalr_sum[31:1], 1'b0} :
                   (id2_pc + id2_imm);

    // 判断中断原因
    assign ex_scause =
        (id_ex_trap_cause != CAUSE_NONE) ? id_ex_trap_cause :
        timer_irq_pending                ? CAUSE_TIMER :
        ext_irq_pending                  ? ext_irq_cause_pending :
                                           CAUSE_NONE;

    assign ex_trap_taken = ex_active && exception_int_signal;
    assign ex_return_taken = ex_active && status[0] && (id_ex_is_eret || id_ex_is_eretn);
    assign ex_return_target = id_ex_is_eretn ? (sepc + 32'd4) : sepc; //两种返回地址


    assign ext_irq_latchable =
        ext_irq_valid && !status[0] && !ext_irq_pending &&
        (ext_irq_cause != CAUSE_NONE);
    assign ext_irq_ack =
        ex_trap_taken && ext_irq_pending &&
        (ex_scause == ext_irq_cause_pending); 
    assign ext_irq_ack_cause = ext_irq_ack ? ext_irq_cause_pending : CAUSE_NONE;

    assign mem_store_active =
        ex_mem_valid && ex_mem_mem_write && !mem_wait_pending;

    assign mem_stage_busy = mem_wait_pending || mem_store_active;

    assign mem_w = !reset && mem_store_active;

    assign Addr_out = ex_mem_alu_result;

    assign Data_out = ex_mem_rs2_data;

    assign dm_ctrl = ex_mem_dm_ctrl;

    assign CPU_MIO =
        !(mem_stage_busy || (id_ex_valid && id_ex_mem_read));

    // Board debug word: 1e, trap count, STATUS, SCAUSE.
    assign int_debug = {8'h1e, trap_count, status, scause};

    ctrl U_CTRL(
        .Op      (id_op),
        .Funct7  (id_funct7),
        .Funct3  (id_funct3),
        .zero    (1'b0),
        .RegWrite(dec_reg_write),
        .MemWrite(dec_mem_write),
        .EXTOp   (dec_ext_op),
        .ALUOp   (dec_alu_op),
        .ALUSrc  (dec_alu_src),
        .DMType  (dec_dm_ctrl),
        .WDSel   (dec_wd_sel),
        .Branch  (dec_branch),
        .jal     (dec_jal),
        .jalr    (dec_jalr)
    );

    EXT U_EXT(
        .iimm_shamt(id_iimm_shamt),
        .iimm      (id_iimm),
        .simm      (id_simm),
        .bimm      (id_bimm),
        .uimm      (id_uimm),
        .jimm      (id_jimm),
        .EXTOp     (dec_ext_op),
        .immout    (dec_imm)
    );

    RF U_RF(
        .clk (clk),
        .rstn(rstn),
        .RFWr(wb_regwrite),
        .sw_i(sw_i),
        .A1  (id_rs1),
        .A2  (id_rs2),
        .A3  (mem_wb_rd),
        .WD  (wb_data),
        .RD1 (rf_rd1_raw),
        .RD2 (rf_rd2_raw)
    );

    ALU U_ALU(
        .clk  (clk),
        .rstn (rstn),
        .sw_i (sw_i),
        .A    (ex_alu_in1),
        .B    (ex_alu_in2),
        .aluop(id_ex_alu_op),
        .zero (ex_zero_bus),
        .C    (ex_alu_result)
    );

    branch U_BRANCH(
        .rs1     (ex_rs1_forwarded),
        .rs2     (ex_rs2_forwarded),
        .funct3  (id_ex_funct3),
        .br_taken(ex_branch_condition)
    );

    ExceptionUnit U_EXCEPTION(
        .STATUS    (status),
        .EX_SCAUSE (ex_scause),
        .INTMASK   (intmask),
        .EXL_Set   (exception_exl_set),
        .INT_Signal(exception_int_signal),
        .INT_PEND  (exception_pend)
    );

    initial begin
        reset_pending = 1'b1;
    end

    // The board-level CPU clock is generated by a divider whose output can stop
    // toggling while reset is asserted. Latch reset asynchronously, then consume
    // it synchronously on the first CPU clock edge after reset is released.
    always @(posedge clk or posedge reset) begin
        if (reset)
            reset_pending <= 1'b1;
        else
            reset_pending <= 1'b0;
    end

    always @(posedge clk) begin
        if (reset || reset_pending) begin
            pc_reg <= 32'h0000_0000;

            if2_pc <= 32'h0000_0000;
            if2_inst <= NOP;
            if2_valid <= 1'b0;

            if_id_pc <= 32'h0000_0000;
            if_id_inst <= NOP;
            if_id_valid <= 1'b0;

            id2_pc <= 32'h0000_0000;
            id2_rs1_data <= 32'h0000_0000;
            id2_rs2_data <= 32'h0000_0000;
            id2_imm <= 32'h0000_0000;
            id2_rs1 <= 5'd0;
            id2_rs2 <= 5'd0;
            id2_rd <= 5'd0;
            id2_funct3 <= 3'b000;
            id2_alu_op <= 5'b00000;
            id2_dm_ctrl <= 3'b000;
            id2_wd_sel <= 2'b00;
            id2_reg_write <= 1'b0;
            id2_mem_write <= 1'b0;
            id2_mem_read <= 1'b0;
            id2_alu_src <= 1'b0;
            id2_branch <= 1'b0;
            id2_jal <= 1'b0;
            id2_jalr <= 1'b0;
            id2_is_lui <= 1'b0;
            id2_is_auipc <= 1'b0;
            id2_trap_cause <= CAUSE_NONE;
            id2_is_eret <= 1'b0;
            id2_is_eretn <= 1'b0;
            id2_valid <= 1'b0;

            id_ex_pc <= 32'h0000_0000;
            id_ex_rs1_data <= 32'h0000_0000;
            id_ex_rs2_data <= 32'h0000_0000;
            id_ex_imm <= 32'h0000_0000;
            id_ex_rs1 <= 5'd0;
            id_ex_rs2 <= 5'd0;
            id_ex_rd <= 5'd0;
            id_ex_funct3 <= 3'b000;
            id_ex_alu_op <= 5'b00000;
            id_ex_dm_ctrl <= 3'b000;
            id_ex_wd_sel <= 2'b00;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_alu_src <= 1'b0;
            id_ex_branch <= 1'b0;
            id_ex_jal <= 1'b0;
            id_ex_jalr <= 1'b0;
            id_ex_is_lui <= 1'b0;
            id_ex_is_auipc <= 1'b0;
            id_ex_trap_cause <= CAUSE_NONE;
            id_ex_is_eret <= 1'b0;
            id_ex_is_eretn <= 1'b0;
            id_ex_rs1_fwd_sel <= FWD_NONE;
            id_ex_rs2_fwd_sel <= FWD_NONE;
            id_ex_valid <= 1'b0;

            ex_mem_alu_result <= 32'h0000_0000;
            ex_mem_rs2_data <= 32'h0000_0000;
            ex_mem_pc_plus4 <= 32'h0000_0000;
            ex_mem_rd <= 5'd0;
            ex_mem_dm_ctrl <= 3'b000;
            ex_mem_wd_sel <= 2'b00;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_valid <= 1'b0;

            mem_wb_data <= 32'h0000_0000;
            mem_wb_rd <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_valid <= 1'b0;

            mem_wait_pending <= 1'b0;
            mem_wait_wb <= 1'b0;
            mem_wait_data_ready <= 1'b0;
            int_prev <= 1'b0;
            timer_irq_pending <= 1'b0;
            ext_irq_pending <= 1'b0;
            ext_irq_cause_pending <= CAUSE_NONE;
            sepc <= 32'h0000_0000;
            scause <= CAUSE_NONE;
            status <= 8'h00;
            intmask <= 8'h1f;
            trap_count <= 8'h00;
        end else if (mem_wait_pending) begin
            int_prev <= INT;
            if (INT && !int_prev && !status[0])
                timer_irq_pending <= 1'b1;
            if (ext_irq_latchable) begin
                ext_irq_pending <= 1'b1;
                ext_irq_cause_pending <= ext_irq_cause;
            end

            pc_reg <= pc_reg;

            if2_pc <= if2_pc;
            if2_inst <= if2_inst;
            if2_valid <= if2_valid;

            if_id_pc <= if_id_pc;
            if_id_inst <= if_id_inst;
            if_id_valid <= if_id_valid;

            id2_pc <= id2_pc;
            id2_rs1_data <=
                load_complete_id2_rs1_hit ? Data_in :
                held_id2_rs1_wb_hit       ? wb_data :
                                             id2_rs1_data;
            id2_rs2_data <=
                load_complete_id2_rs2_hit ? Data_in :
                held_id2_rs2_wb_hit       ? wb_data :
                                             id2_rs2_data;
            id2_imm <= id2_imm;
            id2_rs1 <= id2_rs1;
            id2_rs2 <= id2_rs2;
            id2_rd <= id2_rd;
            id2_funct3 <= id2_funct3;
            id2_alu_op <= id2_alu_op;
            id2_dm_ctrl <= id2_dm_ctrl;
            id2_wd_sel <= id2_wd_sel;
            id2_reg_write <= id2_reg_write;
            id2_mem_write <= id2_mem_write;
            id2_mem_read <= id2_mem_read;
            id2_alu_src <= id2_alu_src;
            id2_branch <= id2_branch;
            id2_jal <= id2_jal;
            id2_jalr <= id2_jalr;
            id2_is_lui <= id2_is_lui;
            id2_is_auipc <= id2_is_auipc;
            id2_trap_cause <= id2_trap_cause;
            id2_is_eret <= id2_is_eret;
            id2_is_eretn <= id2_is_eretn;
            id2_valid <= id2_valid;

            id_ex_pc <= id_ex_pc;
            id_ex_rs1_data <=
                load_complete_rs1_hit ? Data_in :
                held_rs1_wb_hit       ? wb_data :
                                         id_ex_rs1_data;
            id_ex_rs2_data <=
                load_complete_rs2_hit ? Data_in :
                held_rs2_wb_hit       ? wb_data :
                                         id_ex_rs2_data;
            id_ex_imm <= id_ex_imm;
            id_ex_rs1 <= id_ex_rs1;
            id_ex_rs2 <= id_ex_rs2;
            id_ex_rd <= id_ex_rd;
            id_ex_funct3 <= id_ex_funct3;
            id_ex_alu_op <= id_ex_alu_op;
            id_ex_dm_ctrl <= id_ex_dm_ctrl;
            id_ex_wd_sel <= id_ex_wd_sel;
            id_ex_reg_write <= id_ex_reg_write;
            id_ex_mem_write <= id_ex_mem_write;
            id_ex_mem_read <= id_ex_mem_read;
            id_ex_alu_src <= id_ex_alu_src;
            id_ex_branch <= id_ex_branch;
            id_ex_jal <= id_ex_jal;
            id_ex_jalr <= id_ex_jalr;
            id_ex_is_lui <= id_ex_is_lui;
            id_ex_is_auipc <= id_ex_is_auipc;
            id_ex_trap_cause <= id_ex_trap_cause;
            id_ex_is_eret <= id_ex_is_eret;
            id_ex_is_eretn <= id_ex_is_eretn;
            id_ex_rs1_fwd_sel <= FWD_NONE;
            id_ex_rs2_fwd_sel <= FWD_NONE;
            id_ex_valid <= id_ex_valid;

            if (!(mem_wait_wb && mem_wait_data_ready)) begin
                ex_mem_alu_result <= ex_mem_alu_result;
                ex_mem_rs2_data <= ex_mem_rs2_data;
                ex_mem_pc_plus4 <= ex_mem_pc_plus4;
                ex_mem_rd <= ex_mem_rd;
                ex_mem_dm_ctrl <= ex_mem_dm_ctrl;
                ex_mem_wd_sel <= ex_mem_wd_sel;
                ex_mem_reg_write <= ex_mem_reg_write;
                ex_mem_mem_write <= ex_mem_mem_write;
                ex_mem_mem_read <= ex_mem_mem_read;
                ex_mem_valid <= ex_mem_valid;

                mem_wb_data <= 32'h0000_0000;
                mem_wb_rd <= 5'd0;
                mem_wb_reg_write <= 1'b0;
                mem_wb_valid <= 1'b0;

                mem_wait_pending <= 1'b1;
                mem_wait_wb <= 1'b1;
                mem_wait_data_ready <= mem_wait_wb;
            end else begin
                ex_mem_alu_result <= 32'h0000_0000;
                ex_mem_rs2_data <= 32'h0000_0000;
                ex_mem_pc_plus4 <= 32'h0000_0000;
                ex_mem_rd <= 5'd0;
                ex_mem_dm_ctrl <= 3'b000;
                ex_mem_wd_sel <= 2'b00;
                ex_mem_reg_write <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_valid <= 1'b0;

                mem_wb_data <= Data_in;
                mem_wb_rd <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write;
                mem_wb_valid <= ex_mem_valid;

                mem_wait_pending <= 1'b0;
                mem_wait_wb <= 1'b0;
                mem_wait_data_ready <= 1'b0;
            end
        end else if (mem_store_active) begin
            int_prev <= INT;
            if (INT && !int_prev && !status[0])
                timer_irq_pending <= 1'b1;
            if (ext_irq_latchable) begin
                ext_irq_pending <= 1'b1;
                ext_irq_cause_pending <= ext_irq_cause;
            end

            pc_reg <= pc_reg;

            if2_pc <= if2_pc;
            if2_inst <= if2_inst;
            if2_valid <= if2_valid;

            if_id_pc <= if_id_pc;
            if_id_inst <= if_id_inst;
            if_id_valid <= if_id_valid;

            id2_pc <= id2_pc;
            id2_rs1_data <=
                held_id2_rs1_wb_hit ? wb_data : id2_rs1_data;
            id2_rs2_data <=
                held_id2_rs2_wb_hit ? wb_data : id2_rs2_data;
            id2_imm <= id2_imm;
            id2_rs1 <= id2_rs1;
            id2_rs2 <= id2_rs2;
            id2_rd <= id2_rd;
            id2_funct3 <= id2_funct3;
            id2_alu_op <= id2_alu_op;
            id2_dm_ctrl <= id2_dm_ctrl;
            id2_wd_sel <= id2_wd_sel;
            id2_reg_write <= id2_reg_write;
            id2_mem_write <= id2_mem_write;
            id2_mem_read <= id2_mem_read;
            id2_alu_src <= id2_alu_src;
            id2_branch <= id2_branch;
            id2_jal <= id2_jal;
            id2_jalr <= id2_jalr;
            id2_is_lui <= id2_is_lui;
            id2_is_auipc <= id2_is_auipc;
            id2_trap_cause <= id2_trap_cause;
            id2_is_eret <= id2_is_eret;
            id2_is_eretn <= id2_is_eretn;
            id2_valid <= id2_valid;

            id_ex_pc <= id_ex_pc;
            id_ex_rs1_data <=
                held_rs1_wb_hit ? wb_data : id_ex_rs1_data;
            id_ex_rs2_data <=
                held_rs2_wb_hit ? wb_data : id_ex_rs2_data;
            id_ex_imm <= id_ex_imm;
            id_ex_rs1 <= id_ex_rs1;
            id_ex_rs2 <= id_ex_rs2;
            id_ex_rd <= id_ex_rd;
            id_ex_funct3 <= id_ex_funct3;
            id_ex_alu_op <= id_ex_alu_op;
            id_ex_dm_ctrl <= id_ex_dm_ctrl;
            id_ex_wd_sel <= id_ex_wd_sel;
            id_ex_reg_write <= id_ex_reg_write;
            id_ex_mem_write <= id_ex_mem_write;
            id_ex_mem_read <= id_ex_mem_read;
            id_ex_alu_src <= id_ex_alu_src;
            id_ex_branch <= id_ex_branch;
            id_ex_jal <= id_ex_jal;
            id_ex_jalr <= id_ex_jalr;
            id_ex_is_lui <= id_ex_is_lui;
            id_ex_is_auipc <= id_ex_is_auipc;
            id_ex_trap_cause <= id_ex_trap_cause;
            id_ex_is_eret <= id_ex_is_eret;
            id_ex_is_eretn <= id_ex_is_eretn;
            id_ex_rs1_fwd_sel <= FWD_NONE;
            id_ex_rs2_fwd_sel <= FWD_NONE;
            id_ex_valid <= id_ex_valid;

            ex_mem_alu_result <= 32'h0000_0000;
            ex_mem_rs2_data <= 32'h0000_0000;
            ex_mem_pc_plus4 <= 32'h0000_0000;
            ex_mem_rd <= 5'd0;
            ex_mem_dm_ctrl <= 3'b000;
            ex_mem_wd_sel <= 2'b00;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_valid <= 1'b0;

            mem_wb_data <= 32'h0000_0000;
            mem_wb_rd <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_valid <= 1'b0;

            mem_wait_pending <= 1'b0;
            mem_wait_wb <= 1'b0;
            mem_wait_data_ready <= 1'b0;
        end else begin
            // 锁存
            int_prev <= INT;
            if (INT && !int_prev && !status[0])
                timer_irq_pending <= 1'b1;
            if (ext_irq_latchable) begin
                ext_irq_pending <= 1'b1;
                ext_irq_cause_pending <= ext_irq_cause;
            end

            if (ex_mem_valid && !ex_mem_mem_read) begin
                mem_wb_data <= (ex_mem_wd_sel == 2'b10) ? ex_mem_pc_plus4 : ex_mem_alu_result;
                mem_wb_rd <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write;
                mem_wb_valid <= ex_mem_valid;
            end else begin
                mem_wb_data <= 32'h0000_0000;
                mem_wb_rd <= 5'd0;
                mem_wb_reg_write <= 1'b0;
                mem_wb_valid <= 1'b0;
            end

            if (ex_active && !(ex_trap_taken || ex_return_taken)) begin
                ex_mem_alu_result <= ex_alu_result;
                ex_mem_rs2_data <= ex_rs2_forwarded;
                ex_mem_pc_plus4 <= id_ex_pc + 32'd4;
                ex_mem_rd <= id_ex_rd;
                ex_mem_dm_ctrl <= id_ex_dm_ctrl;
                ex_mem_wd_sel <= id_ex_wd_sel;
                ex_mem_reg_write <= id_ex_reg_write;
                ex_mem_mem_write <= id_ex_mem_write;
                ex_mem_mem_read <= id_ex_mem_read;
                ex_mem_valid <= 1'b1;
            end else begin
                ex_mem_alu_result <= 32'h0000_0000;
                ex_mem_rs2_data <= 32'h0000_0000;
                ex_mem_pc_plus4 <= 32'h0000_0000;
                ex_mem_rd <= 5'd0;
                ex_mem_dm_ctrl <= 3'b000;
                ex_mem_wd_sel <= 2'b00;
                ex_mem_reg_write <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_valid <= 1'b0;
            end

            // 阻止多余的内存读
            mem_wait_pending <= ex_active && id_ex_mem_read && !(ex_trap_taken || ex_return_taken);
            mem_wait_wb <= 1'b0;
            mem_wait_data_ready <= 1'b0;

            if (ex_trap_taken) begin
                sepc <= id_ex_pc;
                scause <= ex_scause;
                status[0] <= exception_exl_set;
                trap_count <= trap_count + 8'd1; //test
                if (ex_scause == CAUSE_TIMER)
                    timer_irq_pending <= 1'b0;
                if (ext_irq_ack) begin
                    ext_irq_pending <= 1'b0;
                    ext_irq_cause_pending <= CAUSE_NONE;
                end

                pc_reg <= TRAP_VECTOR;

                if2_pc <= pc_reg;
                if2_inst <= inst_in;
                if2_valid <= 1'b0;
                if_id_pc <= if2_pc;
                if_id_inst <= if2_inst;
                if_id_valid <= 1'b0;
                id2_valid <= 1'b0;
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= 1'b0;
            end else if (ex_return_taken) begin
                status[0] <= 1'b0;
                pc_reg <= ex_return_target;

                if2_pc <= pc_reg;
                if2_inst <= inst_in;
                if2_valid <= 1'b0;
                if_id_pc <= if2_pc;
                if_id_inst <= if2_inst;
                if_id_valid <= 1'b0;
                id2_valid <= 1'b0;
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= 1'b0;
            end else if (ex_redirect_taken) begin
                pc_reg <= ex_redirect_target;

                if2_pc <= pc_reg;
                if2_inst <= inst_in;
                if2_valid <= 1'b0;
                if_id_pc <= if2_pc;
                if_id_inst <= if2_inst;
                if_id_valid <= 1'b0;
                id2_valid <= 1'b0;

                // A redirect only needs to invalidate the younger instruction.
                // The payload registers are ignored while valid is low, so
                // holding them avoids a wide redirect-controlled mux.
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= 1'b0;
            end else if (id2_redirect_taken) begin
                pc_reg <= id2_redirect_target;

                if2_pc <= pc_reg;
                if2_inst <= inst_in;
                if2_valid <= 1'b0;
                if_id_pc <= if2_pc;
                if_id_inst <= if2_inst;
                if_id_valid <= 1'b0;

                id_ex_pc <= id2_pc;
                id_ex_rs1_data <= id2_rs1_to_ex;
                id_ex_rs2_data <= id2_rs2_to_ex;
                id_ex_imm <= id2_imm;
                id_ex_rs1 <= id2_rs1;
                id_ex_rs2 <= id2_rs2;
                id_ex_rd <= id2_rd;
                id_ex_funct3 <= id2_funct3;
                id_ex_alu_op <= id2_alu_op;
                id_ex_dm_ctrl <= id2_dm_ctrl;
                id_ex_wd_sel <= id2_wd_sel;
                id_ex_reg_write <= id2_reg_write;
                id_ex_mem_write <= id2_mem_write;
                id_ex_mem_read <= id2_mem_read;
                id_ex_alu_src <= id2_alu_src;
                id_ex_branch <= 1'b0;
                id_ex_jal <= 1'b0;
                id_ex_jalr <= 1'b0;
                id_ex_is_lui <= id2_is_lui;
                id_ex_is_auipc <= id2_is_auipc;
                id_ex_trap_cause <= id2_trap_cause;
                id_ex_is_eret <= id2_is_eret;
                id_ex_is_eretn <= id2_is_eretn;
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= id2_valid;

                id2_valid <= 1'b0;
            end else if (id_source_stall) begin
                pc_reg <= pc_reg;

                if2_pc <= if2_pc;
                if2_inst <= if2_inst;
                if2_valid <= if2_valid;

                if_id_pc <= if_id_pc;
                if_id_inst <= if_id_inst;
                if_id_valid <= if_id_valid;

                id_ex_pc <= id2_pc;
                id_ex_rs1_data <= id2_rs1_to_ex;
                id_ex_rs2_data <= id2_rs2_to_ex;
                id_ex_imm <= id2_imm;
                id_ex_rs1 <= id2_rs1;
                id_ex_rs2 <= id2_rs2;
                id_ex_rd <= id2_rd;
                id_ex_funct3 <= id2_funct3;
                id_ex_alu_op <= id2_alu_op;
                id_ex_dm_ctrl <= id2_dm_ctrl;
                id_ex_wd_sel <= id2_wd_sel;
                id_ex_reg_write <= id2_reg_write;
                id_ex_mem_write <= id2_mem_write;
                id_ex_mem_read <= id2_mem_read;
                id_ex_alu_src <= id2_alu_src;
                id_ex_branch <= id2_branch;
                id_ex_jal <= id2_control_resolved ? 1'b0 : id2_jal;
                id_ex_jalr <= id2_control_resolved ? 1'b0 : id2_jalr;
                id_ex_is_lui <= id2_is_lui;
                id_ex_is_auipc <= id2_is_auipc;
                id_ex_trap_cause <= id2_trap_cause;
                id_ex_is_eret <= id2_is_eret;
                id_ex_is_eretn <= id2_is_eretn;
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= id2_valid;

                id2_valid <= 1'b0;
            end else begin
                pc_reg <= pc_reg + 32'd4;

                if2_pc <= pc_reg;
                if2_inst <= inst_in;
                if2_valid <= 1'b1;

                if_id_pc <= if2_pc;
                if_id_inst <= if2_inst;
                if_id_valid <= if2_valid;

                id_ex_pc <= id2_pc;
                id_ex_rs1_data <= id2_rs1_to_ex;
                id_ex_rs2_data <= id2_rs2_to_ex;
                id_ex_imm <= id2_imm;
                id_ex_rs1 <= id2_rs1;
                id_ex_rs2 <= id2_rs2;
                id_ex_rd <= id2_rd;
                id_ex_funct3 <= id2_funct3;
                id_ex_alu_op <= id2_alu_op;
                id_ex_dm_ctrl <= id2_dm_ctrl;
                id_ex_wd_sel <= id2_wd_sel;
                id_ex_reg_write <= id2_reg_write;
                id_ex_mem_write <= id2_mem_write;
                id_ex_mem_read <= id2_mem_read;
                id_ex_alu_src <= id2_alu_src;
                id_ex_branch <= id2_branch;
                id_ex_jal <= id2_control_resolved ? 1'b0 : id2_jal;
                id_ex_jalr <= id2_control_resolved ? 1'b0 : id2_jalr;
                id_ex_is_lui <= id2_is_lui;
                id_ex_is_auipc <= id2_is_auipc;
                id_ex_trap_cause <= id2_trap_cause;
                id_ex_is_eret <= id2_is_eret;
                id_ex_is_eretn <= id2_is_eretn;
                id_ex_rs1_fwd_sel <= FWD_NONE;
                id_ex_rs2_fwd_sel <= FWD_NONE;
                id_ex_valid <= id2_valid;

                if (if_id_valid) begin
                    id2_pc <= if_id_pc;
                    id2_rs1_data <= id_rs1_resolved;
                    id2_rs2_data <= id_rs2_resolved;
                    id2_imm <= dec_imm;
                    id2_rs1 <= id_rs1;
                    id2_rs2 <= id_rs2;
                    id2_rd <= id_rd;
                    id2_funct3 <= id_funct3;
                    id2_alu_op <= dec_alu_op;
                    id2_dm_ctrl <= dec_dm_ctrl;
                    id2_wd_sel <= dec_wd_sel;
                    id2_reg_write <= dec_reg_write;
                    id2_mem_write <= dec_mem_write;
                    id2_mem_read <= (dec_wd_sel == 2'b01) && dec_reg_write;
                    id2_alu_src <= dec_alu_src;
                    id2_branch <= dec_branch;
                    id2_jal <= dec_jal;
                    id2_jalr <= dec_jalr;
                    id2_is_lui <= (id_op == OP_LUI);
                    id2_is_auipc <= (id_op == OP_AUIPC);
                    id2_trap_cause <= id_trap_cause;
                    id2_is_eret <= id_is_eret;
                    id2_is_eretn <= id_is_eretn;
                    id2_valid <= 1'b1;
                end else begin
                    // Payload is don't-care when valid is low. Holding it keeps
                    // branch/valid control off the 32-bit ID/EX data inputs.
                    id2_valid <= 1'b0;
                end
            end
        end
    end

    wire unused_ok;
    assign unused_ok = MIO_ready;

endmodule

module ExceptionUnit(
    input  [7:0] STATUS,
    input  [7:0] EX_SCAUSE,
    input  [7:0] INTMASK,
    output       EXL_Set,
    output       INT_Signal,
    output [2:0] INT_PEND
);
    localparam [7:0] CAUSE_NONE    = 8'h00;
    localparam [7:0] CAUSE_TIMER   = 8'h01;
    localparam [7:0] CAUSE_ILLEGAL = 8'h02;
    localparam [7:0] CAUSE_SYSCALL = 8'h03;
    localparam [7:0] CAUSE_BUTTON  = 8'h04;
    localparam [7:0] CAUSE_SWITCH  = 8'h05;

    wire cause_is_timer = (EX_SCAUSE == CAUSE_TIMER);
    wire cause_is_illegal = (EX_SCAUSE == CAUSE_ILLEGAL);
    wire cause_is_syscall = (EX_SCAUSE == CAUSE_SYSCALL);
    wire cause_is_button = (EX_SCAUSE == CAUSE_BUTTON);
    wire cause_is_switch = (EX_SCAUSE == CAUSE_SWITCH);
    wire cause_unmasked =
        (cause_is_timer   && INTMASK[0]) ||
        (cause_is_illegal && INTMASK[1]) ||
        (cause_is_syscall && INTMASK[2]) ||
        (cause_is_button  && INTMASK[3]) ||
        (cause_is_switch  && INTMASK[4]);

    assign INT_Signal = (EX_SCAUSE != CAUSE_NONE) && !STATUS[0] && cause_unmasked;
    assign EXL_Set = INT_Signal;
    assign INT_PEND =
        cause_is_timer   ? 3'd1 :
        cause_is_illegal ? 3'd2 :
        cause_is_syscall ? 3'd3 :
        cause_is_button  ? 3'd4 :
        cause_is_switch  ? 3'd5 :
                           3'd0;
endmodule
