library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sws_write is
    generic(ClockFrequencyHz : integer := 50000000);
    port(
        clk     : in  std_logic;
        rst     : in  std_logic;
        w_done  : out std_logic;
        dq_in   : in  std_logic;
        dq_oe   : out std_logic;
        busy    : out std_logic;
        write   : in  std_logic;
        mode    : in  std_logic_vector(2 downto 0);
        address : in  std_logic_vector(7 downto 0);
        serial_bytes    : in  std_logic_vector(63 downto 0);
        device  : in  std_logic_vector(2 downto 0)
    );
end entity;

architecture Behavioral of sws_write is

    type state_type is (
        IDLE,
        START,
        DEVICE_BIT_SELECT,
        ADDR_BIT_SELECT,
        DATA_BIT_SELECT,
        SEND_ONE_LOW,
        SEND_ONE_HIGH,
        SEND_ZERO_LOW,
        SEND_ZERO_HIGH,
        ACK_RELEASE0,
        ACK_RELEASE1,
        ACK_RELEASE2,
        ACK_WAIT0,
        ACK_WAIT1,
        ACK_WAIT2,
        NACK,       -- host sends no-acknowledge to terminate the write transaction (dq_oe='0' for tLOW1)
        STOP
    );

    signal state, next_state : state_type;
    signal return_state      : state_type;

    constant FREQ_MHZ : integer := 50;
    constant tLOW0    : integer := 6   * FREQ_MHZ;
    constant tLOW1    : integer := 1   * FREQ_MHZ;
    constant tBIT     : integer := 25  * FREQ_MHZ;
    constant tHTSS    : integer := 150 * FREQ_MHZ;
    constant tMRS     : integer := 2   * FREQ_MHZ;
    constant tRD      : integer := 1   * FREQ_MHZ;

    signal tLOW0_counter : integer range 0 to 300  := 0;
    signal tLOW1_counter : integer range 0 to 50   := 0;
    signal tBIT_counter  : integer range 0 to 1250 := 0;
    signal tHTSS_counter : integer range 0 to 7500 := 0;
    signal tMRS_counter  : integer range 0 to 400  := 0;
    signal tRD_counter   : integer range 0 to 50   := 0;

    type t_byte_array is array (0 to 7) of std_logic_vector(7 downto 0);

    signal wr_bytes : t_byte_array := (others => (others => '0'));

    signal addr_byte : std_logic_vector(7 downto 0);
    signal dev_byte  : std_logic_vector(7 downto 0);
    signal dev_bits  : std_logic_vector(2 downto 0);

    signal n_bit      : integer range 0 to 8 := 0;  -- bit counter (within a byte)
    signal n_byte : integer range 0 to 8 := 0;  -- byte counter (across all data bytes sent)
    -- mode type flags, mirrors the approach used in sws_read for consistency
    -- type_1: mode "01" -> 1 data byte to eeprom (single byte write)
    -- type_2: mode "10" -> 1 data bytes to security reg
    -- type_3: mode "11" -> 4 data bytes to security reg
    -- type_4: mode "00" -> 8 data bytes to security reg
    signal type_1 : std_logic := '0';
    signal type_2 : std_logic := '0';
    signal type_3 : std_logic := '0';
    signal type_4 : std_logic := '0';
    signal type_5 : std_logic := '0';

