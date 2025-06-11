`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: Dmitry Matyunin (https://github.com/mcjtag) – modified by shri (github.com/5iri)
//
// Description:
//   TCAM line array with optional per‑lookup X‑mask (req_xmask) and raw match vector
//   output.  Each entry stores {xmask,key} when MASK_DISABLE == 0, or just {key}
//   when MASK_DISABLE == 1.  The match logic supports don’t‑care bits coming from
//   either the stored mask OR the query mask.
//
// Revision History:
//   0.02 – 2025‑06‑11  Added req_xmask support, active flag fix, cleaned syntax.
//
//////////////////////////////////////////////////////////////////////////////////

module tcam_line_array #(
    parameter ADDR_WIDTH    = 8,   // log2(number of entries)
    parameter KEY_WIDTH     = 8,   // bits in a key
    parameter MASK_DISABLE  = 0    // 1 => store key only (binary CAM)
) (
    input  wire                        clk,
    input  wire                        rst,

    // ---------------- SET interface ----------------
    input  wire [ADDR_WIDTH-1:0]       set_addr,
    input  wire [KEY_WIDTH-1:0]        set_key,
    input  wire [KEY_WIDTH-1:0]        set_xmask,   // ignored if MASK_DISABLE
    input  wire                        set_clr,
    input  wire                        set_valid,

    // ---------------- LOOK‑UP interface ------------
    input  wire [KEY_WIDTH-1:0]        req_key,
    input  wire [KEY_WIDTH-1:0]        req_xmask,   // query‑side don’t‑care mask
    input  wire                        req_valid,

    // ---------------- RESULT ----------------------
    output wire [(1<<ADDR_WIDTH)-1:0]  line_match    // one‑hot vector
);

  // ---------------------------------------------------------------------------
  localparam ENTRIES    = (1 << ADDR_WIDTH);
  localparam MEM_WIDTH  = (MASK_DISABLE) ? KEY_WIDTH : KEY_WIDTH * 2;

  // Storage for every entry: {xmask,key} or {key}
  reg  [MEM_WIDTH-1:0]  mem   [0:ENTRIES-1];
  reg  [ENTRIES-1:0]    active;      // 1 => slot is valid
  reg  [ENTRIES-1:0]    match_r;     // registered match vector

  // Convenience wires sliced out of mem[]
  wire [KEY_WIDTH-1:0]  key   [0:ENTRIES-1];
  wire [KEY_WIDTH-1:0]  xmask [0:ENTRIES-1];

  genvar g;
  generate
    for (g = 0; g < ENTRIES; g = g + 1) begin : SLICE
      if (MASK_DISABLE) begin : NO_MASK
        assign key  [g] = mem[g][KEY_WIDTH-1:0];
        assign xmask[g] = {KEY_WIDTH{1'b0}};
      end else begin : WITH_MASK
        assign key  [g] = mem[g][KEY_WIDTH-1          : 0];
        assign xmask[g] = mem[g][KEY_WIDTH*2-1 : KEY_WIDTH];
      end
    end
  endgenerate

  assign line_match = match_r;  // expose registered result

  // ---------------------------------------------------------------------------
  // Reset memories (synthesis replaces with implicit reset for BRAMs)
  integer i;
  initial begin
    for (i = 0; i < ENTRIES; i = i + 1) begin
      mem[i]    = {MEM_WIDTH{1'b0}};
      active[i] = 1'b0;
    end
  end

  // ---------------- SET stage -------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      active <= {ENTRIES{1'b0}};
    end else if (set_valid) begin
      if (set_clr) begin
        active[set_addr] <= 1'b0;               // clear entry
      end else begin
        // write key / mask
        if (MASK_DISABLE) begin
          mem[set_addr] <= set_key;
        end else begin
          mem[set_addr] <= {set_xmask, set_key};
        end
        active[set_addr] <= 1'b1;               // mark entry active
      end
    end
  end

  // ---------------- LOOK‑UP stage --------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      match_r <= {ENTRIES{1'b0}};
    end else if (req_valid) begin
      for (i = 0; i < ENTRIES; i = i + 1) begin
        if (MASK_DISABLE) begin
          // Binary CAM compare (no masks)
          match_r[i] <= (key[i] == req_key) & active[i];
        end else begin
          // Ternary compare with dual masks
          match_r[i] <= active[i] &
                        ( ( (key[i] ^ req_key) &
                            ~(xmask[i] | req_xmask) ) == {KEY_WIDTH{1'b0}} );
        end
      end
    end
  end

endmodule
