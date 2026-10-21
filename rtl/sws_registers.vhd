-------------------------------------------------------------------------------
-- Title       : Coil Driver Register Bank
-- Module      : Coil Driver v2.0
-------------------------------------------------------------------------------
-- Copyright (c) 2024 Wayland Additive Limited
-------------------------------------------------------------------------------
-- R   - Read only
-- RW  - Readable and writable
-- RT1 - Read-only, write trigger
-- RC1 - Read, clear write 1
-- RCW - Read, clear write any
--
-- Register Map:
--   Reg 0  (0x00) : Control        RW
--   Reg 1  (0x04) : Config         RW
--   Reg 2  (0x08) : Status         R / RC1
--   Reg 3  (0x0C) : Serial bytes 0-3  R  [63:32] of serial_bytes
--   Reg 4  (0x10) : Serial bytes 4-7  R  [31:0]  of serial_bytes
--   Reg 5 (0x14)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sws_registers is
    generic (
        G_ADDR_WIDTH    : natural       := 6;
        G_DATA_WIDTH    : natural       := 32
    );
    port (
        i_mm_clk        : in  std_logic;
        i_mm_reset      : in  std_logic;

        i_mm_write      : in  std_logic;
        i_mm_address    : in  std_logic_vector (G_ADDR_WIDTH-1 downto 0);
        i_mm_wr_data    : in  std_logic_vector (G_DATA_WIDTH-1 downto 0);
        o_mm_rd_data    : out std_logic_vector (G_DATA_WIDTH-1 downto 0);

        -- Control outputs
        o_read_mode     : out std_logic_vector ( 3 downto  0);
        o_write_mode    : out std_logic_vector ( 2 downto  0);
        o_addr_byte     : out std_logic_vector ( 7 downto  0);
        -- Trigger based control regs
        o_start_write   : out std_logic;
        o_start_read    : out std_logic;
        o_start_reset   : out std_logic;

        o_cr_oen        : out std_logic;
        o_cr_whatever   : out std_logic;
        o_cr_en         : out std_logic;

        o_cfg_rate      : out std_logic_vector ( 9 downto  0);
        o_cfg_ilfm      : out std_logic_vector ( 1 downto  0);
        o_cfg_ilft      : out std_logic_vector (13 downto  0);

        -- Status inputs
        -- 64-bit serial bytes: [63:32] -> reg 3, [31:0] -> reg 4
        i_rd_serial_bytes : in  std_logic_vector (63 downto 0);

        o_wr_serial_bytes : out std_logic_vector (63 downto 0);

        i_busy_read     : in  std_logic;
        i_busy_write    : in  std_logic;
        i_busy_reset    : in  std_logic;
        i_done_read     : in  std_logic;
        i_done_write    : in  std_logic;
        i_done_reset    : in  std_logic;

        o_device        : out  std_logic_vector (2 downto 0);
        o_wr_byte       : out std_logic_vector (7 downto 0);

        o_idmd          : buffer std_logic_vector (23 downto 0);
        i_irbk          : in  std_logic_vector (23 downto  0);
        o_vdmd          : out std_logic_vector (23 downto  0);

        o_kp            : out std_logic_vector (31 downto  0);
        o_ki            : out std_logic_vector (31 downto  0);
        o_kic           : out std_logic_vector (31 downto  0);
        o_kiet          : out std_logic_vector (23 downto  0);

        o_iwh           : out std_logic_vector (23 downto  0);
        o_iwl           : out std_logic_vector (23 downto  0);
        o_ilh           : out std_logic_vector (23 downto  0);
        o_ill           : out std_logic_vector (23 downto  0);
        o_dch           : out std_logic_vector (23 downto  0);
        o_dcl           : out std_logic_vector (23 downto  0);
        o_vch           : out std_logic_vector (23 downto  0);
        o_vcl           : out std_logic_vector (23 downto  0);

        o_wh            : out std_logic_vector (23 downto  0);
        o_wl            : out std_logic_vector (23 downto  0);
        o_wth           : out std_logic_vector (23 downto  0);
        o_wtl           : out std_logic_vector (23 downto  0);
        o_wsr           : out std_logic_vector (23 downto  0);
        o_wsf           : out std_logic_vector (23 downto  0);
        o_wtr           : out std_logic_vector (23 downto  0);
        o_wtf           : out std_logic_vector (23 downto  0);

        o_debug_sel     : out std_logic_vector ( 4 downto  0)
    );
