module top (
  input button0,
  // These are connected to the mem chip. Pinout is for Sipeed TANG Nano
  inout wire [3:0] mem_sio,   // sio[0] pin 22, sio[1] pin 23, sio[2] pin 24, sio[3] pin 21
  output wire mem_ce_n,       // pin 19
  output wire mem_clk,         // pin 20
  output reg led_g,
  output reg led_r,
  output reg led_b
);

  wire clk;
  wire mem_ready;
  reg [7:0] addr = 8'd0;
  reg read_strb;
  reg write_strb;
  wire [15:0] data_out;
  reg [15:0] data_in;

  Gowin_OSC oscillator(
    .oscout(clk) 
  );

  memory memory(
    button0,
    clk,
    mem_ready,

    {{16{1'b0}},addr},
    read_strb,
    data_out,
    write_strb,
    data_in,

    8'h47, // 71 * 256 clocks at 120MHz is about 150us that we need to wait for the chip.
    
    mem_sio,
    mem_ce_n,
    mem_clk
  );



  localparam [3:0] WRITEA = 0;
  localparam [3:0] WRITEB = 1;
  localparam [3:0] READA = 2;
  localparam [3:0] READB = 3;
  localparam [3:0] NEXT = 4;

  reg [15:0] counter;
  reg [15:0] read;
  reg [3:0] step;
  reg error;

  
  always_comb begin 
      led_r <= ~(error && go);
      led_g <= ~(~error && go);
      led_b <= go;
  end
  

  reg [7:0] debouncec = 0;
  reg go = 0;
  always @(posedge clk) begin
    debouncec <= button0 ? 8'd0 : debouncec + 8'd1;
    if ( debouncec[7] ) go <= 1;
  end


  always @(posedge clk) begin    
    if ( mem_ready && go) 
      case (step)
        WRITEA: begin   
          addr <= 8'h0;
          data_in <= 16'h1234;
          write_strb <= 1;
          read_strb <= 0;
          step <= WRITEB;
        end
        WRITEB: begin   
          addr <= 8'h2;
          data_in <= 16'h5678;
          write_strb <= 1;
          read_strb <= 0;
          step <= READA;
        end
        READA: begin
          addr <= 8'h0;
          write_strb <= 0;
          read_strb <= 1;
          step <= READB;
        end
        READB: begin
          read <= data_out;
          if ( data_out != 16'h1234 ) error <= 1;
          addr <= 8'h1;
          write_strb <= 0;
          read_strb <= 1;
          step <= NEXT;
        end
        NEXT: begin
          write_strb <= 0;
          read_strb <= 0;
          read <= data_out;
          if ( data_out != 16'h3456 ) error <= 1;
          counter <= counter + 1'd1;
          step <= WRITEA;
        end        
      endcase
    else begin
      read_strb <= 0;
      write_strb <= 0;
    end
      
  end

endmodule
