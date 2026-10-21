library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sws_read is
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        r_done       : out std_logic;
        dq_in        : in  std_logic;
        dq_oe        : out std_logic;
        busy         : out std_logic;
        read         : in  std_logic;
        address      : in  std_logic_vector(7 downto 0);
        mode         : in  std_logic_vector(3 downto 0);
        serial_bytes : out std_logic_vector(63 downto 0);
        device       : in std_logic_vector(2 downto 0)
    );
end entity;

architecture Behavioral of sws_read is

    type state_type is ( -- all states used; in somewhat of an orderly fashion. Some return states are shared between the 3 bit select states so its not strictly linear
        IDLE, START,
        DEVICE_BIT_SELECT,
        ADDRESS_BIT_SELECT,
        DEVICE_BIT_SELECT_1,
        SEND_ZERO_LOW, SEND_ZERO_HIGH,
        SEND_ONE_LOW,  SEND_ONE_HIGH,
        ACK_RELEASE0, ACK_WAIT0,
        ACK_RELEASE1, ACK_WAIT1,
        ACK_RELEASE2, ACK_WAIT2,
        START_1,
        BIT_LOW, BIT_WAIT,
        HOST_ACK, HOST_ACK_RELEASE,
        HOST_NACK,
        STOP
    );

    signal state, next_state, return_state : state_type;


    -- Timer constants (for 50 MHz)
    constant FREQ_MHZ : integer := 50;
    constant tRD      : integer := 2   * FREQ_MHZ;
    constant tBIT     : integer := 25  * FREQ_MHZ;
    constant tLOW0    : integer := 6   * FREQ_MHZ;
    constant tLOW1    : integer := 1   * FREQ_MHZ;
    constant tMRS     : integer := 6   * FREQ_MHZ;
    constant tHTSS    : integer := 150 * FREQ_MHZ;
    constant tDACK    : integer := 24  * FREQ_MHZ;
    --Timer counters , this is what will actually decrement and be checked for
    signal tRD_counter   : integer range 0 to 100  := tRD;
    signal tBIT_counter  : integer range 0 to 1250 := tBIT;
    signal tMRS_counter  : integer range 0 to 300  := tMRS;
    signal tLOW0_counter : integer range 0 to 300  := tLOW0;
    signal tLOW1_counter : integer range 0 to 50   := tLOW1;
    signal tHTSS_counter : integer range 0 to 7500 := tHTSS;
    signal tDACK_counter : integer range 0 to 1200 := tDACK;

    -- internal signals for different bytes , the device address byte and memory address byte 
    signal w_dev_byte  : std_logic_vector(7 downto 0);
    signal w_addr_byte : std_logic_vector(7 downto 0); -- keep in mind that addr_byte goes to its own specific register , it is not part of the 64 bit array below

    -- bytes replaced single w_rd_byte with 8-element array
    type t_byte_array is array (0 to 7) of std_logic_vector(7 downto 0);
    signal w_rd_bytes : t_byte_array := (others => (others => '0'));
    signal dev_bits : std_logic_vector(2 downto 0);

    --these count the number of bits and bytes sent or recieved so far. they are used for flow control/next state decisions
    signal n_bit  : integer range 0 to 8 := 0;
    signal n_byte : integer range 0 to 8 := 0;

    -- means the same as mode but i just added another layer on top of that because i dont like using the mode signal directly :P
    signal type_1 : std_logic := '0';
    signal type_2 : std_logic := '0';
    signal type_3 : std_logic := '0';
    signal type_4 : std_logic := '0';
    signal type_5 : std_logic := '0';
    signal type_6 : std_logic := '0';


    -- these are preloaded , theyll never need to be changed
    signal random_read_byte   : std_logic_vector(7 downto 0) ;
    signal security_reg_sequential_read : std_logic_vector(7 downto 0) ; 
    signal eeprom_reg_sequential_read : std_logic_vector(7 downto 0) ;

