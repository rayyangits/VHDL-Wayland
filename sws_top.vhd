-- sws_top.vhd

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sws_top is
    port (
        clock_sink_clk             : in  std_logic := '0';
        reset_sink_reset           : in  std_logic := '0';
        avalon_slave_read          : in  std_logic := '0';
        avalon_slave_write         : in  std_logic := '0';
        avalon_slave_readdatavalid : out std_logic;
        avalon_slave_waitrequest   : out std_logic;
        avalon_slave_address       : in  std_logic_vector(7 downto 0) := (others => '0');
        avalon_slave_readdata      : out std_logic_vector(31 downto 0) := (others => '0');
        avalon_slave_writedata     : in  std_logic_vector(31 downto 0) := (others => '0');
        ow_in                      : in  std_logic;
        ow_oe                      : out std_logic
    );
end entity sws_top;

architecture rtl of sws_top is

    component sws_registers is
        generic (
            G_ADDR_WIDTH : natural := 6;
            G_DATA_WIDTH : natural := 32
        );
        port (
            i_mm_clk          : in  std_logic;
            i_mm_reset        : in  std_logic;
            i_mm_write        : in  std_logic;
            i_mm_address      : in  std_logic_vector(G_ADDR_WIDTH-1 downto 0);
            i_mm_wr_data      : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
            o_mm_rd_data      : out std_logic_vector(G_DATA_WIDTH-1 downto 0);

            o_addr_byte       : out std_logic_vector( 7 downto 0);
            o_wr_byte         : out std_logic_vector( 7 downto 0);
            o_read_mode       : out std_logic_vector( 3 downto 0);
            o_write_mode      : out std_logic_vector( 1 downto 0);

            o_start_write     : out std_logic;
            o_start_read      : out std_logic;
            o_start_reset     : out std_logic;

            o_cr_dacm         : out std_logic_vector( 1 downto 0);
            o_cr_oen          : out std_logic;
            o_cr_whatever     : out std_logic;
            o_cr_en           : out std_logic;

            o_cfg_rate        : out std_logic_vector( 9 downto 0);
            o_cfg_ilfm        : out std_logic_vector( 1 downto 0);
            o_cfg_ilft        : out std_logic_vector(13 downto 0);

            i_rd_serial_bytes : in  std_logic_vector(63 downto 0);
            i_busy_read       : in  std_logic;
            i_busy_write      : in  std_logic;
            i_busy_reset      : in  std_logic;
            i_done_read       : in  std_logic;
            i_done_write      : in  std_logic;
            i_done_reset      : in  std_logic;

            i_device          : in  std_logic_vector(2 downto 0);

            o_idmd            : buffer std_logic_vector(23 downto 0);
            i_irbk            : in  std_logic_vector(23 downto 0);
            o_vdmd            : out std_logic_vector(23 downto 0);

            o_kp              : out std_logic_vector(31 downto 0);
            o_ki              : out std_logic_vector(31 downto 0);
            o_kic             : out std_logic_vector(31 downto 0);
            o_kiet            : out std_logic_vector(23 downto 0);

            o_iwh             : out std_logic_vector(23 downto 0);
            o_iwl             : out std_logic_vector(23 downto 0);
            o_ilh             : out std_logic_vector(23 downto 0);
            o_ill             : out std_logic_vector(23 downto 0);
            o_dch             : out std_logic_vector(23 downto 0);
            o_dcl             : out std_logic_vector(23 downto 0);
            o_vch             : out std_logic_vector(23 downto 0);
            o_vcl             : out std_logic_vector(23 downto 0);

            o_wh              : out std_logic_vector(23 downto 0);
            o_wl              : out std_logic_vector(23 downto 0);
            o_wth             : out std_logic_vector(23 downto 0);
            o_wtl             : out std_logic_vector(23 downto 0);
            o_wsr             : out std_logic_vector(23 downto 0);
            o_wsf             : out std_logic_vector(23 downto 0);
            o_wtr             : out std_logic_vector(23 downto 0);
            o_wtf             : out std_logic_vector(23 downto 0);

            o_debug_sel       : out std_logic_vector( 4 downto 0)
        );
    end component;

    component sws_reset
        port(
            clk   : in  std_logic;
            rst   : in  std_logic;
            go    : in  std_logic;
            busy  : out std_logic;
            done  : out std_logic;
            dq_in : in  std_logic;
            dq_oe : out std_logic
        );
    end component;

    component sws_read
        port(
            clk          : in  std_logic;
            rst          : in  std_logic;
            read         : in  std_logic;
            busy         : out std_logic;
            r_done       : out std_logic;
            dq_in        : in  std_logic;
            dq_oe        : out std_logic;
            address      : in  std_logic_vector(7 downto 0);
            mode         : in  std_logic_vector(3 downto 0);
            serial_bytes : out std_logic_vector(63 downto 0);
            device       : in std_logic_vector(2 downto 0)
        );
    end component;

    component sws_write
        port(
            clk     : in  std_logic;
            rst     : in  std_logic;
            write   : in  std_logic;
            busy    : out std_logic;
            w_done  : out std_logic;
            dq_in   : in  std_logic;
            dq_oe   : out std_logic;
            mode    : in  std_logic_vector(2 downto 0);
            serial_bytes    : in  std_logic_vector(63 downto 0);
            address : in  std_logic_vector(7 downto 0);
            device  : in std_logic_vector(2 downto 0)
        );
    end component;

    ------------------------------------------------------------------
    -- Constants
    ------------------------------------------------------------------
    constant G_ADDR_WIDTH : natural := 6;
    constant G_DATA_WIDTH : natural := 32;

    ------------------------------------------------------------------
    -- Avalon / register bank signals
    ------------------------------------------------------------------
    signal w_avalon_slave_address   : std_logic_vector(5 downto 0);
    signal w_avalon_slave_writedata : std_logic_vector(31 downto 0);
    signal w_avalon_slave_readdata  : std_logic_vector(31 downto 0);

    ------------------------------------------------------------------
    -- Control signals (from register bank)
    ------------------------------------------------------------------
    signal w_start_reset  : std_logic;
    signal w_start_read   : std_logic;
    signal w_start_write  : std_logic;

    signal w_read_mode    : std_logic_vector(3 downto 0);
    signal w_write_mode   : std_logic_vector(2 downto 0);
    signal w_wr_byte      : std_logic_vector(7 downto 0);
    signal w_address_byte : std_logic_vector(7 downto 0);

    ------------------------------------------------------------------
    -- Status signals (to register bank)
    ------------------------------------------------------------------
    signal w_busy_reset : std_logic;
    signal w_busy_read  : std_logic;
    signal w_busy_write : std_logic;

    signal w_done_reset : std_logic;
    signal w_done_read  : std_logic;
    signal w_done_write : std_logic;

    signal w_device : std_logic_vector(2 downto 0);


    -- 64-bit serial bytes from sws_read, wired into register bank
    signal w_rd_serial_bytes : std_logic_vector(63 downto 0);
    signal w_wr_serial_bytes : std_logic_vector(63 downto 0);

    ------------------------------------------------------------------
    -- Register bank output signals (unused outputs still need signals)
    ------------------------------------------------------------------
    signal o_cr_oen    : std_logic;
    signal o_cr_en     : std_logic;
    signal o_cfg_rate  : std_logic_vector(9 downto 0);
    signal o_cfg_ilfm  : std_logic_vector(1 downto 0);
    signal o_cfg_ilft  : std_logic_vector(13 downto 0);
    signal o_idmd      : std_logic_vector(23 downto 0);
    signal o_vdmd      : std_logic_vector(23 downto 0);
    signal o_kp        : std_logic_vector(31 downto 0);
    signal o_ki        : std_logic_vector(31 downto 0);
    signal o_kic       : std_logic_vector(31 downto 0);
    signal o_kiet      : std_logic_vector(23 downto 0);
    signal o_iwh       : std_logic_vector(23 downto 0);
    signal o_iwl       : std_logic_vector(23 downto 0);
    signal o_ilh       : std_logic_vector(23 downto 0);
    signal o_ill       : std_logic_vector(23 downto 0);
    signal o_dch       : std_logic_vector(23 downto 0);
    signal o_dcl       : std_logic_vector(23 downto 0);
    signal o_vch       : std_logic_vector(23 downto 0);
    signal o_vcl       : std_logic_vector(23 downto 0);
    signal o_wh        : std_logic_vector(23 downto 0);
    signal o_wl        : std_logic_vector(23 downto 0);
    signal o_wth       : std_logic_vector(23 downto 0);
    signal o_wtl       : std_logic_vector(23 downto 0);
    signal o_wsr       : std_logic_vector(23 downto 0);
    signal o_wsf       : std_logic_vector(23 downto 0);
    signal o_wtr       : std_logic_vector(23 downto 0);
    signal o_wtf       : std_logic_vector(23 downto 0);
    signal o_debug_sel : std_logic_vector(4 downto 0);
    signal o_cr_whatever : std_logic;
    signal i_irbk      : std_logic_vector(23 downto 0);
    signal i_sr_of     : std_logic := '0';

    ------------------------------------------------------------------
    -- 1-Wire internal signals
    ------------------------------------------------------------------
    signal w_reset_dq_in : std_logic;
    signal w_reset_dq_oe : std_logic;
    signal w_read_dq_in  : std_logic;
    signal w_read_dq_oe  : std_logic;
    signal w_write_dq_in : std_logic;
    signal w_write_dq_oe : std_logic;

