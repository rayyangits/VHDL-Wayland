# SWS – Single Wire Serial Interface User Guide

# Introduction

This document describes the register interface for the SWS (Single Wire Serial) controller, implemented on an Altera Cyclone 10 FPGA using a Nios-V embedded processor. The SWS controller provides a software-configurable interface to up to 8 addressable SWS slave devices on a shared single-wire bus, supporting read and write operations including serial number reads, random address reads, manufacturer ID reads, current address reads, and byte writes.

All register access is performed via the Nios-V memory-mapped bridge (`MM_BRIDGE_0`). The base address is defined in the system header as `MM_BRIDGE_0_BASE`.

---

## Document Conventions

### Addresses

Registers are accessed using a byte offset added to `MM_BRIDGE_0_BASE`. The offset for each register is listed in the register map table below. The offsets have been defined for user ease. For example, to write to the control register:

```c
IOWR_32DIRECT(MM_BRIDGE_0_BASE, CONTROL_REG_OFFSET , value);
```


### Register Access Types

| Read/write | RW | Software can read and write this bit. |
| --- | --- | --- |
| Read-only | R | Software can only read this bit. Writing has no effect. |
| Read, clear write 1 | RC1 | Software can read and clear this bit by writing 1. Writing 0 has no effect. |
| Read-only, write trigger | RT1 | Software can read this bit. Writing 1 triggers an event but does not change the bit value. The bit always reads back as 0. |
| Reserved | -- | Reserved bit. Must be kept at reset value. |

---

# Register Map

