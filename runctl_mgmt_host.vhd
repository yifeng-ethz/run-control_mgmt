-- File name: runctl_mgmt_host.vhd 
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision: 1.0 (file created)
--		Date: Nov 18, 2024
-- =========
-- Description:	[Run-Control Management Host] 
--      Receive the run control command on <synclink>
--          ref: https://www.physi.uni-heidelberg.de/Forschung/he/mu3e/restricted/notes/Mu3e-Note-0046-RunStartAndResetProtocol.pdf

--      Ack the run control command through <upload>
--          ref: https://www.physi.uni-heidelberg.de/Forschung/he/mu3e/restricted/specbook/Mu3eSpecBook.pdf (run control signals)

--      Monitor through <log> interface
--          User can read back the receive (received localled on <synclink>) and execution (ready asserted by all agents) timestamps of each run command.  
--          the <log> interface connects to a fifo, you have to read 4 words for a complete log sentense. 
--          Log data structure is:
--              Word 0: received timestamp [48:16]
--              Word 1: received timestamp [15:0] | empty [7:0] | run command [7:0]
--              Word 2: payload_if [31:0]
--              Word 3: execution timestamp [31:0]
--          note: the timestamps are free-running across runs and only reset by lvdspll_reset
--      
--      Issue decoded run control command to qsys modules (which has runctl mgmt agent) and listen for their ack (ready signals)
--          
--      Assert associate reset depending on the run control command 
--          reset mask is under dev ...
--
-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;
use ieee.std_logic_misc.and_reduce;
use ieee.std_logic_misc.or_reduce;

entity runctl_mgmt_host is
generic (
    -- symbols to be recognized by run control listener
    RUN_START_ACK_SYMBOL    : std_logic_vector(7 downto 0) := "11111110"; -- k30.7 (x"FE")
    RUN_END_ACK_SYMBOL      : std_logic_vector(7 downto 0) := "11111101"; -- k29.7 (x"FD")
    DEBUG                   : natural := 1
);
port (
    -- <synclink> st interface      ========>
    asi_synclink_data        : in  std_logic_vector(8 downto 0); -- {k[8] d[7:0]}
    asi_synclink_error       : in  std_logic_vector(2 downto 0); -- {loss_sync_pattern[2] parity_error[1] decode_error[0]}
    
    -- <upload> st interface        ========>
    aso_upload_data          : out std_logic_vector(35 downto 0);
    aso_upload_valid         : out std_logic;
    aso_upload_ready         : in  std_logic;
    aso_upload_startofpacket : out std_logic;
    aso_upload_endofpacket   : out std_logic;

    -- <runctl> st interface        <========
    aso_runctl_valid         : out std_logic;
    aso_runctl_data          : out std_logic_vector(8 downto 0);
    aso_runctl_ready         : in  std_logic;
    
    -- <log> mm interface           ========>
    avs_log_read             : in  std_logic;
    avs_log_readdata         : out std_logic_vector(31 downto 0);
    avs_log_write            : in  std_logic;
    avs_log_writedata        : in  std_logic_vector(31 downto 0);
    avs_log_waitrequest      : out std_logic;
    
    -- clock and reset interface
    mm_clk                  : in  std_logic; -- clock to the avalon memory mapped interface, arbitary frequency. can be same clock as lvdspll_clk
    mm_reset                : in  std_logic; -- reset the interface and flush the fifo 
    
    dp_hard_reset           : out std_logic; -- hard reset to datapath modules (except lvds_controller), controlled by run command (can be masked) (in lvdsoutclock domain)
    ct_hard_reset           : out std_logic; -- hard reset to control modules, controlled by run command (can be masked) (in control_156 domain) 

    lvdspll_clk             : in  std_logic; -- clock from lvds pll out, should be 125 MHz
    lvdspll_reset           : in  std_logic -- this reset should not be connected to dp_hard_reset to avoid deadlock. this reset should be connected to jtag master, arst of lvds pll and/or push-button.
);
end entity runctl_mgmt_host;

