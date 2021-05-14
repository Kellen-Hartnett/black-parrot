/**
 * bsg_serial_in_parallel_out_last.v
 *
 * This data structure takes in single word serial input and deserializes it
 * to multi-word data output. This module is helpful on both sides, both v_o
 * and ready_and_o are early.
 *
 * The last_i signal must be raised early with v_i when the last serial word
 * is available on the input.
 *
 * If max_els_p == 1 then this module simply passes through the signals.
 * Otherwise, the output becomes valid the cycle after the last serial word
 * arrives.
 *
 * This module expects max_els_p input words for every output produced.
 */

`include "bsg_defines.v"

module bsg_serial_in_parallel_out_last

 #(parameter width_p       = "inv"
  ,parameter max_els_p     = "inv"
  ,parameter lg_max_els_lp = `BSG_SAFE_CLOG2(max_els_p)
  )

  (input                               clk_i
  ,input                               reset_i

  ,input                               v_i
  ,input  [width_p-1:0]                data_i
  ,output                              ready_and_o
  ,input                               last_i

  ,output                              v_o
  ,output [max_els_p-1:0][width_p-1:0] data_o
  ,input                               ready_and_i
  );

  if (max_els_p == 1)
  begin : single_word

    assign v_o         = v_i;
    assign data_o      = data_i;
    assign ready_and_o = ready_and_i;
    wire unused        = last_i;

  end
  else
  begin : multi_word

    // data valid register
    // output data becomes available the cycle following the last input word
    bsg_dff_reset_set_clear
    #(.width_p(1)
      ,.clear_over_set_p(1)
      )
    data_valid_dff
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.set_i(v_i & ready_and_o & last_i)
      ,.clear_i(v_o & ready_and_i)
      ,.data_o(v_o)
      );

    // ready to receive data until last data arrives
    assign ready_and_o = ~v_o;

    // data_dff enable generation
    // start with enable on for word 0, shift to next word as each input word arrives
    // reset to initial mask when output sends
    logic [max_els_p-1:0] data_en_li;
    bsg_dff_reset_en
    #(.width_p(max_els_p)
      ,.reset_val_p(1)
      )
    data_en_dff
     (.clk_i(clk_i)
      ,.reset_i(reset_i | (v_o & ready_and_i))
      ,.en_i(v_i & ready_and_o)
      ,.data_i(data_en_li << 1)
      ,.data_o(data_en_li)
      );

    // Registered data words
    for (genvar i = 0; i < max_els_p; i++)
      begin: rof
        bsg_dff_en
       #(.width_p(width_p      )
        ) data_dff
        (.clk_i  (clk_i        )
        ,.data_i (data_i       )
        ,.en_i   (data_en_li[i])
        ,.data_o (data_o    [i])
        );
      end

  end

endmodule
