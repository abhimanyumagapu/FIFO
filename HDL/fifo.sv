

module fifo#(parameter Dsize = 8, parameter Adsize = 4)(rd_data, wfull, rempty, w_data, winc, rinc, wclk, rclk, w_rst, r_rst);

  output [Dsize - 1 : 0] rd_data;
  output wfull, rempty;
  input [Dsize - 1 : 0] w_data;
  input winc, rinc, wclk, rclk, w_rst, r_rst;

  wire [Adsize - 1:0] r_addr, wr_addr;
  wire [Adsize : 0] r_ptr, wr_ptr, wr_syncptr, r_syncptr;
  wire w_full;
  assign wfull = w_full;
  sync_r2w #(Adsize) sync1(r_ptr, r_syncptr, wclk, w_rst);
  sync_w2r #(Adsize) sync2(wr_ptr, wr_syncptr, rclk, r_rst);
  fifomem #(Dsize, Adsize) mm1(rd_data, w_data, winc, wclk, wr_addr, r_addr, w_full);
  rd_ptr_empty #(Adsize) rp(r_ptr, wr_syncptr, r_addr, rempty, rinc, r_rst, rclk);
  wr_ptr_full #(Adsize) wp(wr_ptr, r_syncptr, wr_addr, w_full, winc, w_rst, wclk);

endmodule

module fifomem #(parameter DATASIZE = 8, parameter ADDRSIZE = 4)(rddata, wrdata, wren, wrclk, wraddr, rdaddr, wfull);

    // fifo memory
    input [DATASIZE - 1 : 0] wrdata;
    input [ADDRSIZE - 1 : 0] rdaddr, wraddr; 
    input wren, wrclk, wfull;
    output [DATASIZE - 1 : 0] rddata;

    localparam depth = 1<<ADDRSIZE; // depth of fifo = 2^addrsize
    reg [DATASIZE - 1 : 0] mem [ADDRSIZE - 1 : 0];

    assign rddata = mem[rdaddr];

  always @(posedge wrclk) begin
      if(wren && ~wfull)
        mem[wraddr] <= wrdata;
  end
  
endmodule

module sync_w2r #(parameter ADDRSIZE = 4)(wrptr, wrptr_sync, rdclk, rrst);

  input [ADDRSIZE : 0] wrptr; // extra bit for check
  output reg [ADDRSIZE : 0] wrptr_sync; 
  input rdclk, rrst;

  reg [ADDRSIZE:0] temp_ptr;

  always @(posedge rdclk) begin
    if(!rrst) begin
        temp_ptr <=0;
        wrptr_sync <=0;
    end
    else begin
        temp_ptr <= wrptr;
        wrptr_sync <= temp_ptr; // two flip flop synchroniser
    end
  end

endmodule

module sync_r2w #(parameter ADDRSIZE = 4)(rdptr, rdptr_sync, wrclk, wrrst);

  input [ADDRSIZE : 0] rdptr; // extra bit for checl
  output reg[ADDRSIZE : 0] rdptr_sync;
  input wrclk, wrrst;
  reg [ADDRSIZE:0] temp_ptr;

  always @(posedge wrclk) begin
    if(!wrrst) begin
        temp_ptr <=0;
        rdptr_sync <=0;
    end
    else begin
        temp_ptr <= rdptr;
        rdptr_sync <= temp_ptr; // two flip flop synchroniser
    end
  end

endmodule

module rd_ptr_empty #(parameter ADDRSIZE = 4)(rdptr, wr_syncptr, rdaddr, rempty, rinc, rrst, rclk);

  output reg [ADDRSIZE : 0] rdptr;
  output [ADDRSIZE - 1:0] rdaddr;
  output reg rempty;
  input rinc, rrst, rclk;
  input [ADDRSIZE : 0] wr_syncptr;

  wire r_empty;

  wire [ADDRSIZE : 0] rbinnext, rgraynext;
  reg [ADDRSIZE :0] rbin;

  always @(posedge rclk)begin
    if(!rrst) 
      {rbin, rdptr} <= 0;
    else
      {rbin, rdptr} <= {rbinnext, rgraynext}; // incrementing pointers
  end

  assign rdaddr = rbin[ADDRSIZE - 1: 0];

  assign rbinnext = rbin + (rinc && ~rempty); 
  assign rgraynext = (rbinnext >> 1) ^ rbinnext; // binary to gray code

  assign r_empty = (rgraynext == wr_syncptr); 

  always @(posedge rclk)begin
    if(!rrst)
      rempty <= 0;
    else begin
      if(rgraynext != 0)
        rempty = r_empty;
    end
  end

endmodule

module wr_ptr_full #(parameter ADDRSIZE = 4)(wrptr, rd_syncptr, wraddr, wrfull, wrrinc, wrrst, wrclk);

  output reg [ADDRSIZE : 0] wrptr;
  output [ADDRSIZE - 1:0] wraddr;
  output reg wrfull;
  input wrrinc, wrrst, wrclk;
  input [ADDRSIZE : 0] rd_syncptr;

  wire wr_full;

  wire [ADDRSIZE : 0] wrbinnext, wrgraynext;
  reg [ADDRSIZE :0] wrbin;

  always @(posedge wrclk)begin
    if(!wrrst) 
      {wrbin, wrptr} <= 0;
    else
      {wrbin, wrptr} <= {wrbinnext, wrgraynext};
  end

  assign wraddr = wrbin[ADDRSIZE - 1: 0];

  assign wrbinnext = wrbin + (wrrinc && ~wr_full);
  assign wrgraynext = (wrbinnext >> 1) ^ wrbinnext;

  assign wr_full = (wrgraynext == {~rd_syncptr[ADDRSIZE: ADDRSIZE-1], rd_syncptr[ADDRSIZE-2 : 0]});

  always @(posedge wrclk)begin
    if(!wrrst)
      wrfull <= 0;
    else
      wrfull <= wr_full;
  end

endmodule

interface fifo_if #(parameter Dsize = 8, parameter Adsize = 4);

  logic [Dsize - 1:0] rd_data;
  logic wfull, rempty;

  logic [Dsize - 1:0] w_data;
  logic winc, rinc, wclk, rclk, w_rst, r_rst;


endinterface