begin

    -- wire all 8 bytes to output
    -- Single-byte modes only write to w_rd_bytes(0), remaining bytes stay 0
    serial_bytes <= w_rd_bytes(0) & w_rd_bytes(1) & w_rd_bytes(2) & w_rd_bytes(3) &
                    w_rd_bytes(4) & w_rd_bytes(5) & w_rd_bytes(6) & w_rd_bytes(7);


    random_read_byte <= "1010" & dev_bits & '1';
    security_reg_sequential_read <= "1011" & dev_bits & '1';
    eeprom_reg_sequential_read <= "1010" & dev_bits & '0';

    w_addr_byte <= address;
    dev_bits    <= device;

    ------------------------------------------------------------------
    -- TIMER PROCESS
    ------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            tLOW0_counter <= 0;
            tLOW1_counter <= 0;
            tBIT_counter  <= 0;
            tRD_counter   <= 0;
            tMRS_counter  <= 0;
            tHTSS_counter <= 0;
            tDACK_counter <= 0;
        elsif rising_edge(clk) then
            if tLOW0_counter > 0 then tLOW0_counter <= tLOW0_counter - 1; end if;
            if tLOW1_counter > 0 then tLOW1_counter <= tLOW1_counter - 1; end if;
            if tRD_counter   > 0 then tRD_counter   <= tRD_counter   - 1; end if;
            if tMRS_counter  > 0 then tMRS_counter  <= tMRS_counter  - 1; end if;
            if tBIT_counter  > 0 then tBIT_counter  <= tBIT_counter  - 1; end if;
            if tDACK_counter > 0 then tDACK_counter <= tDACK_counter - 1; end if;
            if tHTSS_counter > 0 then tHTSS_counter <= tHTSS_counter - 1; end if;

            if state /= next_state then -- I've made it so ALL timers get loaded at the start of every state, its just simpler than being state-specific about it and
                                        -- the counters won't be used unless relevant in each state anyway
                tLOW0_counter <= tLOW0;
                tLOW1_counter <= tLOW1;
                tRD_counter   <= tRD;
                tMRS_counter  <= tMRS;
                tBIT_counter  <= tBIT;
                tHTSS_counter <= tHTSS;
                tDACK_counter <= tDACK;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- STATE REGISTER + RETURN STATE
    ------------------------------------------------------------------
    process(clk, rst) -- this ensures that when we return from sending bits to either bit select state, we return to the correct one based on where we came 
                            --from (device bit select, address bit select, or device bit select 1)
    begin
        if rst = '1' then
            state        <= IDLE;
            return_state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
            if state = DEVICE_BIT_SELECT then
                return_state <= DEVICE_BIT_SELECT;

            elsif state = ADDRESS_BIT_SELECT then
                return_state <= ADDRESS_BIT_SELECT;

            elsif state = DEVICE_BIT_SELECT_1 then
                return_state <= DEVICE_BIT_SELECT_1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- FSM LOGIC
    ------------------------------------------------------------------
    process(state, read, dq_in,
            tRD_counter, tBIT_counter, tHTSS_counter,
            tLOW1_counter, tLOW0_counter, tMRS_counter,
            n_bit, n_byte, w_dev_byte, w_addr_byte,
            type_1, type_2, type_3, type_4,type_5, type_6, return_state)
        variable current_bit : std_logic;
    begin
        next_state <= state;
        dq_oe      <= '0';
        busy       <= '0';
        r_done     <= '0';

        case state is

            when IDLE =>
                if read = '1' then
                    next_state <= START;
                end if;

            when START =>
                dq_oe <= '0';
                busy  <= '1';
                if tHTSS_counter = 0 then
                    next_state <= DEVICE_BIT_SELECT;
                end if;

            when DEVICE_BIT_SELECT =>
                dq_oe <= '0';
                busy  <= '1';
                if n_bit < 8 then
                    current_bit := w_dev_byte(7-n_bit);
                    if current_bit = '1' then
                        next_state <= SEND_ONE_LOW;
                    else
                        next_state <= SEND_ZERO_LOW;
                    end if;
                else
                    next_state <= ACK_RELEASE0;
                end if;

            when ADDRESS_BIT_SELECT =>
                dq_oe <= '0';
                busy  <= '1';
                if n_bit < 8 then
                    current_bit := w_addr_byte(7-n_bit);
                    if current_bit = '1' then
                        next_state <= SEND_ONE_LOW;
                    else
                        next_state <= SEND_ZERO_LOW;
                    end if;
                else
                    next_state <= ACK_RELEASE1;
                end if;

            when DEVICE_BIT_SELECT_1 =>
                dq_oe <= '0';
                busy  <= '1';
                if n_bit < 8 then
                    if type_3 = '1' then
                        current_bit := random_read_byte(7-n_bit);
                    elsif type_4 = '1' then
                        current_bit := security_reg_sequential_read(7-n_bit);
                    elsif type_5 = '1' then
                        current_bit := eeprom_reg_sequential_read(7-n_bit);
                    end if;

                    if type_3 = '1' or type_4 = '1' or type_5 = '1' then
                        if current_bit = '1' then
                            next_state <= SEND_ONE_LOW;
                        else
                            next_state <= SEND_ZERO_LOW;
                        end if;
                    end if;
                else
                    next_state <= ACK_RELEASE2;
                end if;

            when SEND_ZERO_LOW =>
                dq_oe <= '1';
                busy  <= '1';
                if tLOW0_counter = 0 then
                    next_state <= SEND_ZERO_HIGH;
                end if;

            when SEND_ZERO_HIGH =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= return_state;
                end if;

            when SEND_ONE_LOW =>
                dq_oe <= '1';
                busy  <= '1';
                if tLOW1_counter = 0 then
                    next_state <= SEND_ONE_HIGH;
                end if;

            when SEND_ONE_HIGH =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= return_state;
                end if;

            when ACK_RELEASE0 => --all ACK_RELEASE and ACK_WAIT states have the same structure, just different next states based on the type of read and 
                                 -- which bit/byte we are on , i couldve used the return_state variable to simplify this but i felt it was more clear to just
                                 -- write out the specific next states for each case instead of trying to be clever with it 
                                 --(i am lazy and i am now justifying that laziness with "clarity")
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter = (tMRS-tRD)/2 and dq_in = '0' then
                    next_state <= ACK_WAIT0;
                elsif tMRS_counter = 0 and dq_in = '1' then
                    next_state <= IDLE;
                end if;

            when ACK_WAIT0 =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    if type_1 = '1' then
                        next_state <= BIT_LOW;
                    elsif type_2 = '1' then
                        next_state <= BIT_LOW;
                    elsif type_3 = '1' or type_4 = '1' or type_5 = '1' then
                        next_state <= ADDRESS_BIT_SELECT;
                    end if;
                end if;

            when ACK_RELEASE1 =>
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter = (tMRS-tRD)/2 and dq_in = '0' then
                    next_state <= ACK_WAIT1;
                elsif tMRS_counter = 0 and dq_in = '1' then
                    next_state <= IDLE;
                end if;

            when ACK_WAIT1 =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= START_1;
                end if;

            when START_1 =>
                dq_oe <= '0';
                busy  <= '1';
                if tHTSS_counter = 0 then
                    next_state <= DEVICE_BIT_SELECT_1;
                end if;

            when ACK_RELEASE2 =>
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter = (tMRS-tRD)/2 and dq_in = '0' then
                    next_state <= ACK_WAIT2;
                elsif tMRS_counter = 0 and dq_in = '1' then
                    next_state <= IDLE;
                end if;

            when ACK_WAIT2 =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= BIT_LOW;
                end if;

            when BIT_LOW =>       -- this is where the host brings the line low to ask for a bit 
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter = (tMRS-tRD)/2 then
                    next_state <= BIT_WAIT;
                end if;

            when BIT_WAIT => -- we are now waiting for a bit to from the client , depending on the values of n_bit and n_byte this bit will get routed to the correct place
                             -- and we will decide whether to ACK it or not
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    if type_1 = '1' then
                        if n_bit = 7 and n_byte = 2 then
                            next_state <= HOST_NACK;
                        elsif n_bit = 7 and n_byte < 2 then
                            next_state <= HOST_ACK;
                        else
                            next_state <= BIT_LOW;
                        end if;
                    elsif type_2 = '1' then
                        if n_bit = 7 then
                            next_state <= HOST_NACK;
                        else
                            next_state <= BIT_LOW;
                        end if;
                    elsif type_3 = '1' then
                        if n_bit = 7 then
                            next_state <= HOST_NACK;
                        else
                            next_state <= BIT_LOW;
                        end if;
                    elsif type_4 = '1' or type_5 = '1' then
                        if n_bit < 7 then
                            next_state <= BIT_LOW;
                        elsif n_bit = 7 and n_byte < 7 then
                            next_state <= HOST_ACK;
                        elsif n_bit = 7 and n_byte = 7 then
                            next_state <= HOST_NACK;
                        end if;
                    end if;
                end if;

            when HOST_ACK =>
                dq_oe <= '1';
                busy  <= '1';
                if tLOW0_counter = 0 then
                    next_state <= HOST_ACK_RELEASE;
                end if;

            when HOST_ACK_RELEASE =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= BIT_LOW;
                end if;

            when HOST_NACK => -- this means the End of the whole transaction whether successfull or unsuccessfull
                dq_oe <= '1';
                busy  <= '1';
                if tLOW1_counter = 0 then
                    next_state <= STOP;
                end if;

            when STOP =>
                dq_oe  <= '0';
                r_done <= '1';
                if tHTSS_counter = 0 then
                    next_state <= IDLE;
                end if;

        end case;
    end process;

    ------------------------------------------------------------------
    -- CLOCKED SAMPLING PROCESS
    -- Each byte is stored at its own index as it arrives
    -- this is what decides which byte we are on and routes the incoming bits to the correct byte register
    ------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            w_rd_bytes <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if state = BIT_LOW and tMRS_counter = (tMRS-tRD)/2 then
                w_rd_bytes(n_byte)(7 - n_bit) <= dq_in;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- BIT / BYTE COUNTER
    --here n_bit and n_byte get incremented based on the state transitions,
    -- or they get reset to 0 , if youre getting issues where only 5 out of 8 bits are getting read , this is the place to check as well as the BIT_WAIT state because thats where the flow control is 
    --(that should never be an issue though )
    -------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            n_bit  <= 0;
            n_byte <= 0;
        elsif rising_edge(clk) then

            if (state = SEND_ZERO_HIGH or state = SEND_ONE_HIGH) and tBIT_counter = 0 then
                n_bit <= n_bit + 1;
            end if;

            if state = BIT_WAIT and
               (next_state = BIT_LOW or next_state = HOST_ACK or next_state = HOST_NACK) then
                n_bit <= n_bit + 1;
            end if;

            if state = BIT_WAIT and next_state = HOST_ACK then
                n_byte <= n_byte + 1;
            end if;

            if state = DEVICE_BIT_SELECT and next_state = ACK_RELEASE0 then
                n_bit <= 0;
            end if;

            if state = ADDRESS_BIT_SELECT and next_state = ACK_RELEASE1 then
                n_bit <= 0;
            end if;

            if state = DEVICE_BIT_SELECT_1 and next_state = ACK_RELEASE2 then
                n_bit <= 0;
            end if;

            if state = HOST_ACK then
                n_bit <= 0;
            end if;

            if state = STOP and next_state = IDLE then
                n_bit  <= 0;
                n_byte <= 0;
            end if;

        end if;
    end process;

    ------------------------------------------------------------------
    -- MODE DECODER
    --here, hardcoded bytes are assigned and modes are converted to the type_n signal 
    ------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            w_dev_byte <= (others => '0');
            type_1     <= '0';
            type_2     <= '0';
            type_3     <= '0';
            type_4     <= '0';
            type_5     <= '0';
            type_6     <= '0';

        elsif rising_edge(clk) then
            if    mode = "0001" then -- manufacturer ID read
                w_dev_byte <= "1100" & dev_bits & '1';
                type_1     <= '1';
                type_2     <= '0';
                type_3     <= '0';
                type_4     <= '0';
                type_5     <= '0';
                type_6     <= '0';

            elsif mode = "0010" then -- current address read
                w_dev_byte <= "1010" & dev_bits & '1';
                type_1     <= '0';
                type_2     <= '1';
                type_3     <= '0';
                type_4     <= '0';
                type_5     <= '0';
                type_6     <= '0';

            elsif mode = "0100" then -- random address read
                w_dev_byte <= "1010" & dev_bits & '0';
                type_1     <= '0';
                type_2     <= '0';
                type_3     <= '1';
                type_4     <= '0';
                type_5     <= '0';
                type_6     <= '0';

            elsif mode = "1000" then -- serial number read aka security register sequential read
                w_dev_byte <= "1011" & dev_bits & '0';
                type_1     <= '0';
                type_2     <= '0';
                type_3     <= '0';
                type_4     <= '1';
                type_5     <= '0';
                type_6     <= '0';

            elsif mode = "0011" then -- sequential read EEPROM
                w_dev_byte <= "1010" & dev_bits & '0';
                type_1     <= '0';
                type_2     <= '0';
                type_3     <= '0';
                type_4     <= '0';
                type_5     <= '1';
                type_6     <= '0'; -- type 6 is never used


            else
                w_dev_byte <= (others => '0');
                type_1     <= '0';
                type_2     <= '0';
                type_3     <= '0';
                type_4     <= '0';
                type_5     <= '0';
                type_6     <= '0';
                
            end if;
        end if;
    end process;

end architecture;