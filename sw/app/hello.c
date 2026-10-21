#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include "system.h"
#include "io.h"
#include <altera_avalon_pio_regs.h>

#define CONTROL_REG_OFFSET  0x00
#define STATUS_REG_OFFSET   0x08
#define DEVICE_REG_OFFSET   0x14
#define SERIAL_REG_1        0x0C    // reg 4: serial bytes 0-3
#define SERIAL_REG_2        0x10    // reg 5: serial bytes 4-7

#define SERIAL_REG_3        0x18    // reg 6: serial bytes 0-3
#define SERIAL_REG_4        0x1C    // reg 7: serial bytes 4-7


// ---------------------------------------------------------------------------
// run_sws_command
//
// Writes cmd to the control register, waits for completion, then prints
// the result automatically based on the operation type encoded in cmd:
//
//   cmd bit  6     = start_read
//   cmd bit  5     = start_write
//   cmd bit  2     = start_reset
//   cmd [15:12]    = read read_mode  (0x1=mfr_id, 0x2=cur_addr, 0x4=rand_addr, 0x8=serial)
// ---------------------------------------------------------------------------
void device_select(uint8_t device) 
{
    IOWR_32DIRECT(MM_BRIDGE_0_BASE, DEVICE_REG_OFFSET, (device & 0x7)); 
}

void write_bytes(uint8_t b0, uint8_t b1, uint8_t b2, uint8_t b3,
                 uint8_t b4, uint8_t b5, uint8_t b6, uint8_t b7)
{
    uint32_t reg3;
    uint32_t reg4;

    reg3 = ((uint32_t)b0 << 24) |
           ((uint32_t)b1 << 16) |
           ((uint32_t)b2 <<  8) |
           ((uint32_t)b3);

    reg4 = ((uint32_t)b4 << 24) |
           ((uint32_t)b5 << 16) |
           ((uint32_t)b6 <<  8) |
           ((uint32_t)b7);

    IOWR_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_3, reg3);
    IOWR_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_4, reg4);
}


