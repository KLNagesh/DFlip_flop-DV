module dff(input rst,clk,din, output reg dout);
	always@(posedge clk)begin
	if(rst)
		dout<=1'b0;
	else
		dout<=din;
	end
endmodule

//--------------TRANSACTION-----------------
class transaction;
	randc bit din;
	bit dout;
	function transaction copy();
		copy = new();
		copy.din = this.din;
		copy.dout = this.dout;
	endfunction
	
	function void display(input string tag);
		$display("[%0s] : DIN : %0b :DOUT : %0b",tag,din,dout);
	endfunction
endclass
//---------------GENERATOR---------------------
class generator;
	mailbox #(transaction) mbx;
	mailbox #(transaction) mbxref;
	transaction t;
	event sconext,next;
	event done;
	int count;
	
	function new(mailbox #(transaction) mbx ,mailbox #(transaction) mbxref);
		this.mbx = mbx;
		this.mbxref = mbxref;
		t = new();
	endfunction
	
	task run();
		repeat(count) begin
			assert(t.randomize()) else $error("RANDMIZATION IS FAILED");
			mbx.put(t.copy());
			mbxref.put(t.copy());
			$display("GENERATED IS GENERATED OUTPUT");
			#2;
			@(next);
			@(sconext);
			end
		->done;
	endtask
endclass
//----------------INTERFACE---------------
interface dff_if;
	logic clk,rst,din,dout;
endinterface
//------------DRIVER---------------------
class driver;
	transaction t;
	virtual dff_if aif;
	mailbox #(transaction) mbx;
	event next;
	function new(mailbox #(transaction) mbx);
		this.mbx = mbx;
	endfunction
	
	task reset();
		aif.rst<=1;
		repeat(2) @(posedge aif.clk);
		aif.rst <=0;
		$display("RESET IS DONE");
	endtask
	
	task run();
		forever begin
		mbx.get(t);
		aif.din = t.din;
		@(posedge aif.clk);		
		$display("[DRV] : APPILED DIN = %0b ",t.din);
		->next;
		end
	endtask
endclass
//--------------MONITOR----------------------
class monitor;
	transaction t;
	mailbox #(transaction) mbx;
	virtual dff_if aif;
	
	function new(mailbox #(transaction) mbx);
		this.mbx = mbx;
		t = new();
	endfunction
	
	task run();
		forever begin
			t.din = aif.din;
			repeat(2) @(posedge aif.clk);
			t.dout = aif.dout;
			mbx.put(t);
			t.display("MON");
		end
	endtask
endclass
//--------------SCOREBOARD--------------------
class scoreboard;
	transaction t;
	transaction tr;
	transaction tr_prev;
	mailbox #(transaction) mbx;
	mailbox #(transaction) mbxref;
	event sconext;
	
	function new(mailbox #(transaction) mbx ,mailbox #(transaction) mbxref);
		this.mbx = mbx;
		this.mbxref = mbxref;
		tr_prev = new();
		tr_prev.din = 0;
		tr_prev.dout = 0;
	endfunction
	
	task run();
		forever begin
			mbx.get(t);
			mbx.get(tr);
			
			$display("[SCO] : DIN :%0b : DOUT : %0b",t.din,t.dout);
			$display("[REF] : DIN : %0b" ,tr_prev.din);
			if(t.dout == tr_prev.din)
				$display("DATA MATCHED");
			else
				$display("DATA DOESN'T MATCHED");
			$display("--------------------------------");
			tr_prev = tr;
			->sconext;
		end
	endtask
endclass
//----------------ENVIRONMENT----------------------	
class environment;
generator gen;
driver drv;
monitor mon;
scoreboard sco;

mailbox #(transaction) gdmbx;
mailbox #(transaction) msmbx;
mailbox #(transaction) mbxref;

virtual dff_if aif;
	function new(virtual dff_if aif);
		this.aif = aif;
		gdmbx = new();
		msmbx = new();
		mbxref = new();
		
		gen = new(gdmbx,mbxref);
		drv = new(gdmbx);
		mon = new(msmbx);
		sco = new(msmbx,mbxref);
		
		gen.sconext = sco.sconext;
		gen.next = drv.next;
		drv.aif = aif;
		mon.aif = aif;
	endfunction
	task pre_test();
		drv.reset();
	endtask
	task test();
		fork 
			gen.run();
			drv.run();
			mon.run();
			sco.run();
		join_any
	endtask
	
	task post_test();
		wait(gen.done.triggered)
		$finish();
	endtask
	task run();
		pre_test();
		test();
		post_test();
	endtask
endclass
//---------- TESTBENCH------------------------
module tb;

dff_if aif();
dff dut(.rst(aif.rst),.clk(aif.clk),.din(aif.din),.dout(aif.dout));
environment env;
	initial begin
		aif.clk = 0;
	end
	always #10 aif.clk = ~aif.clk;
	initial begin
		env = new(aif);
		env.gen.count = 12;
		env.run();
	end
	initial begin
		$dumpfile("dump.vcd");
		$dumpvars;
	end
endmodule
