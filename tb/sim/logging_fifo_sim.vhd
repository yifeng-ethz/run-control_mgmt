library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity logging_fifo is
    port (
        data    : in  std_logic_vector(127 downto 0);
        rdclk   : in  std_logic;
        rdreq   : in  std_logic;
        wrclk   : in  std_logic;
        wrreq   : in  std_logic;
        q       : out std_logic_vector(31 downto 0);
        rdempty : out std_logic;
        rdfull  : out std_logic;
        rdusedw : out std_logic_vector(9 downto 0);
        wrempty : out std_logic;
        wrfull  : out std_logic;
        wrusedw : out std_logic_vector(7 downto 0)
    );
end entity logging_fifo;

architecture sim of logging_fifo is
    constant DEPTH_WORDS_CONST : natural := 1024;

    type word_mem_t is array (0 to DEPTH_WORDS_CONST - 1) of std_logic_vector(31 downto 0);
    signal mem        : word_mem_t := (others => (others => '0'));
    signal rd_ptr     : natural range 0 to DEPTH_WORDS_CONST - 1 := 0;
    signal wr_ptr     : natural range 0 to DEPTH_WORDS_CONST - 1 := 0;
    signal used_words : natural range 0 to DEPTH_WORDS_CONST := 0;

    function bump_ptr(current_ptr : natural; delta : natural) return natural is
    begin
        return (current_ptr + delta) mod DEPTH_WORDS_CONST;
    end function;
begin
    q <= mem(rd_ptr) when used_words > 0 else (others => '0');

    rdempty <= '1' when used_words = 0 else '0';
    wrempty <= '1' when used_words = 0 else '0';
    rdfull  <= '1' when used_words = DEPTH_WORDS_CONST else '0';
    wrfull  <= '1' when used_words >= DEPTH_WORDS_CONST - 4 else '0';
    rdusedw <= std_logic_vector(to_unsigned(used_words, rdusedw'length));
    wrusedw <= std_logic_vector(to_unsigned(used_words / 4, wrusedw'length));

    proc_sync_fifo : process (wrclk)
        variable next_used_words_v : natural range 0 to DEPTH_WORDS_CONST;
        variable do_write_v        : boolean;
        variable do_read_v         : boolean;
    begin
        if rising_edge(wrclk) then
            next_used_words_v := used_words;
            do_write_v := (wrreq = '1') and (used_words <= DEPTH_WORDS_CONST - 4);
            do_read_v  := (rdreq = '1') and (used_words > 0);

            if do_write_v then
                mem(wr_ptr)                 <= data(31 downto 0);
                mem(bump_ptr(wr_ptr, 1))    <= data(63 downto 32);
                mem(bump_ptr(wr_ptr, 2))    <= data(95 downto 64);
                mem(bump_ptr(wr_ptr, 3))    <= data(127 downto 96);
                wr_ptr                      <= bump_ptr(wr_ptr, 4);
                next_used_words_v           := next_used_words_v + 4;
            end if;

            if do_read_v then
                rd_ptr            <= bump_ptr(rd_ptr, 1);
                next_used_words_v := next_used_words_v - 1;
            end if;

            used_words <= next_used_words_v;
        end if;
    end process;
end architecture sim;
