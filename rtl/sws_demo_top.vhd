library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sws_demo_top is
    Port (
        i_clk_p       : in    std_logic;
        i_rst_n       : in    std_logic;
        io_one_wire   : inout std_logic;
        o_led         : out   std_logic_vector(3 downto 0)
    );
end sws_demo_top;

architecture Behavioral of sws_demo_top is

    signal w_rst : std_logic;
    signal w_ow_in        : std_logic;
    signal w_ow_oe        : std_logic;
    signal w_pio_out      : std_logic_vector(3 downto 0);

    -- Avalon-MM interconnect signals

    signal w_avalon_slave_waitrequest   : std_logic;
    signal w_avalon_slave_readdatavalid : std_logic;



    signal avalon_slave_waitrequest   : std_logic;
    signal avalon_slave_readdatavalid : std_logic;

    signal avalon_slave_read          : std_logic;
    signal avalon_slave_write         : std_logic;

    signal avalon_slave_address       : std_logic_vector(7 downto 0);
    signal avalon_slave_writedata     : std_logic_vector(31 downto 0);
    signal avalon_slave_readdata      : std_logic_vector(31 downto 0);

    signal mm_bridge_0_m0_burstcount      : std_logic_vector(0 downto 0);
    signal mm_bridge_0_m0_byteenable      : std_logic_vector(3 downto 0);
    signal mm_bridge_0_m0_debugaccess     : std_logic;
    signal mm_bridge_0_m0_address          : std_logic_vector(7 downto 0);
    signal mm_bridge_0_m0_write            : std_logic;
    signal mm_bridge_0_m0_read             : std_logic;
    signal mm_bridge_0_m0_writedata         : std_logic_vector(31 downto 0);
    signal mm_bridge_0_m0_readdata         : std_logic_vector(31 downto 0);
    signal mm_bridge_0_m0_readdatavalid    : std_logic;
    signal mm_bridge_0_m0_waitrequest       : std_logic;


    signal w_avalon_slave_read          : std_logic;
    signal w_avalon_slave_write         : std_logic;

    signal w_avalon_slave_address       : std_logic_vector(7 downto 0);
    signal w_avalon_slave_writedata     : std_logic_vector(31 downto 0);
    signal w_avalon_slave_readdata : std_logic_vector(31 downto 0) := (others => '0');
    signal heartbeat_counter : unsigned(24 downto 0) := (others => '0');

    component sws_niosv is
		port (
			clk_clk                          : in  std_logic                     := '0';             --                       clk.clk
			mm_bridge_0_m0_waitrequest       : in  std_logic                     := '0';             --            mm_bridge_0_m0.waitrequest
			mm_bridge_0_m0_readdata          : in  std_logic_vector(31 downto 0) := (others => '0'); --                          .readdata
			mm_bridge_0_m0_readdatavalid     : in  std_logic                     := '0';             --                          .readdatavalid
            mm_bridge_0_m0_burstcount        : out std_logic_vector(0 downto 0);                     --                          .burstcount
			mm_bridge_0_m0_writedata         : out std_logic_vector(31 downto 0);                    --                          .writedata
			mm_bridge_0_m0_address           : out std_logic_vector(7 downto 0);                     --                          .address
			mm_bridge_0_m0_write             : out std_logic;                                        --                          .write
			mm_bridge_0_m0_read              : out std_logic;                                        --                          .read
			mm_bridge_0_m0_byteenable        : out std_logic_vector(3 downto 0);                     --                          .byteenable
			mm_bridge_0_m0_debugaccess       : out std_logic;                                        --                          .debugaccess
			pio_0_external_connection_export : out std_logic_vector(3 downto 0);                     -- pio_0_external_connection.export
			reset_reset                    : in  std_logic                     := '0'              --                     reset.reset
		);
    end component;

    component sws_top is
		 port (
			  clock_sink_clk             : in  std_logic := '0';
			  reset_sink_reset           : in  std_logic := '0';
			  avalon_slave_read          : in  std_logic := '0';
			  avalon_slave_write         : in  std_logic := '0';
			  avalon_slave_waitrequest   : out std_logic;
			  avalon_slave_address       : in  std_logic_vector(7 downto 0) := (others => '0');
			  avalon_slave_readdatavalid : out std_logic;
              avalon_slave_readdata      : out std_logic_vector(31 downto 0) := (others=>'0');
			  avalon_slave_writedata     : in  std_logic_vector(31 downto 0) := (others=>'0');
			  ow_in                      : in  std_logic;
			  ow_oe                      : out std_logic
		 );
    end component;

begin

    w_rst <= not i_rst_n;

    --nios instantiation
    nios_inst : sws_niosv
        port map (
            clk_clk                                     => i_clk_p,
            reset_reset                                 => w_rst,
            mm_bridge_0_m0_waitrequest                  => w_avalon_slave_waitrequest,
            mm_bridge_0_m0_readdata                     => w_avalon_slave_readdata,
            mm_bridge_0_m0_readdatavalid              => w_avalon_slave_readdatavalid,  
            mm_bridge_0_m0_writedata                    => w_avalon_slave_writedata,
            mm_bridge_0_m0_address                      => w_avalon_slave_address,
            mm_bridge_0_m0_write                        => w_avalon_slave_write,
            mm_bridge_0_m0_read                         => w_avalon_slave_read,

            pio_0_external_connection_export            => w_pio_out, -- Connect PIO output to LEDs for debugging

            mm_bridge_0_m0_burstcount                   => open, -- Not used in this design
            mm_bridge_0_m0_byteenable                   => open, -- Not used in this design
            mm_bridge_0_m0_debugaccess                  => open -- Not used in this design
        );

    ow_inst : sws_top
        port map (
            clock_sink_clk                                     => i_clk_p,
            reset_sink_reset                                   => w_rst,
            avalon_slave_read                                  => avalon_if.avalon_read,
            avalon_slave_write                                 => avalon_if.avalon_write,
            avalon_slave_waitrequest                           => avalon_if.avalon_waitrequest,
            avalon_slave_address                               => avalon_if.avalon_address, -- Only lower 8 bits for address
            avalon_slave_readdata                              => avalon_if.avalon_readdata,
            avalon_slave_readdatavalid                         => avalon_if.avalon_readdatavalid,
            avalon_slave_writedata                             => avalon_if.avalon_writedata,
            ow_in                                              => w_ow_in,
            ow_oe                                              => w_ow_oe

        );

        -- Heartbeat counter
    process(i_clk_p, i_rst_n)
    begin
        if i_rst_n = '0' then
            heartbeat_counter <= (others => '0');
        elsif rising_edge(i_clk_p) then
            heartbeat_counter <= heartbeat_counter + 1;
        end if;
    end process;

    --led control
    o_led(0) <= heartbeat_counter(24);
    o_led(1) <= w_pio_out(1);
    o_led(2) <= i_clk_p;
    o_led(3) <= w_pio_out(3);

    --tristate logic
    io_one_wire <= '0' when w_ow_oe = '1' else 'Z';
    w_ow_in     <= io_one_wire;

end Behavioral;