begin

    ------------------------------------------------------------------
    -- Submodule instantiations
    ------------------------------------------------------------------
    owreset_inst : sws_reset
        port map(
            clk   => clock_sink_clk,
            rst   => reset_sink_reset,
            go    => w_start_reset,
            busy  => w_busy_reset,
            done  => w_done_reset,
            dq_in => w_reset_dq_in,
            dq_oe => w_reset_dq_oe
        );

    owwrite_inst : sws_write
        port map(
            clk             => clock_sink_clk,
            rst             => reset_sink_reset,
            write           => w_start_write,
            busy            => w_busy_write,
            w_done          => w_done_write,
            dq_oe           => w_write_dq_oe,
            dq_in           => w_write_dq_in,
            serial_bytes    => w_wr_serial_bytes,
            mode            => w_write_mode,
            address         => w_address_byte,
            device          => w_device
        );

    owread_inst : sws_read
        port map(
            clk          => clock_sink_clk,
            rst          => reset_sink_reset,
            read         => w_start_read,
            busy         => w_busy_read,
            r_done       => w_done_read,
            dq_oe        => w_read_dq_oe,
            dq_in        => w_read_dq_in,
            address      => w_address_byte,
            mode         => w_read_mode,
            serial_bytes => w_rd_serial_bytes ,  -- 64-bit captured bytes
            device       => w_device
        );

    u_register_bank : entity work.sws_registers
        generic map(
            G_ADDR_WIDTH => G_ADDR_WIDTH,
            G_DATA_WIDTH => G_DATA_WIDTH
        )
        port map(
            i_mm_clk          => clock_sink_clk,
            i_mm_reset        => reset_sink_reset,
            i_mm_write        => avalon_slave_write,
            i_mm_address      => w_avalon_slave_address,
            i_mm_wr_data      => w_avalon_slave_writedata,
            o_mm_rd_data      => w_avalon_slave_readdata,

            o_read_mode       => w_read_mode,
            o_write_mode      => w_write_mode,
            o_start_write     => w_start_write,
            o_start_read      => w_start_read,
            o_start_reset     => w_start_reset,
            o_addr_byte       => w_address_byte,

            o_cr_oen          => o_cr_oen,
            o_cr_whatever     => o_cr_whatever,
            o_cr_en           => o_cr_en,
            o_cfg_rate        => o_cfg_rate,
            o_cfg_ilfm        => o_cfg_ilfm,
            o_cfg_ilft        => o_cfg_ilft,

            i_rd_serial_bytes => w_rd_serial_bytes,
            i_busy_read       => w_busy_read,
            i_busy_write      => w_busy_write,
            i_busy_reset      => w_busy_reset,
            i_done_read       => w_done_read,
            i_done_write      => w_done_write,
            i_done_reset      => w_done_reset,

            o_device          => w_device,
            o_wr_serial_bytes => w_wr_serial_bytes,

            o_idmd            => o_idmd,
            i_irbk            => i_irbk,
            o_vdmd            => o_vdmd,

            o_kp              => o_kp,
            o_ki              => o_ki,
            o_kic             => o_kic,
            o_kiet            => o_kiet,

            o_iwh             => o_iwh,
            o_iwl             => o_iwl,
            o_ilh             => o_ilh,
            o_ill             => o_ill,
            o_dch             => o_dch,
            o_dcl             => o_dcl,
            o_vch             => o_vch,
            o_vcl             => o_vcl,

            o_wh              => o_wh,
            o_wl              => o_wl,
            o_wth             => o_wth,
            o_wtl             => o_wtl,
            o_wsr             => o_wsr,
            o_wsf             => o_wsf,
            o_wtr             => o_wtr,
            o_wtf             => o_wtf,

            o_debug_sel       => o_debug_sel
        );

    ------------------------------------------------------------------
    -- Avalon address/data routing
    -- Address bits [7:2] select the 32-bit word (byte address / 4)
    ------------------------------------------------------------------
    w_avalon_slave_address   <= avalon_slave_address(7 downto 2);
    w_avalon_slave_writedata <= avalon_slave_writedata;
    avalon_slave_readdata    <= w_avalon_slave_readdata;

    ------------------------------------------------------------------
    -- Avalon handshake
    -- waitrequest='0' : always ready
    -- readdatavalid registered to align with the clocked read mux
    ------------------------------------------------------------------
    avalon_slave_waitrequest <= '0';

    process(clock_sink_clk)
    begin
        if rising_edge(clock_sink_clk) then
            avalon_slave_readdatavalid <= avalon_slave_read;
        end if;
    end process;

    ------------------------------------------------------------------
    -- 1-Wire bus control
    ------------------------------------------------------------------
    ow_oe <= w_reset_dq_oe or w_read_dq_oe or w_write_dq_oe;

    w_reset_dq_in <= ow_in;
    w_read_dq_in  <= ow_in;
    w_write_dq_in <= ow_in;

end architecture rtl;