begin

    process(clk, rst)
    begin
        if rst = '1' then
            wr_bytes <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if state = IDLE and write = '1' then
                for i in 0 to 7 loop
                    wr_bytes(i) <= serial_bytes(63 - i*8 downto 56 - i*8);
                end loop;
            end if;
        end if;
    end process;

    ------------------timer process--------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            tLOW0_counter <= 0;
            tLOW1_counter <= 0;
            tBIT_counter  <= 0;
            tHTSS_counter <= 0;
            tMRS_counter  <= 0;
            tRD_counter   <= 0;
        elsif rising_edge(clk) then
            if tLOW0_counter > 0 then tLOW0_counter <= tLOW0_counter - 1; end if;
            if tLOW1_counter > 0 then tLOW1_counter <= tLOW1_counter - 1; end if;
            if tBIT_counter  > 0 then tBIT_counter  <= tBIT_counter  - 1; end if;
            if tHTSS_counter > 0 then tHTSS_counter <= tHTSS_counter - 1; end if;
            if tMRS_counter  > 0 then tMRS_counter  <= tMRS_counter  - 1; end if;
            if tRD_counter   > 0 then tRD_counter   <= tRD_counter   - 1; end if;

            if state /= next_state then
                tLOW0_counter <= tLOW0;
                tLOW1_counter <= tLOW1;
                tBIT_counter  <= tBIT;
                tHTSS_counter <= tHTSS;
                tMRS_counter  <= tMRS;
                tRD_counter   <= tRD;
            end if;
        end if;
    end process;

    -------------------------bit + byte counting process-------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            n_bit      <= 0;
            n_byte <= 0;
        elsif rising_edge(clk) then

            -- n_bit (bit counter): increment each time a bit is successfully sent
            if (state = SEND_ZERO_HIGH or state = SEND_ONE_HIGH) and tBIT_counter = 0 then
                n_bit <= n_bit + 1;
            end if;

            -- n_bit reset: clear at the end of each byte phase (entering its ACK state)
            if (state = DEVICE_BIT_SELECT and next_state = ACK_RELEASE0) or
               (state = ADDR_BIT_SELECT   and next_state = ACK_RELEASE1) or
               (state = DATA_BIT_SELECT   and next_state = ACK_RELEASE2) then
                n_bit <= 0;
            end if;

            -- n_byte (byte counter): increments each time a full data byte is sent
            -- checked in ACK_WAIT2 to decide whether to loop back or move to NACK
            if state = DATA_BIT_SELECT and next_state = ACK_RELEASE2 then
                n_byte <= n_byte + 1;
            end if;

            -- n_byte reset: clear when the operation is fully complete
            if state = STOP and next_state = IDLE then
                n_byte <= 0;
            end if;

        end if;
    end process;

    ---------------------state reg + return state tracking------------------------------------------
    -- return_state records which BIT_SELECT state we came from so that after
    -- SEND_ONE/ZERO the FSM knows which bit-select state to return to
    process(clk, rst)
    begin
        if rst = '1' then
            state        <= IDLE;
            return_state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
            if (state = DEVICE_BIT_SELECT or
                state = ADDR_BIT_SELECT   or
                state = DATA_BIT_SELECT) and
               (next_state = SEND_ZERO_LOW or next_state = SEND_ONE_LOW) then
                return_state <= state;
            end if;
        end if;
    end process;

    ---------------------byte + mode capture----------------------------------------------
    -- captures all inputs on the rising edge when a write is triggered from IDLE
    -- also sets the type_N flag and constructs the device address byte from the mode
    -- NOTE: 'device' is used directly here (not dev_bits) to avoid a 1-cycle delay
    --       since dev_bits is registered and would hold the previous value otherwise
    process(clk, rst)
    begin
        if rst = '1' then


            addr_byte <= (others => '0');
            dev_byte  <= (others => '0');
            dev_bits  <= (others => '0');
            type_1    <= '0';
            type_2    <= '0';
            type_3    <= '0';
            type_4    <= '0';
            type_5    <= '0';

        elsif rising_edge(clk) then
            if state = IDLE and write = '1' then
                addr_byte <= address;
                dev_bits  <= device;

                -- type flags and device address byte set from mode at time of trigger
                if mode = "000" then                           -- single byte write within eeprom
                    dev_byte <= "1010" & device & '0';
                    type_1   <= '1';
                    type_2   <= '0';
                    type_3   <= '0';
                    type_4   <= '0';
                    type_5    <= '0';
                elsif mode = "001" then                        -- 8-byte write within EEPROM
                    dev_byte <= "1011" & device & '0';
                    type_1   <= '0';
                    type_2   <= '1';
                    type_3   <= '0';
                    type_4   <= '0';
                    type_5    <= '0';
                elsif mode = "010" then                        -- single-byte write within security reg
                    dev_byte <= "1011" & device & '0';
                    type_1   <= '0';
                    type_2   <= '0';
                    type_3   <= '1';
                    type_4   <= '0';
                    type_5    <= '0';
                    
                elsif mode = "011" then                        -- 8-byte write within security reg
                    dev_byte <= "1011" & device & '0';
                    type_1   <= '0';
                    type_2   <= '0';
                    type_3   <= '0';
                    type_4   <= '1';
                    type_5   <= '0';

                elsif mode = "111" then               --SECURITY REG LOG DO NOT DO THIS UNLESS YOU KNOW WHAT YOU ARE DOING THIS WILL LOCK THE SECURITY REG PERMANENTLY  AND NO FURTHER WRITES CAN BE MADE TO IT
                    dev_byte <= "0010" & device & '0';
                    type_1   <= '0';
                    type_2   <= '0';
                    type_3   <= '0';
                    type_4   <= '0';
                    type_5   <= '1';

                else
                    dev_byte <= (others => '0');
                    type_1   <= '0';
                    type_2   <= '0';
                    type_3   <= '0';
                    type_4   <= '0';
                    type_5    <= '0';
                end if;
            end if;
        end if;
    end process;

    ------------------------fsm logic----------------------------------------------
    process(state, write, n_bit, n_byte, addr_byte, dev_byte, wr_bytes, return_state,
            tLOW0_counter, tLOW1_counter, tBIT_counter, tHTSS_counter,
            tRD_counter, tMRS_counter, dq_in,
            type_1, type_2, type_3, type_4)
        variable current_bit : std_logic;
    begin
        next_state <= state;
        dq_oe      <= '0';
        busy       <= '0';
        w_done     <= '0';

        case state is

            when IDLE =>
                if write = '1' then
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
                    current_bit := dev_byte(7-n_bit);
                    if current_bit = '1' then
                        next_state <= SEND_ONE_LOW;
                    else
                        next_state <= SEND_ZERO_LOW;
                    end if;
                else
                    next_state <= ACK_RELEASE0;
                end if;

            when ACK_RELEASE0 =>
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
                    next_state <= ADDR_BIT_SELECT;
                end if;

            when ADDR_BIT_SELECT =>
                dq_oe <= '0';
                busy  <= '1';
                if n_bit < 8 then
                    current_bit := addr_byte(7-n_bit);
                    if current_bit = '1' then
                        next_state <= SEND_ONE_LOW;
                    else
                        next_state <= SEND_ZERO_LOW;
                    end if;
                else
                    next_state <= ACK_RELEASE1;
                end if;

            when ACK_RELEASE1 =>
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter < (tMRS-tRD) and dq_in = '0' then
                    next_state <= ACK_WAIT1;
                elsif tMRS_counter = 0 and dq_in = '1' then
                    next_state <= IDLE;
                end if;

            when ACK_WAIT1 =>
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    next_state <= DATA_BIT_SELECT;
                end if;

            when DATA_BIT_SELECT =>
                dq_oe <= '0';
                busy  <= '1';
                if n_bit < 8 then
                    current_bit := wr_bytes(n_byte)(7-n_bit);
                    -- NOTE: for true multi-byte writes with different data per byte,
                    -- expand wr_bytes into an array indexed by n_byte here
                    if current_bit = '1' then
                        next_state <= SEND_ONE_LOW;
                    else
                        next_state <= SEND_ZERO_LOW;
                    end if;
                else
                    next_state <= ACK_RELEASE2;
                end if;

            when ACK_RELEASE2 =>
                dq_oe <= '1';
                busy  <= '1';
                if tRD_counter = 0 then
                    dq_oe <= '0';
                end if;
                if tMRS_counter < (tMRS-tRD) and dq_in = '0' then
                    next_state <= ACK_WAIT2;
                elsif tMRS_counter = 0 and dq_in = '1' then
                    next_state <= IDLE;
                end if;

            when ACK_WAIT2 =>
                -- after each data byte ACK, decide whether to send another byte or terminate
                -- n_byte has already been incremented (in the counter process) when the byte completed
                -- so n_byte=1 means 1 byte has been sent, n_byte=2 means 2 bytes, etc.
                dq_oe <= '0';
                busy  <= '1';
                if tBIT_counter = 0 then
                    if type_1 = '1' then        -- 1 byte total: EEPROM
                        next_state <= NACK;
                    elsif type_2 = '1' then     -- 1 bytes total: EEPROM
                        if n_byte < 8 then
                            next_state <= DATA_BIT_SELECT;
                        else
                            next_state <= NACK;
                        end if;
                    elsif type_3 = '1' then     -- 1 byte total : Security Reg
                            next_state <= NACK;
                        
                    elsif type_4 = '1' then     -- 8 bytes total : Security Reg
                    
                        if n_byte < 8 then
                            next_state <= DATA_BIT_SELECT;
                        else
                            next_state <= NACK;
                        end if;

                    elsif type_5 = '1' then
                        next_state <= NACK;
                    end if;

                end if;

            when NACK =>
                -- host releases the line (dq_oe='0') for tLOW1 to signal end of transaction
                dq_oe <= '0';
                busy  <= '1';
                if tLOW1_counter = 0 then
                    next_state <= STOP;
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

            when STOP =>
                dq_oe  <= '0';
                busy   <= '1';
                w_done <= '1';
                if tHTSS_counter = 0 then
                    next_state <= IDLE;
                end if;

        end case;
    end process;

end architecture;