library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sws_reset is
    generic(ClockFrequencyHz : integer := 50000000);
    port(
        clk    : in  std_logic;
        rst    : in  std_logic;
        go     : in  std_logic;
        busy   : out std_logic;
        done   : out std_logic;
        dq_in  : in  std_logic;
        dq_oe  : out std_logic    -- drive low when '1'
    );
end entity;

architecture Behavioral of sws_reset is

    -- FSM states
    type state_type is (
        IDLE,
        START_RESET_LOW,
        BUSY_START_RESET_LOW,
        HOST_RELEASE,
        HOST_LOW,
        SAMPLE,
        ACK_RESET_DONE,
        NACK_RESET_DONE
    );

    signal state, next_state : state_type;

    -- Timer constants (for 50 MHz)
    constant FREQ_MHZ : integer := 50;

    constant tRESET  : integer := 96  * FREQ_MHZ;  -- time to hold reset low (96us)
    constant tRRT    : integer := 8   * FREQ_MHZ;  -- time from host release to host pulling low again (8us)
    constant tDRR    : integer := 1   * FREQ_MHZ; -- time from host pulling low again to sampling (1us)
    constant tMSDR   : integer := 2   * FREQ_MHZ; -- minimum time from master driving line low to releasing for sample (2us)
    constant tDACK   : integer := 8   * FREQ_MHZ; -- time from sampling to when ACK/NACK is expected (8us)
    constant tDSCHG  : integer := 480 * FREQ_MHZ; -- time to wait after a reset attempt before trying again (480us)
    constant tHTSS   : integer := 150 * FREQ_MHZ; -- time required after STOP condition before a new START condition can be issued


    constant tTEST   : integer := 8 * FREQ_MHZ;

    -- Timer counters
    signal tRESET_counter  : integer range 0 to 4800  := 0;
    signal tRRT_counter    : integer range 0 to 400   := 0;
    signal tDRR_counter    : integer range 0 to 50    := 0;
    signal tMSDR_counter   : integer range 0 to 100   := 0;
    signal tDACK_counter   : integer range 0 to 500   := 0;
    signal tDSCHG_counter  : integer range 0 to 25000 := 0;
    signal tHTSS_counter  : integer range 0 to 7500  := 0;

    --temporary counter 
    signal tTEST_counter  : integer range 0 to 480  := 0;

    signal slave_bit : std_logic := '1';
    signal w_busy_rw : std_logic := '0';

begin
   

    ------------------------------------------------------------------
    -- TIMER PROCESS
    ------------------------------------------------------------------
    timers_process : process(clk, rst)
    begin
        if rst = '1' then
            tRESET_counter  <= 0;
            tRRT_counter    <= 0;
            tDRR_counter    <= 0;
            tMSDR_counter   <= 0;
            tDACK_counter   <= 0;
            tDSCHG_counter  <= 0;
            
            tTEST_counter   <= 0;

        elsif rising_edge(clk) then

            if tRESET_counter  > 0 then tRESET_counter  <= tRESET_counter  - 1; end if;
            if tRRT_counter    > 0 then tRRT_counter    <= tRRT_counter    - 1; end if;
            if tDRR_counter    > 0 then tDRR_counter    <= tDRR_counter    - 1; end if;
            if tMSDR_counter   > 0 then tMSDR_counter   <= tMSDR_counter   - 1; end if;
            if tDACK_counter   > 0 then tDACK_counter   <= tDACK_counter   - 1; end if;
            if tDSCHG_counter  > 0 then tDSCHG_counter  <= tDSCHG_counter  - 1; end if;
            --temporary timer
            if tTEST_counter  > 0 then tTEST_counter  <= tTEST_counter  - 1; end if;
           
            
            
            if next_state /= state then
                tRESET_counter  <= tRESET;
                tRRT_counter    <= tRRT;
                tDRR_counter    <= tDRR;
                tMSDR_counter   <= tMSDR;
                tDACK_counter   <= tDACK;
                tDSCHG_counter  <= tDSCHG;
                tHTSS_counter   <= tHTSS;
                tTEST_counter   <= tTEST;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- STATE REGISTER
    ------------------------------------------------------------------
    fsm_state_process : process(clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ------------------------------------------------------------------
    -- FSM LOGIC 
    ------------------------------------------------------------------
    fsm_logic_process : process(
        state, go, dq_in,
        tRESET_counter, tDSCHG_counter,
        tRRT_counter, tDACK_counter, tDRR_counter,thtss_counter
    )
    begin
        -- Defaults
        next_state <= state;
        dq_oe      <= '0';  -- release bus by default
        busy       <= '0';
        done       <= '0';
    
        case state is

            when IDLE =>
            dq_oe <= '0';
                if go = '1'  then
                    next_state <= START_RESET_LOW;
                --elsif go = '1' then
                   -- next_state <= BUSY_START_RESET_LOW;  -- currently not in use 
                end if;

            when START_RESET_LOW =>
                dq_oe <= '1';  -- pull line low
                busy <= '1';
                if tRESET_counter = 0 then
                    next_state <= HOST_RELEASE;
                end if;
            
            when BUSY_START_RESET_LOW =>                    --dq_oe will remain '1' NOT IN USE CURRENTLY
                dq_oe <= '1';  -- pull line low
                
                if tDSCHG_counter = 0 then
                    next_state <= IDLE;
                end if;

            when HOST_RELEASE =>
                dq_oe <= '0';  -- release bus
                busy  <= '1';

                if tRRT_counter = 0 then
                    next_state <= HOST_LOW;
                end if;

            when HOST_LOW =>
                dq_oe <= '1';  -- pull low again
                busy  <= '1';

                if tDRR_counter = 0 then
                    next_state <= SAMPLE;
                end if;

            when SAMPLE =>
                dq_oe <= '0';  -- release for sampling
                busy  <= '1';

                if tDACK_counter < 250  then
                        if dq_in = '1' then
                            next_state <= ACK_RESET_DONE;
                        else
                            next_state <= NACK_RESET_DONE;
                        end if;
                end if;

            when ACK_RESET_DONE => --ack recieved and reset successful
                dq_oe <= '0';
                busy  <= '0';
                done  <= '1';
                if tHTSS_counter = 0 then
                    next_state <= IDLE;
                end if;

            when NACK_RESET_DONE => -- NACK received and reset failed
                dq_oe <= '0';
                busy  <= '0';
                done  <= '0';
                if tHTSS_counter = 0 then
                    next_state <= IDLE;
                end if;




        end case;
    end process;

end architecture;
