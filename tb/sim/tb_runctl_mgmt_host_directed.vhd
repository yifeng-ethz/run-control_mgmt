library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_runctl_mgmt_host_directed is
end entity tb_runctl_mgmt_host_directed;

architecture sim of tb_runctl_mgmt_host_directed is
    constant CLK_PERIOD_CONST : time := 8 ns;

    constant IDLE_DATA_CONST : std_logic_vector(7 downto 0) := x"BC";
    constant CMD_RUN_PREPARE_CONST : std_logic_vector(7 downto 0) := x"10";
    constant CMD_RUN_SYNC_CONST    : std_logic_vector(7 downto 0) := x"11";
    constant CMD_START_RUN_CONST   : std_logic_vector(7 downto 0) := x"12";
    constant CMD_END_RUN_CONST     : std_logic_vector(7 downto 0) := x"13";
    constant CMD_RESET_CONST       : std_logic_vector(7 downto 0) := x"30";
    constant CMD_STOP_RESET_CONST  : std_logic_vector(7 downto 0) := x"31";

    constant RC_IDLE_CONST        : std_logic_vector(8 downto 0) := "000000001";
    constant RC_RUN_PREPARE_CONST : std_logic_vector(8 downto 0) := "000000010";
    constant RC_RUN_SYNC_CONST    : std_logic_vector(8 downto 0) := "000000100";
    constant RC_START_RUN_CONST   : std_logic_vector(8 downto 0) := "000001000";
    constant RC_END_RUN_CONST     : std_logic_vector(8 downto 0) := "000010000";
    constant RC_RESET_CONST       : std_logic_vector(8 downto 0) := "010000000";

    signal clk125 : std_logic := '0';
    signal reset  : std_logic := '1';

    signal synclink_data  : std_logic_vector(8 downto 0) := '1' & IDLE_DATA_CONST;
    signal synclink_error : std_logic_vector(2 downto 0) := (others => '0');

    signal upload_data          : std_logic_vector(35 downto 0);
    signal upload_valid         : std_logic;
    signal upload_ready         : std_logic := '1';
    signal upload_startofpacket : std_logic;
    signal upload_endofpacket   : std_logic;

    signal runctl_valid : std_logic;
    signal runctl_data  : std_logic_vector(8 downto 0);
    signal runctl_ready : std_logic := '1';

    signal log_read        : std_logic := '0';
    signal log_readdata    : std_logic_vector(31 downto 0);
    signal log_write       : std_logic := '0';
    signal log_writedata   : std_logic_vector(31 downto 0) := (others => '0');
    signal log_waitrequest : std_logic;

    signal dp_hard_reset : std_logic;
    signal ct_hard_reset : std_logic;

