`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: Dmitry Matyunin (https://github.com/mcjtag) – modified by shri (github.com/5iri)
//
// Description:
//   Top‑level TCAM wrapper.
//   • Adds per‑lookup mask input  (req_xmask)
//   • Exposes raw one‑hot match bus (res_match_vec) instead of priority‑encoded address
//   • Keeps original address/data outputs for backward compatibility.
//
//////////////////////////////////////////////////////////////////////////////////

module tcam #(
    parameter ADDR_WIDTH = 4,
    parameter KEY_WIDTH  = 4,
    parameter DATA_WIDTH = 4,
    parameter MASK_DISABLE   = 0,
    parameter RAM_STYLE_DATA = "block"
) (
    input  wire                       clk,
    input  wire                       rst,
    // ---------------- SET ----------------
    input  wire [ADDR_WIDTH-1:0]      set_addr,
    input  wire [DATA_WIDTH-1:0]      set_data,
    input  wire [KEY_WIDTH-1:0]       set_key,
    input  wire [KEY_WIDTH-1:0]       set_xmask,
    input  wire                       set_clr,
    input  wire                       set_valid,
    // ---------------- LOOK‑UP ------------
    input  wire [KEY_WIDTH-1:0]       req_key,
    input  wire [KEY_WIDTH-1:0]       req_xmask,   // NEW – per‑lookup don’t‑care mask
    input  wire                       req_valid,
    output wire                       req_ready,
    // ---------------- RESPONSE ----------
    output wire [ADDR_WIDTH-1:0]      res_addr,
    output wire [DATA_WIDTH-1:0]      res_data,
    output wire                       res_valid,
    output wire                       res_null,
    output wire [(1<<ADDR_WIDTH)-1:0] res_match_vec // NEW – raw one‑hot match vector
);

// -----------------------------------------------------------------------------
// Handshake & pipeline registers
// -----------------------------------------------------------------------------
reg line_valid_r;
wire [(1<<ADDR_WIDTH)-1:0] line_match;

assign req_ready = (rst) ? 1'b0 : (~line_valid_r);
assign res_match_vec = line_match;        // pass immediately; assert when res_valid

// delay for latency matching (3‑cycle pipeline in original design)
reg [ADDR_WIDTH-1:0] res_addr_r;
reg                  res_null_r;
reg                  res_valid_r;
assign res_addr  = res_addr_r;
assign res_valid = res_valid_r;
assign res_null  = res_null_r;

// -----------------------------------------------------------------------------
// Instance: line array (associative compare)
// -----------------------------------------------------------------------------
tcam_line_array #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .KEY_WIDTH    (KEY_WIDTH),
    .MASK_DISABLE (MASK_DISABLE)
) u_line_array (
    .clk      (clk),
    .rst      (rst),
    // set port
    .set_addr (set_addr),
    .set_key  (set_key),
    .set_xmask(set_xmask),
    .set_clr  (set_clr),
    .set_valid(set_valid),
    // request port
    .req_key  (req_key),
    .req_xmask(req_xmask),   // <‑‑‑ connected!
    .req_valid(req_valid & req_ready),
    // result
    .line_match(line_match)
);

// -----------------------------------------------------------------------------
// Optional priority encoder (kept for compatibility)
// -----------------------------------------------------------------------------
wire [ADDR_WIDTH-1:0] enc_addr;
wire                  enc_valid;
wire                  enc_null;

tcam_line_encoder #(
    .ADDR_WIDTH (ADDR_WIDTH)
) u_encoder (
    .clk        (clk),
    .rst        (rst),
    .line_match (line_match),
    .line_valid (line_valid_r),
    .addr       (enc_addr),
    .addr_valid (enc_valid),
    .addr_null  (enc_null)
);

// -----------------------------------------------------------------------------
// Data RAM (unchanged)
// -----------------------------------------------------------------------------
tcam_sdpram #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .RAM_STYLE  (RAM_STYLE_DATA)
) u_data_ram (
    .clk    (clk),
    .rst    (rst),
    .dina   (set_data),
    .addra  (set_addr),
    .addrb  (enc_addr),
    .wea    (set_valid),
    .doutb  (res_data)
);

// -----------------------------------------------------------------------------
// Pipeline regs to align outputs (1‑cycle each stage: compare → encode → read)
// -----------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        line_valid_r <= 1'b0;
        res_valid_r  <= 1'b0;
        res_null_r   <= 1'b0;
        res_addr_r   <= '0;
    end else begin
        line_valid_r <= req_valid & req_ready;  // stage‑0
        res_valid_r  <= enc_valid;              // stage‑2 (after encoder)
        res_null_r   <= enc_null;
        res_addr_r   <= enc_addr;
    end
end

endmodule
