# A test of the PSRAM on the Sipeed Tang Nano

First, pardon the mess. This is my first project in verilog. I tested this code with the Oscilloscope tool included with the Gowin software. I think I am respecting the timing as I found on the datasheet, but I may be wrong and my particular chip is working correctly so your mileage may vary.

After programming the FPGA, you can use the oscilloscope to verify the functionality. Pressing the button to the left of the USB connector will trigger the oscilloscope once it is armed.

I was only able to make it work up to 60MHz.

Transfering

For both the writes and the reads I ended up holding for 1 extra clock. I think that is necessary since the clocks are at opposite phases and there is a tCHD time from the clock edge to when CS is released of at least 3ns.