begin
    clk125 <= not clk125 after CLK_PERIOD_CONST / 2;

    dut : entity work.runctl_mgmt_host
        port map (
            asi_synclink_data        => synclink_data,
            asi_synclink_error       => synclink_error,
            aso_upload_data          => upload_data,
            aso_upload_valid         => upload_valid,
            aso_upload_ready         => upload_ready,
            aso_upload_startofpacket => upload_startofpacket,
            aso_upload_endofpacket   => upload_endofpacket,
            aso_runctl_valid         => runctl_valid,
            aso_runctl_data          => runctl_data,
            aso_runctl_ready         => runctl_ready,
            avs_log_read             => log_read,
            avs_log_readdata         => log_readdata,
            avs_log_write            => log_write,
            avs_log_writedata        => log_writedata,
            avs_log_waitrequest      => log_waitrequest,
            mm_clk                   => clk125,
            mm_reset                 => reset,
            dp_hard_reset            => dp_hard_reset,
            ct_hard_reset            => ct_hard_reset,
            lvdspll_clk              => clk125,
            lvdspll_reset            => reset
        );

    proc_stimulus : process
        variable word0_v  : std_logic_vector(31 downto 0);
        variable word1_v  : std_logic_vector(31 downto 0);
        variable word2_v  : std_logic_vector(31 downto 0);
        variable word3_v  : std_logic_vector(31 downto 0);
        variable recv_ts_v : unsigned(47 downto 0) := (others => '0');
        variable exec_ts_v : unsigned(31 downto 0);
        variable prev_recv_ts_v : unsigned(47 downto 0) := (others => '0');

        procedure send_word(
            constant data_byte : in std_logic_vector(7 downto 0);
            constant is_k      : in std_logic := '0') is
        begin
            synclink_data <= is_k & data_byte;
            wait until rising_edge(clk125);
        end procedure;

        procedure send_idle(constant cycles : in natural := 1) is
        begin
            for i in 1 to cycles loop
                send_word(IDLE_DATA_CONST, '1');
            end loop;
        end procedure;

        procedure send_command(
            constant cmd_byte    : in std_logic_vector(7 downto 0);
            constant payload_len : in natural := 0;
            constant payload0    : in std_logic_vector(7 downto 0) := (others => '0');
            constant payload1    : in std_logic_vector(7 downto 0) := (others => '0');
            constant payload2    : in std_logic_vector(7 downto 0) := (others => '0');
            constant payload3    : in std_logic_vector(7 downto 0) := (others => '0')) is
        begin
            send_word(cmd_byte);
            case payload_len is
                when 0 =>
                    null;
                when 1 =>
                    send_word(payload0);
                when 2 =>
                    send_word(payload0);
                    send_word(payload1);
                when 3 =>
                    send_word(payload0);
                    send_word(payload1);
                    send_word(payload2);
                when 4 =>
                    send_word(payload0);
                    send_word(payload1);
                    send_word(payload2);
                    send_word(payload3);
                when others =>
                    assert false report "unsupported payload_len in send_command" severity failure;
            end case;
            send_idle(1);
        end procedure;

        procedure wait_for_runctl_hold(
            constant expected_data : in std_logic_vector(8 downto 0);
            constant hold_cycles   : in natural) is
        begin
            for i in 0 to 63 loop
                wait until rising_edge(clk125);
                if runctl_valid = '1' then
                    assert runctl_data = expected_data
                        report "runctl data mismatch while waiting for hold"
                        severity failure;
                    for j in 1 to hold_cycles loop
                        wait until rising_edge(clk125);
                        assert runctl_valid = '1'
                            report "runctl_valid dropped during backpressure hold"
                            severity failure;
                        assert runctl_data = expected_data
                            report "runctl_data changed during backpressure hold"
                            severity failure;
                    end loop;
                    return;
                end if;
            end loop;

            assert false
                report "timed out waiting for runctl_valid assertion"
                severity failure;
        end procedure;

        procedure wait_for_runctl_handshake(
            constant expected_data : in std_logic_vector(8 downto 0)) is
        begin
            for i in 0 to 63 loop
                wait until rising_edge(clk125);
                if runctl_valid = '1' and runctl_ready = '1' then
                    assert runctl_data = expected_data
                        report "runctl handshake carried unexpected data"
                        severity failure;
                    return;
                end if;
            end loop;

            assert false
                report "timed out waiting for runctl handshake"
                severity failure;
        end procedure;

        procedure wait_for_upload(
            constant expected_symbol    : in std_logic_vector(7 downto 0);
            constant expected_payload24 : in std_logic_vector(23 downto 0)) is
        begin
            for i in 0 to 63 loop
                wait until rising_edge(clk125);
                if upload_valid = '1' then
                    assert upload_data(35 downto 32) = "0001"
                        report "upload packet channel nibble mismatch"
                        severity failure;
                    assert upload_data(7 downto 0) = expected_symbol
                        report "upload packet symbol mismatch"
                        severity failure;
                    assert upload_data(31 downto 8) = expected_payload24
                        report "upload packet payload mismatch"
                        severity failure;
                    assert upload_startofpacket = '1' and upload_endofpacket = '1'
                        report "upload packet SOP/EOP mismatch"
                        severity failure;
                    return;
                end if;
            end loop;

            assert false
                report "timed out waiting for upload packet"
                severity failure;
        end procedure;

        procedure expect_no_upload(constant cycles : in natural) is
        begin
            for i in 1 to cycles loop
                wait until rising_edge(clk125);
                assert upload_valid = '0'
                    report "unexpected upload packet observed"
                    severity failure;
            end loop;
        end procedure;

        procedure log_flush is
        begin
            log_writedata <= (others => '0');
            log_write <= '1';
            loop
                wait until rising_edge(clk125);
                wait for 1 ps;
                exit when log_waitrequest = '0';
            end loop;
            log_write <= '0';
            wait until rising_edge(clk125);
        end procedure;

        procedure log_read_word(variable data_word : out std_logic_vector(31 downto 0)) is
        begin
            log_read <= '1';
            loop
                wait until rising_edge(clk125);
                wait for 1 ps;
                exit when log_waitrequest = '0';
            end loop;
            wait for 1 ps;
            data_word := log_readdata;
            log_read <= '0';
            wait until rising_edge(clk125);
        end procedure;

        procedure log_read_tuple(
            variable w0 : out std_logic_vector(31 downto 0);
            variable w1 : out std_logic_vector(31 downto 0);
            variable w2 : out std_logic_vector(31 downto 0);
            variable w3 : out std_logic_vector(31 downto 0)) is
        begin
            log_read_word(w0);
            log_read_word(w1);
            log_read_word(w2);
            log_read_word(w3);
        end procedure;

        procedure report_tuple(
            constant label_name : in string;
            constant w0 : in std_logic_vector(31 downto 0);
            constant w1 : in std_logic_vector(31 downto 0);
            constant w2 : in std_logic_vector(31 downto 0);
            constant w3 : in std_logic_vector(31 downto 0)) is
        begin
            report label_name & " tuple w0=" & to_hstring(w0) &
                   " w1=" & to_hstring(w1) &
                   " w2=" & to_hstring(w2) &
                   " w3=" & to_hstring(w3)
                severity note;
        end procedure;

        procedure wait_for_logged_tuple(
            constant label_name : in string;
            variable w0 : out std_logic_vector(31 downto 0);
            variable w1 : out std_logic_vector(31 downto 0);
            variable w2 : out std_logic_vector(31 downto 0);
            variable w3 : out std_logic_vector(31 downto 0)) is
        begin
            for attempt in 0 to 31 loop
                log_read_tuple(w0, w1, w2, w3);
                report_tuple(label_name & "_attempt" & integer'image(attempt), w0, w1, w2, w3);
                if w0 /= x"00000000" or w1 /= x"00000000" or
                   w2 /= x"00000000" or w3 /= x"00000000" then
                    return;
                end if;
                send_idle(2);
            end loop;

            assert false
                report label_name & " log tuple remained empty"
                severity failure;
        end procedure;

        procedure assert_zero_tuple(
            constant w0 : in std_logic_vector(31 downto 0);
            constant w1 : in std_logic_vector(31 downto 0);
            constant w2 : in std_logic_vector(31 downto 0);
            constant w3 : in std_logic_vector(31 downto 0)) is
        begin
            assert w0 = x"00000000" and w1 = x"00000000" and
                   w2 = x"00000000" and w3 = x"00000000"
                report "expected an empty log tuple"
                severity failure;
        end procedure;
    begin
        synclink_data  <= '1' & IDLE_DATA_CONST;
        synclink_error <= (others => '0');
        upload_ready   <= '1';
        runctl_ready   <= '1';
        log_read       <= '0';
        log_write      <= '0';
        log_writedata  <= (others => '0');
        reset          <= '1';

        wait for 64 ns;
        wait until rising_edge(clk125);
        reset <= '0';
        send_idle(8);

        log_flush;
        log_read_tuple(word0_v, word1_v, word2_v, word3_v);
        report_tuple("flush", word0_v, word1_v, word2_v, word3_v);
        assert_zero_tuple(word0_v, word1_v, word2_v, word3_v);

        runctl_ready <= '0';
        send_command(CMD_RUN_SYNC_CONST);
        wait_for_runctl_hold(RC_RUN_SYNC_CONST, 2);
        runctl_ready <= '1';
        wait_for_runctl_handshake(RC_RUN_SYNC_CONST);
        expect_no_upload(8);
        wait_for_logged_tuple("run_sync", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_RUN_SYNC_CONST
            report "log command byte mismatch for RUN_SYNC"
            severity failure;
        assert word1_v = x"00000000"
            report "RUN_SYNC payload log word should be zero"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        exec_ts_v := unsigned(word0_v);
        assert recv_ts_v > prev_recv_ts_v
            report "RUN_SYNC receive timestamp did not advance"
            severity failure;
        assert exec_ts_v /= 0
            report "RUN_SYNC execution timestamp should be non-zero"
            severity failure;
        prev_recv_ts_v := recv_ts_v;

        send_command(CMD_RUN_PREPARE_CONST, 4, x"11", x"22", x"33", x"44");
        wait_for_runctl_handshake(RC_RUN_PREPARE_CONST);
        wait_for_upload(x"FE", x"223344");
        send_idle(4);
        wait_for_logged_tuple("run_prepare", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_RUN_PREPARE_CONST
            report "log command byte mismatch for RUN_PREPARE"
            severity failure;
        assert word1_v = x"11223344"
            report "RUN_PREPARE payload log word mismatch"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        assert recv_ts_v > prev_recv_ts_v
            report "RUN_PREPARE receive timestamp did not advance"
            severity failure;
        prev_recv_ts_v := recv_ts_v;

        send_command(CMD_RESET_CONST, 2, x"00", x"03");
        wait_for_runctl_handshake(RC_RESET_CONST);
        for i in 0 to 15 loop
            wait until rising_edge(clk125);
            exit when dp_hard_reset = '1' and ct_hard_reset = '1';
        end loop;
        assert dp_hard_reset = '1' and ct_hard_reset = '1'
            report "RESET command did not assert hard resets"
            severity failure;
        wait_for_logged_tuple("reset", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_RESET_CONST
            report "log command byte mismatch for RESET"
            severity failure;
        assert word1_v = x"00000003"
            report "RESET payload log word mismatch"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        assert recv_ts_v > prev_recv_ts_v
            report "RESET receive timestamp did not advance"
            severity failure;
        prev_recv_ts_v := recv_ts_v;

        send_command(CMD_STOP_RESET_CONST, 2, x"00", x"03");
        wait_for_runctl_handshake(RC_IDLE_CONST);
        for i in 0 to 15 loop
            wait until rising_edge(clk125);
            exit when dp_hard_reset = '0' and ct_hard_reset = '0';
        end loop;
        assert dp_hard_reset = '0' and ct_hard_reset = '0'
            report "STOP_RESET command did not deassert hard resets"
            severity failure;
        wait_for_logged_tuple("stop_reset", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_STOP_RESET_CONST
            report "log command byte mismatch for STOP_RESET"
            severity failure;
        assert word1_v = x"00000003"
            report "STOP_RESET payload log word mismatch"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        assert recv_ts_v > prev_recv_ts_v
            report "STOP_RESET receive timestamp did not advance"
            severity failure;
        prev_recv_ts_v := recv_ts_v;

        send_command(CMD_START_RUN_CONST);
        wait_for_runctl_handshake(RC_START_RUN_CONST);
        expect_no_upload(8);
        wait_for_logged_tuple("start_run", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_START_RUN_CONST
            report "log command byte mismatch for START_RUN"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        assert recv_ts_v > prev_recv_ts_v
            report "START_RUN receive timestamp did not advance"
            severity failure;
        prev_recv_ts_v := recv_ts_v;

        send_command(CMD_END_RUN_CONST);
        wait_for_runctl_handshake(RC_END_RUN_CONST);
        wait_for_upload(x"FD", x"000000");
        send_idle(4);
        wait_for_logged_tuple("end_run", word0_v, word1_v, word2_v, word3_v);
        assert word2_v(7 downto 0) = CMD_END_RUN_CONST
            report "log command byte mismatch for END_RUN"
            severity failure;
        assert word1_v = x"00000000"
            report "END_RUN payload log word should be zero"
            severity failure;
        recv_ts_v := unsigned(word3_v & word2_v(31 downto 16));
        assert recv_ts_v > prev_recv_ts_v
            report "END_RUN receive timestamp did not advance"
            severity failure;

        log_flush;
        log_read_tuple(word0_v, word1_v, word2_v, word3_v);
        report_tuple("post_flush", word0_v, word1_v, word2_v, word3_v);
        assert_zero_tuple(word0_v, word1_v, word2_v, word3_v);

        report "RUNCTL_MGMT_HOST_DIRECTED_PASS" severity note;
        stop;
        wait;
    end process;
end architecture sim;
