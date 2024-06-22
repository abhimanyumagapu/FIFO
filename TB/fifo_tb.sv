class transaction;
  bit[7:0] w_data;
  rand bit winc, rinc; // random enable signals
  byte rd_data; // output
  bit wfull, rempty; //output
  int i;
  constraint oper{ winc dist{1:=100, 0:=0}; rinc dist{0:=0, 1:=100};} 
endclass

 //------------------------------------------------------

class generator;
  
  transaction tr;
  mailbox mbx_rd, mbx_w;
  
  int count;
  event next;
  event done;
  
  function new(mailbox mbx_rd, mbx_w);
    this.mbx_rd = mbx_rd;
    this.mbx_w = mbx_w;
	tr = new();
  endfunction
  
  task run();
    repeat(count) begin
      assert(tr.randomize) else $error(" Randomize failed");
      mbx_rd.put(tr);
      mbx_w.put(tr);
      $display("Generated - W_en=%b, R_en=%b, t=%t" ,tr.winc, tr.rinc, $time);
      @(next);
    end
    ->done;
  endtask
endclass

//------------------------------------------------------

class driver;
  transaction tr_w, tr_rd;
  mailbox mbx_rd, mbx_w;
  
  virtual fifo_if vif;
  event generated;
  event fin_read;
  
  function new(mailbox mbx_rd, mbx_w);    
    this.mbx_rd = mbx_rd;
    this.mbx_w = mbx_w;
  endfunction
  
  task reset();
    vif.w_rst = 0;
    vif.winc = 0;
	@(posedge vif.wclk);
    vif.r_rst = 0;
   	vif.rinc = 0;
    @(posedge vif.rclk);
    @(posedge vif.rclk);
    vif.w_rst = 1;
    vif.r_rst = 1;
    $display("DRV - Reset Done, Time = %t", $time);
    $display("------------------------------------------");
  endtask
   
  task write();
    forever begin
      mbx_w.get(tr_w);
      vif.winc = tr_w.winc;
      vif.w_data = $urandom_range(1, 300);
      $display("DRV : Written Data - %d, W_en = %b, Time = %t", vif.w_data, tr_w.winc, $time);
      @(posedge vif.wclk);
      -> generated;   
    end
  endtask
  
  task read();
    forever begin
      mbx_rd.get(tr_rd);
      vif.rinc = tr_rd.rinc;
      @(posedge vif.rclk);
      ->fin_read;
      $display("DRV : Rd_Data En = %b, Time = %t", tr_rd.rinc, $time);
    end
  endtask
 
  
  task run();
    fork 
      write();
      read();
    join_none
  endtask
endclass
    
//------------------------------------------------------

class monitor;
  
  transaction tr;
  mailbox mbx_w, mbx_rd;
  virtual fifo_if vif;
  event generated;
  event fin_read;
  
  function new(mailbox mbx_w, mailbox mbx_rd);
    this.mbx_w = mbx_w;
    this.mbx_rd = mbx_rd;
  endfunction
  
  task write_out();
    forever begin
      @(generated);
      tr = new();
      tr.winc = vif.winc;
      tr.w_data = vif.w_data;
      tr.wfull = vif.wfull;
      mbx_w.put(tr);
    end
  endtask
  
  task read_out();
    forever begin
      @(fin_read);
      tr = new();
      tr.rinc = vif.rinc;
      tr.rd_data = vif.rd_data;
      tr.rempty = vif.rempty;
      mbx_rd.put(tr);
    end
  endtask
  
  task run();
    tr = new();
    fork 
      write_out;
      read_out;
    join_none

  endtask

endclass
  

//------------------------------------------------------

class scoreboard;
  
  mailbox mbx_w, mbx_rd;
  transaction tr;
  event next;
  event generated;
  event fin_read;
  
  bit [7:0] din [$]; // dynamic array to hold data
  bit [7:0] temp;
  int error;
  bit first = 1;
  
  function new(mailbox mbx_w, mailbox mbx_rd);
    this.mbx_w = mbx_w;
    this.mbx_rd = mbx_rd;
  endfunction
  
  task wr();
    forever begin
        @(generated);
        mbx_w.get(tr);
        if(tr.winc) begin
          if(!tr.wfull) begin
            if(first == 1) first = 0;
            else din.push_front(tr.w_data);
            $display("Data in queue = %p, time = %t", din, $time);
          end else $display("FIFO is full");
        end
        ->next;
        $display("--------------Wr next-----------------");
    end
  endtask
  
  task rd();
    forever begin
      @(fin_read);
      mbx_rd.get(tr);
      if (tr.rinc) begin
        if (!tr.rempty) begin
          if (din.size() > 0) begin
            temp = din.pop_back();
            $display("Data in queue after pop = %p, time = %t", din, $time);
            if (temp == tr.rd_data) begin
              $display("match, Queue = %d, Rd_data = %d, time = %t", temp, tr.rd_data, $time);
            end else begin
              $display("mismatch: Expected %d, got %d, time = %t", temp, tr.rd_data, $time);
              error++;
            end
          end else begin
            $display("Error: Read operation attempted on empty queue");
            error++;
          end
        end else $display("FIFO is empty");
      end
      ->next;
      $display("--------------Rd next-----------------");
    end
  endtask
      
  
  task run();
    fork
      wr();
      rd();
    join_none
  endtask
  
endclass
          
//------------------------------------------------------

class environment;
  
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  virtual fifo_if vif;
  
  mailbox gdmbx_w, gdmbx_rd;
  mailbox msmbx_w, msmbx_rd;
  event next;
  event generated;
  event fin_read;
  
  function new(virtual fifo_if vif);
    gdmbx_w = new();
    gdmbx_rd = new();
    msmbx_w = new();
    msmbx_rd = new();
    gen = new(gdmbx_rd, gdmbx_w);
    mon = new(msmbx_w, msmbx_rd);
    drv = new(gdmbx_rd, gdmbx_w);
    sco = new(msmbx_w, msmbx_rd);
    this.vif = vif;
    drv.vif = vif;
    mon.vif = vif;
    gen.next = next;
    sco.next = next;
    drv.generated = generated;
    sco.generated = generated;
    mon.generated = generated;
    drv.fin_read = fin_read;
    sco.fin_read = fin_read;
    mon.fin_read = fin_read;
  endfunction
  
  task pre_test;
    drv.reset();
  endtask
  
  task test;
	fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  
  task post_test;
    wait(gen.done.triggered);
    $display("Error count = %d", sco.error);
    $finish;
  endtask
  
  task run();
    pre_test;
    test;
    post_test;
  endtask
  
endclass
   
//------------------------------------------------------

module tb;
  
  fifo_if vif();
  
  fifo t1(vif.rd_data, vif.wfull, vif.rempty, vif.w_data, vif.winc, vif.rinc, vif.wclk, vif.rclk, vif.w_rst, vif.r_rst);
  
  environment env;
  
  initial begin
    vif.rclk = 0;
    forever #22 vif.rclk = ~vif.rclk;
  end
  
  initial begin
    vif.wclk = 0;
    forever #10 vif.wclk = ~vif.wclk;
  end
  
  initial begin
    env = new(vif);
    env.gen.count = 15;
    env.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule 