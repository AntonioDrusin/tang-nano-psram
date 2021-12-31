module old_mem_driver(
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

  reg [7:0] rout = 0;
  reg [3:0] counter = 0;
  reg [2:0] excommand = 0;
  reg [2:0] step = 0;
  reg [3:0] sio = 0;
  reg [23:0] mem_addr = 0;
  reg [15:0] data = 0;
  reg done = 0;
  reg reading = 0;

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
            step <= STEP_QPI_CMD; // Reads and writes are always sent in QPI mode.
            mem_addr <= addr;
          end
          CMD_WRITE: begin    
            rout <= PS_CMD_WRITE;
            step <= STEP_QPI_CMD; 
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
          done <= 1;
      end
      STEP_QPI_CMD: begin  // Only read and write are QPI        
        mem_ce_n <= 0;
        sio <= counter == 0 ? rout[7:4] : rout[3:0];
        if ( counter == 1 ) begin
          counter <= 0;
          step <= STEP_ADDR;                     
        end
      end
      STEP_ADDR: begin
        {sio, mem_addr[23:4]} <= mem_addr;        
        if ( counter == 5 ) begin
          counter <= 0;
          case (excommand)
            CMD_READ: step <= STEP_WAIT;
            CMD_WRITE: step <= STEP_WRITE;
          endcase
        end
      end
      STEP_WAIT: begin
        sio <= 4'bzzzz;
        if ( counter == 5 ) begin
          counter <= 0;
          step <= STEP_READ;
        end
      end
      STEP_WRITE: begin        
        {sio, data[15:4]} <= data;
        if ( counter[2] == 1 ) begin
          mem_ce_n <= 1;
          counter <= 0;
          step <= STEP_BRSTDLY;
        end
      end
      STEP_READ: begin
        reading <= 1;
        if ( counter[2] == 1 ) 
        begin
          mem_ce_n <= 1;
          reading <= 0;
          counter <= 0;
          step <= STEP_BRSTDLY;
        end
      end
      STEP_BRSTDLY: begin
        sio[3:0] <= 0;
        if ( counter[1] == 1 ) begin // 3 clocks at 120MHZ is >18ns required.
          done <= 1;
        end    
      end
    endcase

    if ( reading ) begin  
      data_out[15:0] = {data_out[11:0], sio[3:0]};      
    end

    if ( done ) begin 
      counter <= 0;
      step <= STEP_IDLE;
      mem_ce_n <= 1;
      sio[3:0] <= 0;
      ready <= 1;
      done <= 0;
    end
  end
    
endmodule