| **#** | **Offset** | **Abbr.** | **Name** |
| --- | --- | --- | --- |
| 0 | 0x00 | [SWS\_CR](#sws_cr--control-register) | SWS\_CONTROL |
| 1 | 0x04 | [SWS\_CFG](#sws_cfg--configuration-register) | SWS\_CONFIG |
| 2 | 0x08 | [SWS\_SR](#sws_sr--status-register) | SWS\_STATUS |
| 3 | 0x0C | [SWS\_SERH](#sws_serh--serial-data-high-register) | SWS\_SERIAL\_HIGH |
| 4 | 0x10 | [SWS\_SERL](#sws_serl--serial-data-low-register) | SWS\_SERIAL\_LOW |
| 5 | 0x14 | [SWS\_DEV](#sws_dev--device-select-register) | SWS\_DEVICE\_SELECT |
| 6 | 0x18 | [SWS\_WSERH](#sws_wserh--write-serial-data-high-register) | SWS\_WRITE\_SERIAL\_HIGH |
| 7 | 0x1C | [SWS\_WSERL](#sws_wserl--write-serial-data-low-register) | SWS\_WRITE\_SERIAL\_LOW |

---

# Register Descriptions

## SWS\_CR – Control Register

**Register Number:** 0

**Address Offset:** 0x00

This is the primary register for issuing commands to the SWS controller. Write the desired operation parameters and trigger bits in a single 32-bit write. The trigger bits (RT1) clear automatically on the next clock cycle after the write, so the start condition is a single-cycle pulse.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:24 | ADDR | 0x00 | RW | **Memory address byte** <br> The target memory address on the SWS slave device. Used in random address reads and byte writes. Ignored for modes that do not require an address (e.g. manufacturer ID read, serial number read). |
| 23:16 | WDAT | 0x00 | RW | **Write data byte** <br> The data byte to be written to the slave device during a single byte write operation. Only relevant when `START_WRITE` is triggered with `WMODE = 0x0` or `0x2`. For page writes the data is supplied via `SWS_WSERH` and `SWS_WSERL`. |
| 15:12 | RMODE | 0x0 | RW | **Read mode select** <br> Selects the type of read operation to perform when `START_READ` is triggered. See Read Mode table below. |
| 11:9 | WMODE | 000 | RW | **Write mode select** <br> Selects the type of write operation to perform when `START_WRITE` is triggered. See Write Mode table below. |
| 8 | DACM | 0 | RW | **DAC output data multiplexer** <br> Reserved for future use. |
| 7 | -- | 0 | -- | Reserved. |
| 6 | START\_READ | 0 | RT1 | **Start read operation** <br> Write 1 to trigger the read operation selected by `RMODE`. This bit always reads back as 0. The controller must be idle (`BUSY_READ = 0`) before triggering. |
| 5 | START\_WRITE | 0 | RT1 | **Start write operation** <br> Write 1 to trigger a write operation. Mode and target are determined by `WMODE` and `ADDR`. This bit always reads back as 0. The controller must be idle (`BUSY_WRITE = 0`) before triggering. |
| 4 | -- | 0 | -- | Reserved. |
| 3 | OEN | 0 | RW | **Output enable** <br> Reserved for future use. |
| 2 | START\_RESET | 0 | RT1 | **Start reset operation** <br> Write 1 to issue a bus reset pulse to the SWS bus. This bit always reads back as 0. |
| 1 | -- | 0 | -- | Reserved. |
| 0 | EN | 0 | RW | **Controller enable** <br> Reserved for future use. |

### Read Mode Table

| **RMODE [15:12]** | **Mode** | **Bytes Returned** | **Description** |
| --- | --- | --- | --- |
| 0001 | Manufacturer ID Read | 3 | Reads the 3-byte manufacturer ID from the device. Result in `SWS_SERH[31:8]`. |
| 0010 | Current Address Read | 1 | Reads one byte from the device's current internal pointer address. Result in `SWS_SERH[31:24]`. |
| 0100 | Random Address Read | 1 | Reads one byte from the address specified in `ADDR`. Result in `SWS_SERH[31:24]`. |
| 1000 | EEPROM Sequential Read | 8 | Identical to Security Register Sequential read but just in the EEPROM.|
| 0011 | Security Register Sequential Read / Serial Number Read | 8 | If `ADDR = 0x00`, reads the full 8-byte serial number. If `ADDR` is non-zero, performs a sequential read of 8 bytes starting from that address. Result across `SWS_SERH` and `SWS_SERL`.  |

### Write Mode Table

| **WMODE [11:9]** | **Mode** | **Data Source** | **Description** |
| --- | --- | --- | --- |
| 000 | EEPROM Single Byte Write | `WDAT [23:16]` | Writes a single byte to the EEPROM at the address given in `ADDR`. |
| 001 | EEPROM Page Write | `SWS_WSERH` / `SWS_WSERL` | Writes 8 bytes to EEPROM starting at the 8-byte aligned address in `ADDR` (lower 3 bits ignored). Data must be written to registers 6 and 7 before triggering. |
| 010 | Security Register Single Byte Write | `WDAT [23:16]` | Writes a single byte to the security register at the address given in `ADDR`. |
| 011 | Security Register Page Write | `SWS_WSERH` / `SWS_WSERL` | Writes 8 bytes to the security register at the 8-byte aligned address in `ADDR` (lower 3 bits ignored). Data must be written to registers 6 and 7 before triggering. |
| 10110 | **Security Register Lock** ⚠️ | — | **Permanently locks the security register. This operation is irreversible — no further writes can be made to the security register after this command is issued. Use with extreme caution.** |

### Example Usage of 
```c
// Write a page to EEPROM: load data into regs 6/7 first, then trigger


uint32_t eeprom_page_write = 0;
eeprom_page_write |= (1 << 5);         // START_WRITE
eeprom_page_write |= (0x1 << 9);       // WMODE = EEPROM page write 
eeprom_page_write |= (0x38 << 24);     // ADDR = 0x38           <-- for changes in memory address , find relevant operation in the glossary and edit the byte

device_select(1);  // this takes 3 digits , refer to page 55 of the microchip datasheet , They correspond to the notation A2 A1 A0.

write_bytes(0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88); // this is where you input your bytes for page writes | in the case of single byte writes , 
//                                                              you must edit the  single data byte in the glossary

run_sws_command(eeprom_page_write);  // Choose from the list of operations and input it here
```

[Back to register map](#register-map)

---

## SWS\_CFG – Configuration Register

**Register Number:** 1

**Address Offset:** 0x04

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:30 | -- | 00 | -- | Reserved. |
| 29:20 | RATE | 0x00F | RW | **Sample rate configuration** <br> Reserved for future use. Configures internal timing parameters. |
| 19:16 | -- | 0x0 | -- | Reserved. |
| 15:14 | ILFM | 00 | RW | **Glitch filter mode** <br> Reserved for future use. |
| 13:0 | ILFT | 0x0000 | RW | **Glitch filter threshold** <br> Reserved for future use. |

[Back to register map](#register-map)

---

## SWS\_SR – Status Register

**Register Number:** 2

**Address Offset:** 0x08

This register reflects the real-time status of all three SWS bus operations. The `BUSY` bits are set while the operation is in progress and cleared when it completes. The `DONE` bits are set when the operation completes successfully and cleared automatically on the next operation trigger.

Poll this register after issuing a command to determine when the result is ready. Always read result registers (`SWS_SERH`, `SWS_SERL`) only after the relevant `DONE` bit is set.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:9 | -- | 0 | -- | Reserved. |
| 8 | BUSY\_READ | 0 | R | **Read operation busy** <br> Set to 1 while a read operation is in progress. Cleared when the operation completes or returns to idle. Do not trigger a new read while this bit is set. |
| 7 | BUSY\_WRITE | 0 | R | **Write operation busy** <br> Set to 1 while a write operation is in progress. Cleared when the operation completes. Do not trigger a new write while this bit is set. |
| 6 | BUSY\_RESET | 0 | R | **Reset operation busy** <br> Set to 1 while a bus reset is in progress. |
| 5 | DONE\_READ | 0 | R | **Read operation complete** <br> Set to 1 when a read operation has completed successfully. Result data is stable in `SWS_SERH` and `SWS_SERL` while this bit is set. Cleared on the next triggered operation. |
| 4 | DONE\_WRITE | 0 | R | **Write operation complete** <br> Set to 1 when a write operation has completed successfully. Cleared on the next triggered operation. |
| 3 | DONE\_RESET | 0 | R | **Reset operation complete** <br> Set to 1 when a bus reset has completed. Cleared on the next triggered operation. |
| 2:0 | -- | 0 | -- | Reserved. |

### Polling Example

```c
// Wait for read to complete
uint32_t status;
do {
    status = IORD_32DIRECT(MM_BRIDGE_0_BASE, 0x08);
} while (!((status >> 5) & 0x1));  // poll DONE_READ (bit 5)
```

> **Note:** Do not issue a new command while any `BUSY` bit is set. Issuing a command while the bus is busy will be ignored by the controller as the FSM will not be in the IDLE state.

[Back to register map](#register-map)

---

## SWS\_SERH – Serial Data High Register

**Register Number:** 3

**Address Offset:** 0x0C

**Access:** Read-only. This register is a direct live view of the most recently captured read data. It is not latched — it reflects the current output of the SWS read module at all times.

This register holds the first four bytes of data received from the SWS slave device. For single-byte read modes, only the most significant byte `[31:24]` is populated.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:24 | BYTE0 | 0x00 | R | **Received byte 0** <br> First byte received from the SWS device. For single-byte modes (current address read, random address read) this is the only valid byte. For manufacturer ID read, bytes 0–2 are valid. For serial number read, all 8 bytes across both registers are valid. |
| 23:16 | BYTE1 | 0x00 | R | **Received byte 1** <br> Second byte received. Valid for manufacturer ID read and serial number read. |
| 15:8 | BYTE2 | 0x00 | R | **Received byte 2** <br> Third byte received. Valid for manufacturer ID read and serial number read. |
| 7:0 | BYTE3 | 0x00 | R | **Received byte 3** <br> Fourth byte received. Valid for serial number read only. |

### Data Layout by Mode

| **Mode** | **Valid bytes in SERH** | **Valid bytes in SERL** |
| --- | --- | --- |
| Manufacturer ID Read | BYTE0, BYTE1, BYTE2 | None |
| Current Address Read | BYTE0 only | None |
| Random Address Read | BYTE0 only | None |
| Serial Number Read | BYTE0–BYTE3 | BYTE4–BYTE7 |

[Back to register map](#register-map)

---

## SWS\_SERL – Serial Data Low Register

**Register Number:** 4

**Address Offset:** 0x10

**Access:** Read-only. Populated only during a serial number read (RMODE = 1000). Contains bytes 4–7 of the 8-byte serial number response.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:24 | BYTE4 | 0x00 | R | **Received byte 4** <br> Fifth byte of the serial number. Valid for serial number read only. |
| 23:16 | BYTE5 | 0x00 | R | **Received byte 5** <br> Sixth byte of the serial number. Valid for serial number read only. |
| 15:8 | BYTE6 | 0x00 | R | **Received byte 6** <br> Seventh byte of the serial number. Valid for serial number read only. |
| 7:0 | BYTE7 | 0x00 | R | **Received byte 7** <br> Eighth and final byte of the serial number. Valid for serial number read only. |

### Reading the Full Serial Number

```c
uint32_t serh = IORD_32DIRECT(MM_BRIDGE_0_BASE, 0x0C);
uint32_t serl = IORD_32DIRECT(MM_BRIDGE_0_BASE, 0x10);

printf("Serial: %02X %02X %02X %02X %02X %02X %02X %02X\n",
    (serh >> 24) & 0xFF, (serh >> 16) & 0xFF,
    (serh >>  8) & 0xFF, (serh      ) & 0xFF,
    (serl >> 24) & 0xFF, (serl >> 16) & 0xFF,
    (serl >>  8) & 0xFF, (serl      ) & 0xFF);
```

[Back to register map](#register-map)

---

## SWS\_DEV – Device Select Register

**Register Number:** 5

**Address Offset:** 0x14

Selects which physical SWS device on the bus will be targeted by the next command. Write this register before issuing any command via `SWS_CR`. The selected device persists until this register is written again, so consecutive operations on the same device require only one write.

The 3-bit `DEVICE` field maps directly to bits [7:5] of the SWS device address byte transmitted on the bus during every operation.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:3 | -- | 0 | -- | Reserved. |
| 2:0 | DEVICE | 000 | RW | **Device select** <br> Selects the target SWS slave device. This value is inserted into bits [7:5] of the device address byte in the SWS protocol frame. Supports up to 8 devices (0–7). |

### Device Select Table

| **DEVICE [2:0]** | **Target Device** |
| --- | --- |
| 000 | Device 0 (default) |
| 001 | Device 1 |
| 010 | Device 2 |
| 011 | Device 3 |
| 100 | Device 4 |
| 101 | Device 5 |
| 110 | Device 6 |
| 111 | Device 7 |

### Example Usage

```c
// Select device 3 then read its serial number
device_select(3);
run_sws_command(serial_number_read);
```

> **Note:** Always call `device_select()` before `run_sws_command()`. Writing `SWS_DEV` after the command has been issued will have no effect on the current operation.

[Back to register map](#register-map)

---

## SWS\_WSERH – Write Serial Data High Register

**Register Number:** 6

**Address Offset:** 0x18

**Access:** Read/Write. Holds bytes 0–3 of the data payload for page write operations. This register must be written before triggering an EEPROM page write (`WMODE = 001`) or a security register page write (`WMODE = 011`). The value is held until overwritten.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:24 | WBYTE0 | 0x00 | RW | **Write byte 0** <br> First byte to be written to the device during a page write. |
| 23:16 | WBYTE1 | 0x00 | RW | **Write byte 1** |
| 15:8  | WBYTE2 | 0x00 | RW | **Write byte 2** |
| 7:0   | WBYTE3 | 0x00 | RW | **Write byte 3** |

[Back to register map](#register-map)

---

## SWS\_WSERL – Write Serial Data Low Register

**Register Number:** 7

**Address Offset:** 0x1C

**Access:** Read/Write. Holds bytes 4–7 of the data payload for page write operations. Used in conjunction with `SWS_WSERH` to provide all 8 bytes for a page write. Must be written before triggering any page write command.

**Bit Definitions:**

| **Bit #** | **Name** | **Reset** | **Access** | **Description** |
| --- | --- | --- | --- | --- |
| 31:24 | WBYTE4 | 0x00 | RW | **Write byte 4** |
| 23:16 | WBYTE5 | 0x00 | RW | **Write byte 5** |
| 15:8  | WBYTE6 | 0x00 | RW | **Write byte 6** |
| 7:0   | WBYTE7 | 0x00 | RW | **Write byte 7** <br> Last byte of the 8-byte page write payload. |

### Loading Write Data Example

```c
// Usage before a page write:
write_bytes(0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88);
run_sws_command(eeprom_page_write);
```

[Back to register map](#register-map)

---

# Software Reference

## C Defines

```c
#define CONTROL_REG_OFFSET  0x00    // SWS_CR    – Control
#define STATUS_REG_OFFSET   0x08    // SWS_SR    – Status
#define SERIAL_REG_1        0x0C    // SWS_SERH  – Read serial bytes 0–3
#define SERIAL_REG_2        0x10    // SWS_SERL  – Read serial bytes 4–7
#define DEVICE_REG_OFFSET   0x14    // SWS_DEV   – Device select
#define SERIAL_REG_3        0x18    // SWS_WSERH – Write serial bytes 0–3
#define SERIAL_REG_4        0x1C    // SWS_WSERL – Write serial bytes 4–7
```

## Status Register Bit Positions

| **Bit** | **Name** | **Shift** | **Notes** |
| --- | --- | --- | --- |
| 8 | BUSY\_READ | `>> 8` | Busy functions signal ongoing data transfer attempts |
| 7 | BUSY\_WRITE | `>> 7` | |
| 6 | BUSY\_RESET | `>> 6` | |
| 5 | DONE\_READ | `>> 5` | Done functions signal the successful completion of an operation type |
| 4 | DONE\_WRITE | `>> 4` | |
| 3 | DONE\_RESET | `>> 3` | |

## Control Register Command Quick Reference

| **Operation** | **Bit 6** | **Bit 5** | **Bit 2** | **RMODE [15:12]** | **WMODE [11:9]** | **ADDR [31:24]** | **WDAT [23:16]** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Manufacturer ID Read | 1 | 0 | 0 | 0001 | — | — | — |
| EEPROM Current Address Read | 1 | 0 | 0 | 0010 | — | 00h-7Fh | — |
| EEPROM Random Address Read | 1 | 0 | 0 | 0100 | — | 00h-7Fh | — |
| Serial Number Read | 1 | 0 | 0 | 1000 | — | 0x00 | — |
| Security Register Sequential Read | 1 | 0 | 0 | 1000 | — | 10h-1Fh | — |
| EEPROM Sequential Read | 1 | 0 | 0 | 0011 | — | 00h-7Fh | — |
| EEPROM Single Byte Write | 0 | 1 | 0 | — | 000 | 00h-7Fh | data |
| EEPROM Page Write | 0 | 1 | 0 | — | 001 | 00h-7Fh | — |
| Security Single Byte Write | 0 | 1 | 0 | — | 010 | 10h-1Fh | data |
| Security Page Write | 0 | 1 | 0 | — | 011 | 10h-1Fh | — |
| Security Register Lock ⚠️ | 0 | 1 | 0 | — | 111 | — | — |
| Bus Reset | 0 | 0 | 1 | — | — | — | — |





<img src="https://www.image2url.com/r2/default/images/1779202748165-7f034d26-f922-4304-b586-0273e167521a.png" alt="Alt text" width="50%">