architecture rtl of runctl_mgmt_host is 

    ------------- Reset link protocol -------------- 
    --       <command>                       <code>     <comment>
    constant CMD_RUN_PREPARE    : integer := 16#10#; -- 32 bit run number       
    constant CMD_RUN_SYNC       : integer := 16#11#;   
    constant CMD_START_RUN      : integer := 16#12#;
    constant CMD_END_RUN        : integer := 16#13#;
    constant CMD_ABORT_RUN      : integer := 16#14#;
    ------------------------------------------------
    constant CMD_RESET          : integer := 16#30#; -- 16 bit mask
    constant CMD_STOP_RESET     : integer := 16#31#; -- 16 bit mask
    constant CMD_ENABLE         : integer := 16#32#;
    constant CMD_DISABLE        : integer := 16#33#;
    ------------------------------------------------
    constant CMD_ADDRESS        : integer := 16#40#; -- 16 bit address

  

    -- /////////////////////////////// helper functions ///////////////////////////////    
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @funcName        get_payload_length 
    --
    -- @berief          get the payload length given input run control commands 
    -- @input           <ilink> -- decoded reset link (8b+1k) from optical xcvr 
    -- @output          <ret> -- type: std_logic_vector(7 downto 0)
    --                        -- value: 
    --                           -> 0               : data not valid, idle
    --                           -> -1              : decode error, run command unknown
    --                           -> payload length  : success 
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    function get_payload_length (ilink : std_logic_vector(8 downto 0)) return std_logic_vector is 
        variable k                  : std_logic;
        variable data               : std_logic_vector(7 downto 0);
        variable run_command        : std_logic_vector(7 downto 0);
        variable payload_len        : integer;
        variable ret                : std_logic_vector(7 downto 0); -- payload length [byte]
            
    begin
        -- parse argv
        k       := ilink(8);
        data    := ilink(7 downto 0);
        run_command := data;
        
        -- derive "run prepare" flag
        if (k = '0') then 
        -- 1) valid  
            case to_integer(unsigned(run_command)) is 
                when CMD_RUN_PREPARE => 
                    payload_len     := 4;
                when CMD_RUN_SYNC =>
                    payload_len     := 0;
                when CMD_START_RUN =>
                    payload_len     := 0;
                when CMD_END_RUN =>
                    payload_len     := 0;
                when CMD_ABORT_RUN =>
                    payload_len     := 0;
                ------------------------------------------------
                when CMD_RESET =>
                    payload_len     := 2;
                when CMD_STOP_RESET =>
                    payload_len     := 2;
                when CMD_ENABLE =>
                    payload_len     := 0;
                when CMD_DISABLE => 
                    payload_len     := 0;
                ------------------------------------------------
                when CMD_ADDRESS => 
                    payload_len     := 2;
                when others => 
                    payload_len     := -1; -- decode error
            end case;
        else 
        -- 2) not valid
            payload_len     := 0;
        end if;
        
        -- type cast for return value
        ret     := std_logic_vector(to_unsigned(payload_len,ret'length));
        
        return ret;
    end function;
    
    
    -- @input:      run command
    -- @output:     runctl data signal value (sending to run mgmt agents)
    function dec_runcmd (run_cmd : std_logic_vector(7 downto 0)) return std_logic_vector is 
        variable ret         : std_logic_vector(8 downto 0);     
    begin
        case to_integer(unsigned(run_cmd)) is 
            when CMD_RUN_PREPARE => 
                ret     := "000000010";
            when CMD_RUN_SYNC =>
                ret     := "000000100";
            when CMD_START_RUN =>
                ret     := "000001000";
            when CMD_END_RUN =>
                ret     := "000010000";
            when CMD_ABORT_RUN =>
                ret     := "000000001";
            ------------------------------------------------
            when CMD_RESET =>
                ret     := "010000000"; -- -> RESET
            when CMD_STOP_RESET =>
                ret     := "000000001"; -- -> IDLE
            when CMD_ENABLE =>
                ret     := "000000001"; -- -> IDLE
            when CMD_DISABLE => 
                ret     := "100000000"; -- -> OUT_OF_DAQ
            ------------------------------------------------
            when others => -- for safety, this has minimal impact on our system
                ret     := "000000001"; -- -> IDLE
        end case;
        return ret;
    end function;
    
    constant LOGGING_FIFO_DATA_W            : natural := 128;
    constant LOGGING_FIFO_WRUSEDW_W         : natural := 8;
    constant LOGGING_FIFO_Q_W               : natural := 32;
    constant LOGGING_FIFO_RDUSEDW_W         : natural := 10;
    component logging_fifo
	port (
        -- --------------------------------------------------
        -- write side - data
        wrreq		: in  std_logic;
		data		: in  std_logic_vector(LOGGING_FIFO_DATA_W-1 downto 0);
        -- write side - control
        wrempty		: out std_logic;
		wrfull		: out std_logic;
		wrusedw		: out std_logic_vector(LOGGING_FIFO_WRUSEDW_W-1 downto 0);
        -- write side - clock 
        wrclk		: in  std_logic;
        -- --------------------------------------------------
        -- read side - data 
		rdreq		: in  std_logic;
        q		    : out std_logic_vector(LOGGING_FIFO_Q_W-1 downto 0);
		-- read side - control
		rdempty		: out std_logic;
		rdfull		: out std_logic;
		rdusedw		: out std_logic_vector(LOGGING_FIFO_RDUSEDW_W-1 downto 0);
        -- read side - clock
        rdclk		: in  std_logic
        -- --------------------------------------------------
	);
    end component;
    
    -- pipe(s)
    type pipe_r2h_t is record 
        start       : std_logic;
        done        : std_logic;
    end record;
    signal pipe_r2h         : pipe_r2h_t;
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ synclink_recv \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    type recv_state_t is (IDLE,RECV_PAYLOAD,LOGGING,LOG_ERROR,RESET);
    signal recv_state               : recv_state_t;
    
    type synclink_recv_run_number_t is array (0 to 3) of std_logic_vector(7 downto 0);
    type synclink_recv_reset_assert_mask_t is array (0 to 1) of std_logic_vector(7 downto 0);
    type synclink_recv_reset_release_mask_t is array (0 to 1) of std_logic_vector(7 downto 0);
    type synclink_recv_fpga_address_t is array (0 to 1) of std_logic_vector(7 downto 0);
    type synclink_recv_payload_t is array (0 to 3) of std_logic_vector(7 downto 0);
    
    type synclink_recv_t is record 
        run_command                 : std_logic_vector(7 downto 0);
        timestamp                   : std_logic_vector(47 downto 0);
        run_number                  : synclink_recv_run_number_t;
        reset_assert_mask           : synclink_recv_reset_assert_mask_t;
        reset_release_mask          : synclink_recv_reset_release_mask_t;
        fpga_address                : synclink_recv_fpga_address_t;
        payload                     : synclink_recv_payload_t;
        payload_len                 : std_logic_vector(7 downto 0);
        payload_cnt                 : unsigned(7 downto 0);
    end record;
    signal synclink_recv            : synclink_recv_t;
    
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ runctl_mgmt_host \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    type host_state_t is (IDLE,POSTING,RESET);
    signal host_state           : host_state_t;
    
    type runctl_mgmt_t is record 
        timestamp               : std_logic_vector(47 downto 0);
    end record;
    signal runctl_mgmt          : runctl_mgmt_t;
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ gts_counter \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    signal gts_counter              : unsigned(47 downto 0);
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ log_fifo \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    signal log_fifo_wrreq           : std_logic;
    signal log_fifo_data            : std_logic_vector(LOGGING_FIFO_DATA_W-1 downto 0);
    signal log_fifo_wrempty         : std_logic;
    signal log_fifo_wrfull          : std_logic;
    signal log_fifo_wrusedw         : std_logic_vector(LOGGING_FIFO_WRUSEDW_W-1 downto 0);
    signal log_fifo_rdreq           : std_logic;
    signal log_fifo_q               : std_logic_vector(LOGGING_FIFO_Q_W-1 downto 0);
    signal log_fifo_rdempty         : std_logic;
    signal log_fifo_rdfull          : std_logic;
    signal log_fifo_rdusedw         : std_logic_vector(LOGGING_FIFO_RDUSEDW_W-1 downto 0);
    
    type read_log_fifo_state_t is (FLUSH, IDLE, POP_LOG, RESET);
    signal read_log_fifo_state              : read_log_fifo_state_t;
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ rc_uploader \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    type rc_pkt_upload_state_t is (IDLE, UPLOAD,RESET);
    signal rc_pkt_upload_state          : rc_pkt_upload_state_t;
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

begin
    
    
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @blockName       synclink_recv
    --
    -- @berief          deassemble the run command from <synclink> and ask runctl host to do its job.
    --                  <synclink> -> <runctl> 
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    proc_synclink_recv : process (lvdspll_clk)
    begin 
        if rising_edge(lvdspll_clk) then 
            -- default
            log_fifo_wrreq          <= '0';
            log_fifo_data           <= (others => '0');
            case recv_state is 
                when IDLE => 
                    if (asi_synclink_error(2) = '0') then -- lvds is trained
                        if (asi_synclink_data(asi_synclink_data'high) = '0') then -- byte is data 
                            -- new command incoming...
                            -- latch command
                            synclink_recv.run_command       <= asi_synclink_data(7 downto 0);
                            -- register timestamp
                            synclink_recv.timestamp         <= std_logic_vector(gts_counter);
                            -- lut -> command length
                            if (to_integer(unsigned(get_payload_length(asi_synclink_data))) > 0) then 
                                -- 1) length > 0: receive payload
                                synclink_recv.payload_len            <= get_payload_length(asi_synclink_data);
                                recv_state               <= RECV_PAYLOAD;
                            else 
                                -- 2) length = 0: skip payload
                                recv_state        <= LOGGING;
                            end if;
                        end if;
                        -- exception: link symbol error
                        if (or_reduce(asi_synclink_error(1 downto 0)) = '1') then 
                            recv_state            <= LOG_ERROR;
                        end if;
                    end if;
                when RECV_PAYLOAD => 
                    if (asi_synclink_error(2) = '0') then -- lvds is trained
                        if (to_integer(synclink_recv.payload_cnt) >= to_integer(unsigned(synclink_recv.payload_len))) then 
                            -- exit: 
                            recv_state              <= LOGGING;
                        else
                            -- receiving... :
                            synclink_recv.payload_cnt        <= synclink_recv.payload_cnt + 1;
                            case to_integer(unsigned(synclink_recv.run_command)) is 
                                when CMD_RUN_PREPARE =>
                                    -- load first byte into byte 3 last byte into byte 0 (lsb last) (byte3-byte2-byte1-byte0)
                                    for i in 0 to synclink_recv.run_number'length-1 loop
                                        if (to_integer(unsigned(synclink_recv.payload_cnt)) = i) then 
                                            synclink_recv.payload(synclink_recv.run_number'length-1-i)                <= asi_synclink_data(7 downto 0);
                                            synclink_recv.run_number(synclink_recv.run_number'length-1-i)             <= asi_synclink_data(7 downto 0);
                                        end if;
                                    end loop;
                                    -- TODO: the reset mask are not implemented on the SWB yet. so currently, we are taking in 0xBC as payload
                                    --       regardless of the "k" flag bit to prevent infinite hanging. add protection to it in the future once the payload is implemented.
                                when CMD_RESET =>
                                    for i in 0 to synclink_recv.reset_assert_mask'length-1 loop
                                        if (to_integer(unsigned(synclink_recv.payload_cnt)) = i) then 
                                            synclink_recv.payload(synclink_recv.reset_assert_mask'length-1-i)                <= asi_synclink_data(7 downto 0);
                                            synclink_recv.reset_assert_mask(synclink_recv.reset_assert_mask'length-1-i)      <= asi_synclink_data(7 downto 0);
                                        end if;
                                    end loop;
                                when CMD_STOP_RESET =>
                                    for i in 0 to synclink_recv.reset_release_mask'length-1 loop
                                        if (to_integer(unsigned(synclink_recv.payload_cnt)) = i) then 
                                            synclink_recv.payload(synclink_recv.reset_release_mask'length-1-i)                <= asi_synclink_data(7 downto 0);
                                            synclink_recv.reset_release_mask(synclink_recv.reset_release_mask'length-1-i)     <= asi_synclink_data(7 downto 0);
                                        end if;
                                    end loop;
                                when CMD_ADDRESS =>
                                    for i in 0 to synclink_recv.fpga_address'length-1 loop
                                        if (to_integer(unsigned(synclink_recv.payload_cnt)) = i) then 
                                            synclink_recv.payload(synclink_recv.fpga_address'length-1-i)                <= asi_synclink_data(7 downto 0);
                                            synclink_recv.fpga_address(synclink_recv.fpga_address'length-1-i)           <= asi_synclink_data(7 downto 0);
                                        end if;
                                    end loop;
                                when others => 
                                    null;
                            end case;
                        end if;
                        -- exception: link symbol error
                        if (or_reduce(asi_synclink_error(1 downto 0)) = '1') then 
                            recv_state            <= LOG_ERROR;
                        end if;
                    else -- link is not trained (corrupted)
                        recv_state              <= LOG_ERROR;
                    end if;
                    
                when LOGGING =>
                    if (pipe_r2h.start = '0' and pipe_r2h.done = '0') then 
                        pipe_r2h.start          <= '1'; -- start host 
                    elsif (pipe_r2h.start = '1' and pipe_r2h.done = '0') then 
                        -- wait
                    elsif (pipe_r2h.start = '1' and pipe_r2h.done = '1') then -- host finish
                        pipe_r2h.start          <= '0'; -- ack host finish
                        -- write to log_fifo
                        log_fifo_wrreq          <= '1';
                        log_fifo_data(127 downto 80)    <= synclink_recv.timestamp; 
                        log_fifo_data(71 downto 64)     <= synclink_recv.run_command;
                        for i in 0 to 3 loop -- [63:32]
                            log_fifo_data(63-i*8 downto 64-(i+1)*8)     <= synclink_recv.payload(3-i);
                        end loop;
                        log_fifo_data(31 downto 0)      <= runctl_mgmt.timestamp(31 downto 0); -- only lower parts are registered as this ack will not take longer than a few cycles
                        recv_state                   <= RESET;
                        
                    end if;
                    -- mask the address command, which stop at recv and will not need agents ack
                    if (to_integer(unsigned(synclink_recv.run_command)) = CMD_ADDRESS) then -- terminate it
                        pipe_r2h.start          <= '0'; -- (mask) start host
                        recv_state              <= RESET;
                    end if;
                   
                when LOG_ERROR =>
                    -- ...
                    recv_state                      <= RESET;
                -- --------------
                -- reset (soft)
                -- --------------
                when RESET =>
                    -- 1) reset the pipe
                    pipe_r2h.start                  <= '0';
                    -- 2) reset the tmp signals
                    synclink_recv.run_command       <= (others => '0');
                    synclink_recv.timestamp         <= (others => '0');
                    synclink_recv.payload_len       <= (others => '0');
                    synclink_recv.payload_cnt       <= (others => '0');
                    synclink_recv.payload           <= (others => (others => '0'));
                    -- 3) reset state
                    recv_state                      <= IDLE;
                when others =>
                    null;
            end case;
            
            -- --------------
            -- reset (hard)
            -- --------------
            if (lvdspll_reset = '1' or asi_synclink_error(2) = '1') then 
                -- 1) reset state related signals
                recv_state                       <= RESET; 
                -- 2) reset register pack
                synclink_recv.run_number            <= (others => (others => '0'));
                synclink_recv.reset_assert_mask     <= (others => (others => '0'));
                synclink_recv.reset_release_mask    <= (others => (others => '0'));
                synclink_recv.fpga_address          <= (others => (others => '0'));
            end if;
            
        end if;
    end process;
    
    proc_runrst_mgmt_host : process (lvdspll_clk) 
    begin
        if (rising_edge(lvdspll_clk)) then 
            if (to_integer(unsigned(synclink_recv.run_command)) = CMD_RESET) then 
                dp_hard_reset       <= '1';
                ct_hard_reset       <= '1';
            end if;
            if (to_integer(unsigned(synclink_recv.run_command)) = CMD_STOP_RESET) then 
                dp_hard_reset       <= '0';
                ct_hard_reset       <= '0';
            end if;
            -- TODO: add mask ability of the reset 
        
        end if;
    
    end process;
    
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @procName          runctl_mgmt_host (abbr. host)
    --
    -- @berief            converts run command into runctl.data for communicating runctl mgmt agents 
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    proc_runctl_mgmt_host : process (lvdspll_clk)
    begin
        if (rising_edge(lvdspll_clk)) then 
            case host_state is 
                when IDLE => 
                    if (pipe_r2h.start = '1' and pipe_r2h.done = '0') then 
                        host_state          <= POSTING;
                    end if;
                when POSTING => 
                    -- 1) send run command to agents 
                    aso_runctl_valid            <= '1'; 
                    aso_runctl_data             <= dec_runcmd(synclink_recv.run_command);
                    -- 2) agents ack the run command 
                    if (aso_runctl_ready = '1' and aso_runctl_valid = '1') then 
                        pipe_r2h.done               <= '1'; -- pipe send to recv
                        -- register the timestamp at the completion
                        runctl_mgmt.timestamp       <= std_logic_vector(gts_counter); -- for the recv to log
                        aso_runctl_valid            <= '0';
                    end if;
                    if (pipe_r2h.done = '1') then -- mask valid during handshake with recv 
                        aso_runctl_valid            <= '0';
                    end if;
                    
                    if (pipe_r2h.done = '1' and pipe_r2h.start = '0') then -- recv ack its done signal 
                        host_state                  <= RESET;
                    end if;
                when RESET =>
                    host_state                  <= IDLE;
                    aso_runctl_valid            <= '0';
                    runctl_mgmt.timestamp        <= (others => '0');
                    if (pipe_r2h.start = '0') then -- handshake with recv     
                        pipe_r2h.done               <= '0'; -- deassert on slave side
                    end if;
                when others =>
                    null;
            end case;
            -- ------------
            -- reset 
            -- ------------
            if (lvdspll_reset = '1' or asi_synclink_error(2) = '1') then 
                host_state                  <= RESET;
                pipe_r2h.done               <= '0';
            end if;

        end if;
        

    end process;
    
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @procName            gts_counter
    --
    -- @berief              the timer that is running at datapath clock, known as mu3e global timestamp
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    proc_gts_counter : process (lvdspll_clk) 
    begin
        if (rising_edge(lvdspll_clk)) then 
            if (lvdspll_reset = '1' or asi_synclink_error(2) = '1') then 
                gts_counter         <= (others => '0');
            else 
                gts_counter         <= gts_counter + 1;
            end if;
        end if;
    end process;
    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @compName            <logging_fifo> log_fifo 
    --
    -- @berief              the fifo to log [info]. ring-shape. can be read out through memory-mapped interface.
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    log_fifo : logging_fifo 
    port map (
        -- --------------------------------------------------
        -- write side - data
        wrreq		=> log_fifo_wrreq,
		data		=> log_fifo_data,
        -- write side - control
        wrempty		=> log_fifo_wrempty,
		wrfull		=> log_fifo_wrfull,
		wrusedw		=> log_fifo_wrusedw,
        -- write side - clock 
        wrclk		=> lvdspll_clk,
        -- --------------------------------------------------
        -- read side - data 
		rdreq		=> log_fifo_rdreq,
        q		    => log_fifo_q,
		-- read side - control
		rdempty		=> log_fifo_rdempty,
		rdfull		=> log_fifo_rdfull,
		rdusedw		=> log_fifo_rdusedw,
        -- read side - clock
        rdclk		=> mm_clk
        -- --------------------------------------------------
	);

    
    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @procName            unload_log_fifo
    --
    -- @berief              connect log fifo with avalon <log> interface 
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- fifo read side <-> avalon log interface
    proc_unload_log_fifo : process (mm_clk)  
    begin
        if (rising_edge(mm_clk)) then 
            if (mm_reset = '1') then
                read_log_fifo_state         <= FLUSH;
            else 
                -- default 
                log_fifo_rdreq              <= '0';
                avs_log_waitrequest         <= '1';
                avs_log_readdata            <= (others => '0');
                case read_log_fifo_state is 
                    when FLUSH =>
                        if (log_fifo_rdempty = '1') then 
                            read_log_fifo_state         <= IDLE;
                        end if;
                        log_fifo_rdreq                  <= '1';
                    when IDLE =>
                        if (avs_log_read = '1') then 
                            read_log_fifo_state         <= POP_LOG;
                        end if;
                        if (avs_log_write = '1') then 
                            if (and_reduce(avs_log_writedata) = '0') then 
                                read_log_fifo_state         <= FLUSH;
                            end if;
                            avs_log_waitrequest         <= '0';
                        end if;
                    when POP_LOG =>
                        avs_log_waitrequest         <= '0';
                        avs_log_readdata            <= log_fifo_q;
                        log_fifo_rdreq              <= '1';
                        read_log_fifo_state         <= RESET;
                        if (log_fifo_rdempty = '1') then 
                            avs_log_readdata            <= (others => '0');
                        end if;
                        if (avs_log_read = '0') then
                            read_log_fifo_state         <= IDLE;
                        end if;
                    when RESET =>
                        avs_log_waitrequest         <= '0';
                        if (avs_log_read = '0') then
                            read_log_fifo_state         <= IDLE;
                        end if;
                    when others =>
                        null;
                end case;   
            end if;
        end if;
    
    end process;
    

    
    
    
        
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @procName            rc_pkt_upload
    --
    -- @berief              reply for the run prep and run end occurance. send rc packet for uploading
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- reply the rc packet by uploading a run control packet to upload_mux
    proc_rc_pkt_upload : process (lvdspll_clk)
    begin
        if (rising_edge(lvdspll_clk)) then 
            if (lvdspll_reset = '1' or asi_synclink_error(2) = '1') then 
                rc_pkt_upload_state         <= RESET;
            else 
                -- default 
                aso_upload_data             <= (others => '0');
                aso_upload_valid            <= '0';
                aso_upload_startofpacket    <= '0';
                aso_upload_endofpacket      <= '0';
                -- main logic
                case rc_pkt_upload_state is 
                    when IDLE => 
                        if (pipe_r2h.done = '1') then -- identifier for transaction done, ack by agents
                            if (to_integer(unsigned(synclink_recv.run_command)) = CMD_RUN_PREPARE) then 
                                rc_pkt_upload_state         <= UPLOAD;
                            end if;
                            if (to_integer(unsigned(synclink_recv.run_command)) = CMD_END_RUN) then 
                                rc_pkt_upload_state         <= UPLOAD;
                            end if;
                        end if;
                    when UPLOAD =>
                        aso_upload_data(35 downto 32)   <= "0001";
                        -- byte 0 : identifer
                        if (to_integer(unsigned(synclink_recv.run_command)) = CMD_RUN_PREPARE) then 
                            -- k30.7 (run prep ack)
                            aso_upload_data(7 downto 0)     <= x"FE"; 
                            -- byte [3:1] : run number (4 bytes -> trim lower 3 bytes) 
                            aso_upload_data(31 downto 8)    <= synclink_recv.run_number(2) & synclink_recv.run_number(1) & synclink_recv.run_number(0);
                        end if;
                        if (to_integer(unsigned(synclink_recv.run_command)) = CMD_END_RUN) then 
                            -- k29.7 (run end ack)
                            aso_upload_data(7 downto 0)     <= x"FD"; 
                        end if;
                        aso_upload_valid                <= '1';
                        aso_upload_startofpacket        <= '1';
                        aso_upload_endofpacket          <= '1';
                        -- block until: packet accepted by the upload mux
                        if (aso_upload_valid = '1' and aso_upload_ready = '1') then 
                            rc_pkt_upload_state             <= RESET;
                            aso_upload_valid                <= '0';
                        end if;
                    when RESET => 
                        if (pipe_r2h.done = '0') then  -- transaction is done in between recv and host
                            rc_pkt_upload_state             <= IDLE;
                        end if;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    
    
    
    end process;


end architecture rtl;











