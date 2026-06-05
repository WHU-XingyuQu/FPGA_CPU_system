`timescale 1ns / 1ps

module dm_controller(
    input         mem_w,
    input  [31:0] Addr_in,
    input  [31:0] Data_write,
    input  [2:0]  dm_ctrl,
    input  [31:0] Data_read_from_dm,
    output reg [31:0] Data_read,
    output reg [31:0] Data_write_to_dm,
    output reg [3:0]  wea_mem
);
    wire [7:0] load_byte =
        (Addr_in[1:0] == 2'b00) ? Data_read_from_dm[7:0] :
        (Addr_in[1:0] == 2'b01) ? Data_read_from_dm[15:8] :
        (Addr_in[1:0] == 2'b10) ? Data_read_from_dm[23:16] :
                                  Data_read_from_dm[31:24];

    wire [15:0] load_half = Addr_in[1] ? Data_read_from_dm[31:16] :
                                         Data_read_from_dm[15:0];
    wire        ram_write = mem_w && (Addr_in[31:12] == 20'h00000);

    always @(*) begin
        case (dm_ctrl)
            3'b001: Data_read = {{16{load_half[15]}}, load_half}; // lh
            3'b010: Data_read = {16'b0, load_half};               // lhu
            3'b011: Data_read = {{24{load_byte[7]}}, load_byte};  // lb
            3'b100: Data_read = {24'b0, load_byte};               // lbu
            default: Data_read = Data_read_from_dm;               // lw
        endcase
    end

    always @(*) begin
        Data_write_to_dm = Data_write;
        wea_mem = 4'b0000;

        if (ram_write) begin
            case (dm_ctrl)
                3'b001: begin // sh
                    if (Addr_in[1]) begin
                        Data_write_to_dm = {Data_write[15:0], 16'b0};
                        wea_mem = 4'b1100;
                    end else begin
                        Data_write_to_dm = {16'b0, Data_write[15:0]};
                        wea_mem = 4'b0011;
                    end
                end

                3'b011: begin // sb
                    case (Addr_in[1:0])
                        2'b00: begin
                            Data_write_to_dm = {24'b0, Data_write[7:0]};
                            wea_mem = 4'b0001;
                        end
                        2'b01: begin
                            Data_write_to_dm = {16'b0, Data_write[7:0], 8'b0};
                            wea_mem = 4'b0010;
                        end
                        2'b10: begin
                            Data_write_to_dm = {8'b0, Data_write[7:0], 16'b0};
                            wea_mem = 4'b0100;
                        end
                        default: begin
                            Data_write_to_dm = {Data_write[7:0], 24'b0};
                            wea_mem = 4'b1000;
                        end
                    endcase
                end

                default: begin // sw
                    Data_write_to_dm = Data_write;
                    wea_mem = 4'b1111;
                end
            endcase
        end
    end
endmodule
