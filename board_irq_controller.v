`timescale 1ns / 1ps

module board_irq_controller #(
    parameter DEBOUNCE_BITS = 20,
    parameter HOLDOFF_BITS  = 16
)(
    input         clk,
    input         reset,
    input         timer_irq_i,
    input         manual_timer_i,
    input  [4:0]  btn_i,
    input  [15:0] sw_i,
    input         cpu_irq_ack,
    input  [7:0]  cpu_irq_ack_cause,
    input         mem_w,
    input  [31:0] addr,
    input  [31:0] wdata,
    output        irq_valid,
    output [7:0]  irq_cause,
    output [7:0]  irq_pending_o,
    output [7:0]  irq_mask_o
);
    localparam [7:0] CAUSE_NONE   = 8'h00;
    localparam [7:0] CAUSE_TIMER  = 8'h01;
    localparam [7:0] CAUSE_BUTTON = 8'h04;
    localparam [7:0] CAUSE_SWITCH = 8'h05;

    localparam [31:0] IRQ_MASK_ADDR = 32'hf000_0014;
    localparam [31:0] IRQ_ACK_ADDR  = 32'hf000_0018;

    reg [7:0] irq_pending;
    reg [7:0] irq_mask;
    reg       timer_irq_meta;
    reg       timer_irq_sync;
    reg       manual_timer_meta;
    reg       manual_timer_sync;
    reg       manual_timer_stable;
    reg [DEBOUNCE_BITS-1:0] manual_timer_debounce;
    reg       btn_any_meta;
    reg       btn_any_sync;
    reg       btn_any_stable;
    reg [DEBOUNCE_BITS-1:0] btn_any_debounce;
    reg       sw13_meta;
    reg       sw13_sync;
    reg       sw13_stable;
    reg [DEBOUNCE_BITS-1:0] sw13_debounce;
    reg       timer_irq_d;
    reg       manual_timer_d;
    reg       btn_any_d;
    reg       sw13_d;
    reg       manual_timer_armed_low;
    reg       btn_any_armed_low;
    reg       sw13_armed_low;
    reg [DEBOUNCE_BITS:0] startup_guard;
    reg [HOLDOFF_BITS-1:0] button_holdoff;
    reg [HOLDOFF_BITS-1:0] switch_holdoff;
    reg [HOLDOFF_BITS-1:0] manual_holdoff;

    wire btn_any = |btn_i;
    wire timer_event = timer_irq_sync & ~timer_irq_d;
    wire manual_timer_event =
        manual_timer_stable & ~manual_timer_d & manual_timer_armed_low &
        (startup_guard == {(DEBOUNCE_BITS+1){1'b0}}) &
        (manual_holdoff == {HOLDOFF_BITS{1'b0}});
    wire button_event =
        btn_any_stable & ~btn_any_d & btn_any_armed_low &
        (startup_guard == {(DEBOUNCE_BITS+1){1'b0}}) &
        (button_holdoff == {HOLDOFF_BITS{1'b0}});
    wire switch_event =
        sw13_stable & ~sw13_d & sw13_armed_low &
        (startup_guard == {(DEBOUNCE_BITS+1){1'b0}}) &
        (switch_holdoff == {HOLDOFF_BITS{1'b0}});
    wire irq_mask_we = mem_w && (addr == IRQ_MASK_ADDR);
    wire irq_ack_we = mem_w && (addr == IRQ_ACK_ADDR);

    reg [7:0] pending_next;

    function [7:0] cause_to_pending_bit;
        input [7:0] cause;
        begin
            case (cause)
                CAUSE_TIMER:  cause_to_pending_bit = 8'b0000_0001;
                CAUSE_BUTTON: cause_to_pending_bit = 8'b0000_1000;
                CAUSE_SWITCH: cause_to_pending_bit = 8'b0001_0000;
                default:      cause_to_pending_bit = 8'b0000_0000;
            endcase
        end
    endfunction

    always @(*) begin
        pending_next = irq_pending;

        if (timer_event)
            pending_next[0] = 1'b1;
        if (manual_timer_event)
            pending_next[0] = 1'b1;
        if (button_event)
            pending_next[3] = 1'b1;
        if (switch_event)
            pending_next[4] = 1'b1;

        if (cpu_irq_ack)
            pending_next = pending_next & ~cause_to_pending_bit(cpu_irq_ack_cause);
        if (irq_ack_we)
            pending_next = pending_next & ~wdata[7:0];
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            irq_pending <= 8'h00;
            irq_mask <= 8'h19;
            timer_irq_meta <= 1'b0;
            timer_irq_sync <= 1'b0;
            manual_timer_meta <= 1'b0;
            manual_timer_sync <= 1'b0;
            manual_timer_stable <= 1'b0;
            manual_timer_debounce <= {DEBOUNCE_BITS{1'b0}};
            btn_any_meta <= 1'b0;
            btn_any_sync <= 1'b0;
            btn_any_stable <= 1'b0;
            btn_any_debounce <= {DEBOUNCE_BITS{1'b0}};
            sw13_meta <= 1'b0;
            sw13_sync <= 1'b0;
            sw13_stable <= 1'b0;
            sw13_debounce <= {DEBOUNCE_BITS{1'b0}};
            timer_irq_d <= 1'b0;
            manual_timer_d <= 1'b0;
            btn_any_d <= 1'b0;
            sw13_d <= 1'b0;
            manual_timer_armed_low <= 1'b0;
            btn_any_armed_low <= 1'b0;
            sw13_armed_low <= 1'b0;
            startup_guard <= {(DEBOUNCE_BITS+1){1'b1}};
            button_holdoff <= {HOLDOFF_BITS{1'b0}};
            switch_holdoff <= {HOLDOFF_BITS{1'b0}};
            manual_holdoff <= {HOLDOFF_BITS{1'b0}};
        end else begin
            irq_pending <= pending_next;
            if (irq_mask_we)
                irq_mask <= wdata[7:0];

            timer_irq_meta <= timer_irq_i;
            timer_irq_sync <= timer_irq_meta;
            manual_timer_meta <= manual_timer_i;
            manual_timer_sync <= manual_timer_meta;
            btn_any_meta <= btn_any;
            btn_any_sync <= btn_any_meta;
            sw13_meta <= sw_i[13];
            sw13_sync <= sw13_meta;

            if (manual_timer_sync == manual_timer_stable) begin
                manual_timer_debounce <= {DEBOUNCE_BITS{1'b0}};
            end else begin
                manual_timer_debounce <= manual_timer_debounce + {{(DEBOUNCE_BITS-1){1'b0}}, 1'b1};
                if (&manual_timer_debounce) begin
                    manual_timer_stable <= manual_timer_sync;
                    manual_timer_debounce <= {DEBOUNCE_BITS{1'b0}};
                end
            end

            if (btn_any_sync == btn_any_stable) begin
                btn_any_debounce <= {DEBOUNCE_BITS{1'b0}};
            end else begin
                btn_any_debounce <= btn_any_debounce + {{(DEBOUNCE_BITS-1){1'b0}}, 1'b1};
                if (&btn_any_debounce) begin
                    btn_any_stable <= btn_any_sync;
                    btn_any_debounce <= {DEBOUNCE_BITS{1'b0}};
                end
            end

            if (sw13_sync == sw13_stable) begin
                sw13_debounce <= {DEBOUNCE_BITS{1'b0}};
            end else begin
                sw13_debounce <= sw13_debounce + {{(DEBOUNCE_BITS-1){1'b0}}, 1'b1};
                if (&sw13_debounce) begin
                    sw13_stable <= sw13_sync;
                    sw13_debounce <= {DEBOUNCE_BITS{1'b0}};
                end
            end

            timer_irq_d <= timer_irq_sync;
            manual_timer_d <= manual_timer_stable;
            btn_any_d <= btn_any_stable;
            sw13_d <= sw13_stable;

            if (startup_guard != {(DEBOUNCE_BITS+1){1'b0}}) begin
                startup_guard <= startup_guard - {{DEBOUNCE_BITS{1'b0}}, 1'b1};
            end else begin
                if (!manual_timer_stable)
                    manual_timer_armed_low <= 1'b1;
                else if (manual_timer_event)
                    manual_timer_armed_low <= 1'b0;

                if (!btn_any_stable)
                    btn_any_armed_low <= 1'b1;
                else if (button_event)
                    btn_any_armed_low <= 1'b0;

                if (!sw13_stable)
                    sw13_armed_low <= 1'b1;
                else if (switch_event)
                    sw13_armed_low <= 1'b0;
            end

            if (button_event)
                button_holdoff <= {HOLDOFF_BITS{1'b1}};
            else if (button_holdoff != {HOLDOFF_BITS{1'b0}})
                button_holdoff <= button_holdoff - {{(HOLDOFF_BITS-1){1'b0}}, 1'b1};

            if (switch_event)
                switch_holdoff <= {HOLDOFF_BITS{1'b1}};
            else if (switch_holdoff != {HOLDOFF_BITS{1'b0}})
                switch_holdoff <= switch_holdoff - {{(HOLDOFF_BITS-1){1'b0}}, 1'b1};

            if (manual_timer_event)
                manual_holdoff <= {HOLDOFF_BITS{1'b1}};
            else if (manual_holdoff != {HOLDOFF_BITS{1'b0}})
                manual_holdoff <= manual_holdoff - {{(HOLDOFF_BITS-1){1'b0}}, 1'b1};
        end
    end

    wire [7:0] irq_active = irq_pending & irq_mask;

    assign irq_cause =
        irq_active[0] ? CAUSE_TIMER :
        irq_active[3] ? CAUSE_BUTTON :
        irq_active[4] ? CAUSE_SWITCH :
                        CAUSE_NONE;

    assign irq_valid = (irq_cause != CAUSE_NONE);
    assign irq_pending_o = irq_pending;
    assign irq_mask_o = irq_mask;

endmodule
