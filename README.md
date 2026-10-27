All work here is from before I went to university, while I interned at Wayland Additive for the year. 2025-2026 .

This is a custom communication protocol to communicate with the AT21 series of One-Wire IC's in VHDL.
In order to understand this project better, you may open [doc/sws_register_guide.md](doc/sws_register_guide.md), and thereafter [doc/single_wire_serial_user_guide.md](doc/single_wire_serial_user_guide.md) and [sw/app/hello.c](sw/app/hello.c).

The former explains the premise as well as how to use it from a register R/W point of view in VHDL. The second explains the each of the codes functions in much greater detail with oscilloscope graphs. And finally the former explains how we address the VHDL through the NIOS's Avalon-MM interface using C.

Thank you for taking an interest. Kind regards.