end sws_registers;

architecture rtl of sws_registers is

    signal w_reg_write  : std_logic_vector(2**G_ADDR_WIDTH-1 downto 0) := (others => '0');

    type   t_reg_bank is array (0 to 2**G_ADDR_WIDTH-1) of std_logic_vector(G_DATA_WIDTH-1 downto 0);
    signal r_reg_bank   : t_reg_bank := (others => (others => '0'));

    signal w_sr_set_bits    : std_logic_vector (G_DATA_WIDTH-1 downto 0);
    signal w_sr_clear_bits  : std_logic_vector (G_DATA_WIDTH-1 downto 0);
    signal r_idmd           : std_logic_vector (23 downto 0);

begin

    -------------------------
    -- Write decoding logic
    -------------------------
    g_wr_decode : for n in 0 to 2**G_ADDR_WIDTH-1 generate
        w_reg_write(n) <= '1' when i_mm_address = std_logic_vector(to_unsigned(n, G_ADDR_WIDTH))
                              and  i_mm_write = '1'
                     else '0';
    end generate;

    ---------------------------
    -- Read multiplexing logic
    --
    -- Registers 3 and 4 are read-only views of i_rd_serial_bytes.
    -- They are not stored in r_reg_bank — served directly from the input
    ---------------------------
    p_rd_mux : process(i_mm_clk)
    begin
        if rising_edge(i_mm_clk) then
            case to_integer(unsigned(i_mm_address)) is
                when 3      => o_mm_rd_data <= i_rd_serial_bytes(63 downto 32); -- bytes 0-3
                when 4      => o_mm_rd_data <= i_rd_serial_bytes(31 downto  0); -- bytes 4-7  ---i switched these 
                when others => o_mm_rd_data <= r_reg_bank(to_integer(unsigned(i_mm_address)));
            end case;
        end if;
    end process;

    ------------------------
    -- Register 00: Control
    ------------------------
    o_addr_byte    <= r_reg_bank(0)(31 downto 24);
    o_wr_byte      <= r_reg_bank(0)(23 downto 16);
    o_read_mode    <= r_reg_bank(0)(15 downto 12);
    o_write_mode   <= r_reg_bank(0)(11 downto 9);

    o_start_read   <= r_reg_bank(0)(6);
    o_start_write  <= r_reg_bank(0)(5);
    o_start_reset  <= r_reg_bank(0)(2);

    o_cr_whatever  <= r_reg_bank(0)(7);
    o_cr_oen       <= r_reg_bank(0)(3);
    o_cr_en        <= r_reg_bank(0)(0);

    p_reg_00 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(0) <= (others => '0');
        elsif rising_edge(i_mm_clk) then
            if w_reg_write(0) = '1' then
                r_reg_bank(0)(30 downto 24) <= i_mm_wr_data(30 downto 24);
                r_reg_bank(0)(23 downto 16) <= i_mm_wr_data(23 downto 16);
                r_reg_bank(0)(15 downto 12) <= i_mm_wr_data(15 downto 12);
                r_reg_bank(0)(11 downto 10) <= i_mm_wr_data(11 downto 10);
                r_reg_bank(0)(9  downto  8) <= i_mm_wr_data( 9 downto  8);
                r_reg_bank(0)(7)            <= i_mm_wr_data(7);
                r_reg_bank(0)(6)            <= i_mm_wr_data(6);  -- start_read  (RT1)
                r_reg_bank(0)(5)            <= i_mm_wr_data(5);  -- start_write (RT1)
                r_reg_bank(0)(3)            <= i_mm_wr_data(3);
                r_reg_bank(0)(2)            <= i_mm_wr_data(2);  -- start_reset (RT1)
                r_reg_bank(0)(0)            <= i_mm_wr_data(0);

                if i_mm_wr_data(2) = '1' then
                    r_reg_bank(0)(9) <= '1';
                end if;
            else
                -- RT1: trigger bits clear automatically after one write cycle
                r_reg_bank(0)(6) <= '0';  -- start_read
                r_reg_bank(0)(5) <= '0';  -- start_write
                r_reg_bank(0)(2) <= '0';  -- start_reset
            end if;
        end if;
    end process;

    -----------------------
    -- Register 01: Config
    -----------------------
    o_cfg_rate <= r_reg_bank(1)(29 downto 20);
    o_cfg_ilfm <= r_reg_bank(1)(15 downto 14);
    o_cfg_ilft <= r_reg_bank(1)(13 downto  0);

    p_reg_01 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(1) <= (others => '0');
        elsif rising_edge(i_mm_clk) then
            if w_reg_write(1) = '1' then
                r_reg_bank(1)(29 downto 20) <= i_mm_wr_data(29 downto 20);
                r_reg_bank(1)(15 downto  0) <= i_mm_wr_data(15 downto  0);
            end if;
        end if;
    end process;

    ------------------------
    -- Register 02: Status
    --
    -- Bit layout:
    --   [8]  = busy_read
    --   [7]  = busy_write
    --   [6]  = busy_reset
    --   [4]  = done_read
    --   [3]  = done_write
    --   [2]  = done_reset
    --   [1]  = sr_il
    --   [0]  = sr_of
    --
    -- Note: serial data bytes are in registers 3 and 4, not here
    ------------------------
    w_sr_set_bits(31 downto 9) <= (others => '0');
    w_sr_set_bits(8)           <= i_busy_read;
    w_sr_set_bits(7)           <= i_busy_write;
    w_sr_set_bits(6)           <= i_busy_reset;
    w_sr_set_bits(5)           <= i_done_read;
    w_sr_set_bits(4)           <= i_done_write;
    w_sr_set_bits(3)           <= i_done_reset;
    w_sr_set_bits(2 downto 0)  <= (others => '0');  -- sr_il and sr_of are not implemented in this example

    w_sr_clear_bits <= i_mm_wr_data when w_reg_write(2) = '1' else (others => '0');

    p_reg_02 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(2) <= (others => '0');
        elsif rising_edge(i_mm_clk) then
            r_reg_bank(2) <= (r_reg_bank(2) and not w_sr_clear_bits) or w_sr_set_bits;
        end if;
    end process;

    -- Registers 3 and 4 are READ-ONLY and handled directly in p_rd_mux above.
    -- No write process needed — r_reg_bank(3) and r_reg_bank(4) are unused.

    -----------------------
    -- Register 05: Control 2 / Device Register (free space for more control bits to use)
    -----------------------
    o_device <= r_reg_bank(5)(2 downto 0);

    p_reg_05 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(5) <= (others => '0');

        elsif rising_edge(i_mm_clk) then
            if w_reg_write(5) = '1' then
                r_reg_bank(5) <= i_mm_wr_data;
            end if;
        end if;
    end process;
    -----------------------
    -- Register 06: Serial Data (High Bits)
    -----------------------
    o_wr_serial_bytes (63 downto 32) <= r_reg_bank(6)(31 downto 0);
    
    p_reg_06 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(6) <= (others => '0');

        elsif rising_edge(i_mm_clk) then
            if w_reg_write(6) = '1' then
                r_reg_bank(6) <= i_mm_wr_data;
            end if;
        end if;
    end process;
    -----------------------
    -- Register 07: Serial Data (Low Bits)
    -----------------------
    o_wr_serial_bytes (31 downto 0) <= r_reg_bank(7)(31 downto 0);

    p_reg_07 : process(i_mm_clk, i_mm_reset)
    begin
        if i_mm_reset = '1' then
            r_reg_bank(7) <= (others => '0');

        elsif rising_edge(i_mm_clk) then
            if w_reg_write(7) = '1' then
                r_reg_bank(7) <= i_mm_wr_data;
            end if;
        end if;
    end process;

end architecture;