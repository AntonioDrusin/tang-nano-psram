// When clk > 84MHz all reads will not access across 1024byte boundary.
// Maximum tCEM low is 8us, so at 120MHz you cannot read more than 120x8 960 - 8(command) - 6 wait - 6 address = 938 nibbles
// The module will hold ready low for an extra 2 clock cycles to respect tCPH of 18ns (CE# high between subsequent burst operations), this can be optimized out if the clock is low.

// define QPI to use the shorter command sequence.
`define QPI

module memory (
  input button0,
  input clk,
  
  output reg out_ready,             // does not listen to commands when low.

  input [23:0] addr,
  input read_strb,
  output [15:0] data_out,
  input write_strb,
  input[15:0] data_in,

  // configuration
  input [15:0] mem_150us_clock_count, // The min number of mem_clk to reach a 150us delay.

  // These are connected to the mem chip. Pinout is for Sipeed TANG Nano
  inout wire [3:0] mem_sio,   // sio[0] pin 22, sio[1] pin 23, sio[2] pin 24, sio[3] pin 21
  output wire mem_ce_n,       // pin 19
  output wire mem_clk         // pin 20
);
 
    
  
  localparam [2:0] STEP_DELAY = 0;  
  localparam [2:0] STEP_RSTEN = 1;
  localparam [2:0] STEP_RST = 2;
  localparam [2:0] STEP_SPI2QPI = 3;
  localparam [2:0] STEP_IDLE = 4;

  reg [15:0] counter;
  
  reg [2:0] command;
  reg [7:0] mem_command;
  reg [2:0] step;
  reg ready;
  wire mem_ready;
  reg initialized = 0;  
 
  assign mem_clk = ~clk;

  mem_driver mem_driver(
    mem_sio,
    mem_ce_n,
    clk,
    command,
    mem_command,
    addr,
    data_out,
    data_in,
    mem_ready
  );

  always_ff @(posedge clk) begin
    if ( mem_ready )
    begin
      if ( initialized ) 
      begin
        if ( read_strb ) begin
          command <= mem_driver.CMD_READ;
          ready <= 0;
        end
        if ( write_strb ) begin
          command <= mem_driver.CMD_WRITE;
          ready <= 0;
        end
        if ( !read_strb && !write_strb ) ready <= 1;
      end
      else    
        case (step)
          STEP_DELAY: begin 
            // datasheet requires a 150us delay before sending the reset upon power up            
            counter <= counter + 1'd1;
            if ( counter == mem_150us_clock_count ) begin
              step <= STEP_RSTEN;
            end
          end
          STEP_RSTEN: begin                    
            // RSTEN followed by RST. This sequence is required in the datasheet      
            // But the chip seems functional without it. Removing the RSTEN+RST steps can
            // be a way to recover some LUTs
            command <= mem_driver.CMD_CMD;
            mem_command <= mem_driver.PS_CMD_RSTEN;
            step <= STEP_RST;
          end
          STEP_RST: begin
            command <= mem_driver.CMD_CMD;
            mem_command <= mem_driver.PS_CMD_RST;
`ifdef QPI
            step <= STEP_SPI2QPI;
`else
            step <= STEP_IDLE;
`endif
          end      
`ifdef QPI
          STEP_SPI2QPI: begin
            // Switch to QPI commands, this saves 6 clocks per read/write     
            // But if you do not need the speed, should not use QPI at all for the Tang Nano
            // The FPGA is just too small.
            command <= mem_driver.CMD_CMD;
            mem_command <= mem_driver.PS_CMD_QPI;
            step <= STEP_IDLE;            
          end
`endif
          STEP_IDLE: begin
            initialized <= 1;            
            command <= 0; 
          end
        endcase
    end
    else  
      command <= 0;
  end

  assign out_ready = mem_ready && ready && initialized && !read_strb && !write_strb;
endmodule

module mem_driver(
  inout wire [3:0] mem_sio,
  output reg mem_ce_n,
  input clk,
  input [2:0] command,
  input [7:0] mem_command,
  input [23:0] addr,
  output reg [15:0] data_out,
  input [15:0] data_in,
  output reg ready
);

  localparam [2:0] CMD_READ    = 3'b011;
  localparam [2:0] CMD_WRITE   = 3'b010;
  localparam [2:0] CMD_CMD     = 3'b100;

  localparam [7:0] PS_CMD_READ  = 8'hEB;
  localparam [7:0] PS_CMD_WRITE = 8'h38;
  localparam [7:0] PS_CMD_RSTEN = 8'h66;
  localparam [7:0] PS_CMD_RST   = 8'h99;
  localparam [7:0] PS_CMD_QPI   = 8'h35;
  
  localparam [2:0] STEP_IDLE    = 0;
  localparam [2:0] STEP_SPI_CMD = 1;
  localparam [2:0] STEP_QPI_CMD = 2; 
  localparam [2:0] STEP_ADDR    = 3; 
  localparam [2:0] STEP_WAIT    = 4; 
  localparam [2:0] STEP_READ    = 5; 
  localparam [2:0] STEP_WRITE   = 6; 
  localparam [2:0] STEP_BRSTDLY = 7; 

  reg [7:0] rout;
  reg [4:0] counter;
  reg [2:0] excommand;
  reg [2:0] step;
  reg [3:0] sio;
  reg [23:0] mem_addr;
  reg [15:0] data;
  reg next_step;
  reg done;
  reg reading;

  assign mem_sio = sio;
  
  initial begin
    mem_ce_n <= 1;
    ready <= 1;
  end

  always_ff @(posedge clk) begin
    if ( step == STEP_IDLE  ) begin
      if ( command != 0) begin
        excommand = command;
        ready <= 0;
        case ( excommand ) 
          CMD_READ: begin 
            rout <= PS_CMD_READ;
`ifdef QPI
            step <= STEP_QPI_CMD; // Reads and writes are always sent in QPI mode.
`else
            step <= STEP_SPI_CMD; 
`endif
            mem_addr <= addr;
          end
          CMD_WRITE: begin    
            rout <= PS_CMD_WRITE;
`ifdef QPI
            step <= STEP_QPI_CMD; 
`else
            step <= STEP_SPI_CMD; 
`endif
            mem_addr <= addr;
            data <= data_in;
          end
          CMD_CMD: begin  
            rout <= mem_command;
            step <= STEP_SPI_CMD;
          end
        endcase
      end
    end
    else counter <= counter + 1'd1;
    
    case (step)
      STEP_SPI_CMD: begin        
        mem_ce_n <= 0;
        {sio[0], rout[7:1]} <= rout;
        sio[3:1] <= 3'bzzz;
        if ( counter == 7 )
`ifdef QPI
          done <= 1;
`else
          if ( excommand == CMD_READ || excommand == CMD_WRITE ) begin
            next_step = 1;          
            step <= STEP_ADDR;      
          end
          else
            done <= 1;
`endif
      end
`ifdef QPI
      STEP_QPI_CMD: begin  // Only read and write are QPI        
        mem_ce_n <= 0;
        sio <= counter == 0 ? rout[7:4] : rout[3:0];
        if ( counter == 1 ) begin
          next_step = 1;          
          step <= STEP_ADDR;                     
        end
      end
`endif
      STEP_ADDR: begin
        {sio, mem_addr[23:4]} <= mem_addr;        
        if ( counter == 5 ) begin
          next_step = 1;
          case (excommand)
            CMD_READ: step <= STEP_WAIT;
            CMD_WRITE: step <= STEP_WRITE;
          endcase
        end
      end
      STEP_WAIT: begin
        sio <= 4'bzzzz;
        if ( counter == 5 ) begin
          next_step = 1;
          step <= STEP_READ;
        end
      end
      STEP_WRITE: begin        
        {sio, data[15:4]} <= data;
        if ( counter == 4 ) begin
          mem_ce_n <= 1;
          next_step = 1;
          step <= STEP_BRSTDLY;
        end
      end
      STEP_READ: begin
        if ( counter == 1 )
          reading <= 1;
        if ( counter == 4 ) 
          mem_ce_n <= 1;
        if ( counter == 5 ) begin
          reading <= 0;
          next_step = 1;
          step <= STEP_BRSTDLY;      
        end
      end
      STEP_BRSTDLY: begin
        sio[3:0] <= 0;
        if ( counter == 2 ) begin // 3 clocks at 120MHZ is >18ns required.
          done <= 1;
        end    
      end
    endcase

    if ( reading ) begin  
      data_out[15:0] = {data_out[11:0], sio[3:0]};      
    end

    if (next_step || done) begin
      counter <= 0;
      next_step = 0;
    end

    if ( done ) begin 
      step <= STEP_IDLE;
      mem_ce_n <= 1;
      sio[3:0] <= 0;
      ready <= 1;
      done <= 0;
    end
  end
    
endmodule