void run_sws_command(uint32_t cmd)
{
    IOWR_32DIRECT(MM_BRIDGE_0_BASE, CONTROL_REG_OFFSET, cmd);

    int is_read  = (cmd >> 6) & 0x1;
    int is_write = (cmd >> 5) & 0x1;
    int is_reset = (cmd >> 2) & 0x1;

    uint32_t status;

    if (is_reset)
    {
        // wait for done_reset (bit 3 to match VHDL)
        do {
            status = IORD_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET);
        } while (!((status >> 3) & 0x1));

        // Clear the status flag so it doesn't false-trigger next loop
        IOWR_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET, 0xFFFFFFFF);

        printf("Reset completed\n"); 
    }
    else if (is_write)
    {
        // wait for done_write (bit 4 to match VHDL)
        do {
            status = IORD_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET); 
        } while (!((status >> 4) & 0x1));

        // Clear the status flag so it doesn't false-trigger next loop
        IOWR_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET, 0xFFFFFFFF);

        uint8_t data_byte   = (cmd >> 16) & 0xFF;
        uint8_t mem_address = (cmd >> 24) & 0xFF;
        printf("Write completed: addr=0x%02X  data=0x%02X\n", mem_address, data_byte); 
        
        uint8_t  write_mode = (cmd >> 10) & 0x6F;
        uint32_t serial_3 = IORD_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_3);
        uint32_t serial_4 = IORD_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_4); 

        switch (write_mode)
        {
            case 0x0: // EEPROM single byte write
                printf("Writing single byte to EEPROM: %02X\n",
                    (unsigned int)((serial_3) & 0xFF));
                break;

            case 0x1: // EEPROM page write
                printf("Writing page to EEPROM: %02X %02X %02X %02X %02X %02X %02X %02X\n",
                    (unsigned int)((serial_3 >> 24) & 0xFF),
                    (unsigned int)((serial_3 >> 16) & 0xFF),
                    (unsigned int)((serial_3 >>  8) & 0xFF),
                    (unsigned int)((serial_3      ) & 0xFF),
                    (unsigned int)((serial_4 >> 24) & 0xFF),
                    (unsigned int)((serial_4 >> 16) & 0xFF),
                    (unsigned int)((serial_4 >>  8) & 0xFF),
                    (unsigned int)((serial_4      ) & 0xFF));
                break;

            case 0x2: // Security single byte write
                printf("Writing single byte to Security Register: %02X\n",
                    (unsigned int)((serial_3) & 0xFF));
                break;

            case 0x3: // Security page write
                printf("Writing page to Security Register: %02X %02X %02X %02X %02X %02X %02X %02X\n",
                    (unsigned int)((serial_3 >> 24) & 0xFF),
                    (unsigned int)((serial_3 >> 16) & 0xFF),
                    (unsigned int)((serial_3 >>  8) & 0xFF),
                    (unsigned int)((serial_3      ) & 0xFF),
                    (unsigned int)((serial_4 >> 24) & 0xFF),
                    (unsigned int)((serial_4 >> 16) & 0xFF),
                    (unsigned int)((serial_4 >>  8) & 0xFF),
                    (unsigned int)((serial_4      ) & 0xFF));
                break;

            default:
                printf("Unknown write_mode: 0x%X\n", write_mode);
                break;
        }
    }
    else if (is_read)
    {
        // wait for done_read (bit 5 to match VHDL)
        do {
            status = IORD_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET);
        } while (!((status >> 5) & 0x1));

        // Clear the status flag so it doesn't false-trigger next loop
        IOWR_32DIRECT(MM_BRIDGE_0_BASE, STATUS_REG_OFFSET, 0xFFFFFFFF);

        printf("Read completed\n");

        uint8_t  read_mode = (cmd >> 12) & 0xF;
        
        uint32_t serial_1 = IORD_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_1);   
        uint32_t serial_2 = IORD_32DIRECT(MM_BRIDGE_0_BASE, SERIAL_REG_2);   
   
        switch (read_mode) 
        {
            case 0x1: // manufacturer ID read — 3 bytes
                printf("Manufacturer ID: %02X %02X %02X\n",
                    (unsigned int)((serial_1 >> 24) & 0xFF),
                    (unsigned int)((serial_1 >> 16) & 0xFF),
                    (unsigned int)((serial_1 >>  8) & 0xFF));
                break;

            case 0x2: // current address read — 1 byte
                printf("Current Address Read: 0x%02X\n",
                    (unsigned int)((serial_1 >> 24) & 0xFF));
                break;

            case 0x4: // random address read — 1 byte
                printf("Random Address Read [0x%02X]: 0x%02X\n",
                    (unsigned int)((cmd >> 24) & 0xFF),
                    (unsigned int)((serial_1 >> 24) & 0xFF));
                break;

            case 0x8: // serial number read — 8 bytes
                uint8_t start_address = (cmd >> 24) & 0xFF;

                if (start_address == 0x00)
                {
                    printf("Serial Number Read: %02X %02X %02X %02X %02X %02X %02X %02X\n",
                        (unsigned int)((serial_1 >> 24) & 0xFF),
                        (unsigned int)((serial_1 >> 16) & 0xFF),
                        (unsigned int)((serial_1 >>  8) & 0xFF),
                        (unsigned int)((serial_1       ) & 0xFF),
                        (unsigned int)((serial_2 >> 24) & 0xFF),
                        (unsigned int)((serial_2 >> 16) & 0xFF),
                        (unsigned int)((serial_2 >>  8) & 0xFF),
                        (unsigned int)((serial_2       ) & 0xFF));
                }
                else
                {
                    printf("Sequential Read [0x%02X]: %02X %02X %02X %02X %02X %02X %02X %02X\n",
                        start_address,
                        (unsigned int)((serial_1 >> 24) & 0xFF),
                        (unsigned int)((serial_1 >> 16) & 0xFF),
                        (unsigned int)((serial_1 >>  8) & 0xFF),
                        (unsigned int)((serial_1       ) & 0xFF),
                        (unsigned int)((serial_2 >> 24) & 0xFF),
                        (unsigned int)((serial_2 >> 16) & 0xFF),
                        (unsigned int)((serial_2 >>  8) & 0xFF),
                        (unsigned int)((serial_2       ) & 0xFF));
                }
                break;
            
            default:
                printf("Unknown read read_mode: 0x%X\n", read_mode);
                break;
        }
    }

    printf("---\n");
    fflush(stdout);
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////





