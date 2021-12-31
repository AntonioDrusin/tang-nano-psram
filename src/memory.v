// When clk > 84MHz all reads will not access across 1024byte boundary.
// Maximum tCEM low is 8us, so at 120MHz you cannot read more than 120x8 960 - 8(command) - 6 wait - 6 address = 938 nibbles
// The module will hold ready low for an extra 2 clock cycles to respect tCPH of 18ns (CE# high between subsequent burst operations), this can be optimized out if the clock is low.
module memory (
  input button0,
  input clk,
  
  output reg out_ready,             // does not listen to commands when low.

  input [23:0] addr,
  input read_strobe,
  output [15:0] data_out,
  input write_strobe,
  input[15:0] data_in,

  // configuration
  input [7:0] mem_150us_clock_count, // The min number of mem_clk to reach a 150us delay.

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

  reg [15:0] counter = 0; 
  reg [2:0] step = 0;
  reg initialized = 0;  

//  reg clk;
//  always_ff @(posedge fast_clk) begin
//    clk <= ~clk;
//  end
//  assign clk = fast_clk;
  assign mem_clk = ~clk;
  wire driver_ce_n;
  wire [3:0] driver_sio_out;  
  wire driver_ready;
  wire driver_sio_outputen;

  mem_driver mem_driver(
    clk,
    read_strobe,
    write_strobe,
    addr,
    data_out,
    data_in,
    driver_ready,

    mem_sio,
    driver_sio_out,
    driver_sio_outputen,

    driver_ce_n
  );

  wire command_ce_n;
  reg command_strobe = 0;
  reg [7:0] command;

  spi_command spi_command(
    clk,
    command,
    command_strobe,
    command_ready,
    command_line,
    command_ce_n
  );

  reg initializing = 0;
  always_ff @(posedge clk) begin
    if ( !initialized ) 
      if ( command_ready && !command_strobe) 
        case (step)
          STEP_DELAY: begin 
            // datasheet requires a 150us delay before sending the reset upon power up                        
            if( !button0 ) counter <= counter + 1'd1;
            if ( counter[15:8] == mem_150us_clock_count ) begin            
              initializing <= 1;
              step <= STEP_RSTEN;
            end
          end
          STEP_RSTEN: begin                    
            // RSTEN followed by RST. This sequence is required in the datasheet      
            // But the chip seems functional without it. Removing the RSTEN+RST steps can
            // be a way to recover some LUTs
            command <= spi_command.PS_CMD_RSTEN;
            command_strobe <= 1;
            step <= STEP_RST;
          end
          STEP_RST: begin
            command <= spi_command.PS_CMD_RST;
            command_strobe <= 1;
            step <= STEP_SPI2QPI;
          end      
          STEP_SPI2QPI: begin
            // Switch to QPI commands, this saves 6 clocks per read/write     
            // But if you do not need the speed, should not use QPI at all for the Tang Nano
            // The FPGA is just too small.
            command <= spi_command.PS_CMD_QPI;
            command_strobe <= 1;
            step <= STEP_IDLE;
          end
          STEP_IDLE: begin
            initialized <= 1;
          end
        endcase
    if ( command_strobe ) command_strobe <= 0;      
  end
  
  assign out_ready = initialized && driver_ready;
  assign mem_ce_n = command_ce_n && driver_ce_n;
  assign mem_sio = command_ce_n 
    ? (driver_sio_outputen ? driver_sio_out : 4'hZ ) 
    : ({ 3'bzzz, command_line });  
endmodule

module mem_driver(
  input clk,
  input read_strobe,
  input write_strobe,
  input [23:0] addr,
  output reg [15:0] data_out,
  input [15:0] data_in,
  output reg ready,

  input wire [3:0] mem_sio_in,
  output reg [3:0] mem_sio_out,
  output reg mem_sio_outputen,
  output reg mem_ce_n
);
  localparam [7:0] PS_CMD_READ  = 8'hEB;
  localparam [7:0] PS_CMD_WRITE = 8'h38;
  
  reg [3:0] sio_out = 0;
  reg reading = 0;
  reg writing = 0;
  reg [4:0] counter = 0; 
  reg [15:0] data_write;

  initial mem_ce_n = 1;  
  assign ready = !reading && !writing && mem_ce_n;  

  always_ff @(posedge clk) begin    
    if ( ready ) begin      
      if ( read_strobe ) begin
        reading <= 1; 
        counter <= 0;
      end
      else if ( write_strobe ) begin
        writing <= 1;
        counter <= 0;
        data_write <= data_in;
      end
    end
    else begin
      counter <= counter + 1'd1;
      case (counter) 
        0: begin 
              mem_ce_n <= 0;
              mem_sio_outputen <= 1;
              mem_sio_out <= reading ? PS_CMD_READ[7:4] : PS_CMD_WRITE[7:4];
           end
        1: mem_sio_out <= reading ? PS_CMD_READ[3:0] : PS_CMD_WRITE[3:0];
        2: mem_sio_out <= addr[23:20];
        3: mem_sio_out <= addr[19:16];
        4: mem_sio_out <= addr[15:12];
        5: mem_sio_out <= addr[11:8];
        6: mem_sio_out <= addr[7:4];
        7: mem_sio_out <= addr[3:0];
        default: begin
          if ( reading ) begin
            if ( counter > 13 ) begin // Allow 6 clocks of wait for the RAM to get ready
              mem_sio_outputen <= 0;
              data_out = {data_out[11:0], mem_sio_in};
              if ( counter == 18 ) reading <= 0;
            end
          end 
          else if ( writing ) begin
            {mem_sio_out, data_write[15:4]} = data_write;
            if ( counter == 11 ) writing <= 0;
          end
          else    
            mem_ce_n <= 1;
        end
      endcase    
    end
  end
endmodule


module spi_command( // 12 reg 7 lut 300MHz max
  input clk,
  input [7:0] command,
  input strobe,
  output reg ready,
  output reg line,
  output reg ce_n
);

  localparam [7:0] PS_CMD_RSTEN = 8'h66;
  localparam [7:0] PS_CMD_RST   = 8'h99;
  localparam [7:0] PS_CMD_QPI   = 8'h35;

  reg [7:0] shifter;
  reg sendcommand = 0;
  reg [2:0] command_ctr = 0;

  always_ff @(posedge clk) begin       
    if ( ready && strobe ) begin
       sendcommand <= 1;    
       shifter <= command;
       command_ctr <= 0;      
    end
    else if ( sendcommand ) begin
      shifter <= shifter << 1;
      command_ctr <= command_ctr + 1'd1;
      if ( command_ctr == 3'd7 ) begin
        sendcommand <= 0;
      end
    end      
  end

  assign line = shifter[7];  
  assign ce_n = ~sendcommand;
  assign ready = ce_n;
endmodule
