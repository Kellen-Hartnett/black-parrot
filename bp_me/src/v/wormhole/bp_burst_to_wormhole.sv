/**
 *
 * Name:
 *   bp_burst_to_wormhole.sv
 *
 * Description:
 *   Converts BedRock Burst protocol to wormhole router stream.
 *
 * Assumptions:
 *  Usage of this module requires correctly formed wormhole headers. The length
 *    field of the wormhole message determines how many protocol data beats are
 *    expected (some multiple or divisor of the flit_width). We expect most
 *    link and protocol data widths to be powers of 2 (32, 64, 512), so this
 *    length restriction is lenient.
 *
 *   - data width is a multiple of flit width (would be easy to add support)
 *   - header width is a multiple of flit width  (would be more challenging)
 *     - header width == wormhole header width + protocol header width
 *   - wormhole packets are laid out like the following:
 *   ---------------------------------------------------------------
 *   | data   | data  | data  | data  | protocol hdr  | len   cord |
 *   ---------------------------------------------------------------
 *   - header flits do not contain any data
 *
 *
 * Input Burst message has a single header beat and zero or more data beats.
 * This module does not accept data until the header sends
 *
 */

`include "bsg_defines.v"

module bp_burst_to_wormhole
 #(// The wormhole router protocol information
   // flit_width_p: number of physical data wires between links
   // cord_width_p: the width of the {y,x} coordinate of the destination
   // len_width_p : the width of the length field, denoting #flits+1
   // cid_width   : the width of the concentrator id of the destination
   // Default to 0 for cord and cid, so that this module can be used either
   //   for concentrator or router
   parameter flit_width_p      = "inv"
   , parameter cord_width_p    = 0
   , parameter len_width_p     = "inv"
   , parameter cid_width_p     = 0

   // Higher level protocol information
   , parameter pr_hdr_width_p  = "inv"
   , parameter pr_data_width_p = "inv"
   , parameter pr_len_width_p  = "inv"

   // Size of the wormhole header + the protocol header. The data starts afterwards.
   // Users may set this directly rather than relying on the protocol header derived default
   , parameter hdr_width_p = cord_width_p + len_width_p + cid_width_p + pr_hdr_width_p
   )
  (input                             clk_i
   , input                           reset_i

   // BedRock Burst input channel
   // ready&valid
   , input [hdr_width_p-1:0]         pr_hdr_i
   , input                           pr_hdr_v_i
   , output logic                    pr_hdr_ready_and_o
   , input                           pr_has_data_i

   , input [pr_data_width_p-1:0]     pr_data_i
   , input                           pr_data_v_i
   , output logic                    pr_data_ready_and_o
   , input                           pr_last_data_i

   // Wormhole output
   // ready&valid
   , output logic [flit_width_p-1:0] link_data_o
   , output logic                    link_v_o
   , input                           link_ready_and_i
   );

  wire is_hdr, is_data, wh_has_data, wh_last_data;

  localparam [len_width_p-1:0] hdr_len_lp = `BSG_CDIV(hdr_width_p, flit_width_p);

  logic [flit_width_p-1:0] hdr_lo;
  logic hdr_v_lo, hdr_ready_and_li;
  logic hdr_v_li, hdr_ready_and_lo;
  assign hdr_v_li = is_hdr & pr_hdr_v_i;
  assign pr_hdr_ready_and_o = is_hdr & hdr_ready_and_lo;

  // Header is input all at once and streamed out 1 flit at a time
  bsg_parallel_in_serial_out_passthrough
   #(.width_p(flit_width_p)
     ,.els_p(hdr_len_lp)
     )
   hdr_piso
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(pr_hdr_i)
     ,.v_i(hdr_v_li)
     ,.ready_and_o(hdr_ready_and_lo)

     ,.data_o(hdr_lo)
     ,.v_o(hdr_v_lo)
     ,.ready_and_i(hdr_ready_and_li)
     );
  assign hdr_ready_and_li = is_hdr & link_ready_and_i;

  logic [flit_width_p-1:0] data_lo;
  logic data_v_lo, data_ready_and_li;
  logic data_v_li, data_ready_and_lo;
  assign pr_data_ready_and_o = is_data & data_ready_and_lo;
  assign data_v_li = is_data & pr_data_v_i;

  // Protocol data is 1 or multiple flit-sized. We accept a large protocol data
  //   and then stream out 1 flit at a time
  if (pr_data_width_p >= flit_width_p)
    begin : wide
      localparam [len_width_p-1:0] data_len_lp = `BSG_CDIV(pr_data_width_p, flit_width_p);
      bsg_parallel_in_serial_out_passthrough
       #(.width_p(flit_width_p)
         ,.els_p(data_len_lp)
         )
       data_piso
        (.clk_i(clk_i)
         ,.reset_i(reset_i)

         ,.data_i(pr_data_i)
         ,.v_i(data_v_li)
         ,.ready_and_o(data_ready_and_lo)

         ,.data_o(data_lo)
         ,.v_o(data_v_lo)
         ,.ready_and_i(data_ready_and_li)
         );
    end
    wire unused = pr_last_data_i;
  else
    // Protocol data is less than a single flit-sized. We accept a small
    //   protocol data, aggregate it, and then send it out on the wormhole network
    begin : narrow
      // flit_width_p > pr_data_width_p -> multiple protocol data per link flit
      // and the protocol data may not completely fill the SIPO.

      bsg_serial_in_parallel_out_passthrough_dynamic_last
       #(.width_p(pr_data_width_p)
         ,.max_els_p(max_els_lp)
         )
       data_sipo
        (.clk_i(clk_i)
         ,.reset_i(reset_i)

         ,.data_i(pr_data_i)
         ,.v_i(data_v_li)
         ,.ready_and_o(data_ready_and_lo)
         ,.last_i(pr_last_data_i)

         //,.first_o(sipo_first_lo)

         // len_i must be valid when v_i & first_o
         //,.len_i(sipo_len_li)

         ,.data_o(data_lo)
         ,.v_o(data_v_lo)
         ,.ready_and_i(data_ready_and_li)
         );
    end

  assign data_ready_and_li = is_data & link_ready_and_i;

  // Identifies which flits are header vs data flits
  bsg_wormhole_stream_control
   #(.len_width_p(len_width_p)
     ,.hdr_len_p(hdr_len_lp)
     )
   stream_control
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.len_i(hdr_lo[cord_width_p+:len_width_p])
     ,.link_accept_i(link_ready_and_i & link_v_o)

     ,.is_hdr_o(is_hdr)
     ,.has_data_o(wh_has_data)
     ,.is_data_o(is_data)
     ,.last_data_o(wh_last_data)
     );

  assign link_data_o = is_hdr ? hdr_lo   : data_lo;
  assign link_v_o    = is_hdr ? hdr_v_lo : data_v_lo;

  //synopsys translate_off
  if (hdr_width_p % flit_width_p != 0)
    $fatal("Header width: %d must be multiple of flit width: %d", hdr_width_p, flit_width_p);

  if ((pr_data_width_p % flit_width_p != 0) && (flit_width_p % pr_data_width_p != 0))
    $fatal("Protocol data width: %d must be multiple of flit width: %d", pr_data_width_p, flit_width_p);
  //synopsys translate_on

endmodule