int main(void)
{
    printf("SWS Read Test Starting\n");
    fflush(stdout);

////////  ////////////   ///////////////   ////////////// ////////////// //////////////
 //  _____ _      ____   _____ _____        _____ __     __                          //
 // / ____| |    / __ \ / ____/ ____|  /\   |  __ \ \   / /
 //| |  __| |   | |  | | (___| (___   /  \  | |__) \ \_/ / 
 //| | |_ | |   | |  | |\___ \\___ \ / /\ \ |  _  / \   /  
 //| |__| | |___| |__| |____) |___) / ____ \| | \ \  | |   
 // \_____|______\____/|_____/_____/_/    \_\_|  \_\ |_|                                              
 //  You can edit stuff below this line to configure different operations   

////////////////READ COMMANDS/////////////////////////////////////////////////

    uint32_t manufacturer_id_read = 0;
    manufacturer_id_read |= (1 << 6);            // go
    manufacturer_id_read |= (0x1 << 12);        // read_mode: manufacturer ID
                                                
    uint32_t eeprom_current_address_read = 0;           
    eeprom_current_address_read |= (1 << 6);
    eeprom_current_address_read |= (0x2 << 12);        // read_mode: current address
    eeprom_current_address_read |= (0x38 << 24);   

    uint32_t eeprom_random_address_read = 0;
    eeprom_random_address_read |= (1 << 6);
    eeprom_random_address_read |= (0x4 << 12);         // read_mode: random address
    eeprom_random_address_read |= (0x38 << 24);        // memory address (configurable) // CHANGE THIS 

    uint32_t serial_number_read = 0;
    serial_number_read |= (1 << 6);
    serial_number_read |= (0x8 << 12);          // read_mode: sequential read
    serial_number_read |= (0x0 << 24);          // always starts from 0x00

    uint32_t security_reg_sequential_read = 0;
    security_reg_sequential_read |= (1 << 6);
    security_reg_sequential_read |= (0x8 << 12);          // read_mode: security register sequential read
    security_reg_sequential_read |= (0x38 << 24);         // memory address (configurable) CHANGE THIS

    uint32_t eeprom_sequential_read = 0;
    eeprom_sequential_read |= (1 << 6);
    eeprom_sequential_read |= (0x3 << 12);          // read_mode: eeprom sequential read
    eeprom_sequential_read |= (0x1C << 24);         // memory address (configurable) CHANGE THIS

/////////////////WRITE COMMANDS/////////////////////////////////////////////

    uint32_t eeprom_single_byte_write = 0;
    eeprom_single_byte_write |= (1 << 5);
    eeprom_single_byte_write |= (0x0 << 9);          // write_mode: security reg write
    eeprom_single_byte_write |= (0x38 << 24);          // address byte
    eeprom_single_byte_write |= (0xF0 << 16);         // data byte (configurable) this needs to go to regs 6 and 7

    uint32_t eeprom_page_write = 0;
    eeprom_page_write |= (1 << 5);
    eeprom_page_write |= (0x1 << 9);          // write_mode: security reg write
    eeprom_page_write |= (0x1C << 24);          // address byte

    uint32_t security_single_byte_write = 0;
    security_single_byte_write |= (1 << 5);
    security_single_byte_write |= (0x2 << 9);          // write_mode: security reg write
    security_single_byte_write |= (0x0 << 24);           // address byte
    security_single_byte_write |= (0xF0 << 16);        // data byte (configurable) this needs to go to regs 6 and 7

    uint32_t security_page_write = 0;
    security_page_write |= (1 << 5);
    security_page_write |= (0x3 << 9);          // write_mode: security reg write
    security_page_write |= (0x0 << 24);           // address byte

    uint32_t SECURITY_REGISTER_LOCK = 0;                    // DO NOT USE THIS UNLESS YOU KNOW WHAT YOU ARE DOING ONCE THE SECURITY REG IS LOCKED IT IS LOCKED PERMANENTLY AND NO FURTHER WRITES CAN BE MADE ONTO IT
    SECURITY_REGISTER_LOCK |= (1 << 5);
    SECURITY_REGISTER_LOCK |= (0x16 << 9);
    SECURITY_REGISTER_LOCK |= (0x0 << 24);
    SECURITY_REGISTER_LOCK |= (0xF0 << 16);

    uint32_t reset = 0;
    reset |= (1 << 2);                          // go (reset)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

    while (1)
    {
        printf("in the loop\n");
        fflush(stdout);

        // Change the argument here to switch operations:
        //   manufacturer_id_read             -> prints 3-byte manufacturer ID
        //   eeprom_current_address_read      -> prints 1-byte current address data
        //   eeprom_random_address_read       -> prints 1-byte data at your specified address 
        //   serial_number_read               -> prints 8-byte serial number
        //   security_reg_sequential_read     -> prints 8 bytes starting from specified address and auto-increments address for each byte (wraps around)
        //   eeprom_single_byte_write         -> writes custom byte to custom address 
        //   reset                            -> issues a device reset
        //   eeprom_page_write                -> writes 8 bytes from reg6/7 to 8-byte aligned address 
        //   security_single_byte_write       -> writes custom byte to custom address in security register
        //   security_page_write              -> writes 8 bytes from reg6/7 to 8-byte aligned address in security register (lower 3 bits of address ignored e.g. if 1111 1111 then xxx1 1111 will be what gets written to)
        //   SECURITY_REGISTER_LOCK           -> permanently locks the security register to prevent any future writes to it (USE WITH CAUTION THIS IS UNRECOVERABLE)
        //   reset                            -> issues a device reset


        device_select(2);          

        write_bytes(0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x80); // for 8 byte write opserations , change for single bytes in the glossary above 

        run_sws_command(eeprom_sequential_read);
        
        
        //usleep(1000000); //dont make the usleep value absurdly low if you intend to loop or else data will corrupt and you will be sad. (see README for details)
        break; //ideal to use the break
    }

    return 0;
}