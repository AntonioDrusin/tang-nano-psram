# A test of the PSRAM on the Sipeed Tang Nano

First, pardon the mess. This is my first project in verilog. I tested this code with the Oscilloscope tool included with the Gowin software. I think I am respecting the timing as I found on the datasheet, but I may be wrong and my particular chip is working correctly so your mileage may vary.

After programming the FPGA, you can use the oscilloscope to verify the functionality. Pressing the button to the left of the USB connector will trigger the oscilloscope once it is armed.

There are relatively few resources on the fpga (it's a nano after all). So my thoughts on that are:
 - Do not use more address lines than you need to
 - Transfer data to the BSRAM instead of a register and allow it to change its width by using one of the dual port versions of it. This requires the modification of the memory_driver module.
 - Remove the code that switches to QPI and use the STEP_SPI_CMD for CMD_READ and CMD_WRITE. The performance does not change that much, and the # of resources saved can be significant.

 2 byte read with QPI 18 clocks + cooldown
 2 byte read with SPI 24 clocks + cooldown

Transfering

For both the writes and the reads I ended up holding for 1 extra clock. I think that is necessary since the clocks are at opposite phases and there is a tCHD time from the clock edge to when CS is released of at least 3ns.


