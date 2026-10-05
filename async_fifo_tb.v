`timescale 1ns/1ps
module async_fifo_tb;

    reg        wr_clk = 0, rd_clk = 0;
    reg        wr_rst, rd_rst;
    reg        wr_en,  rd_en;
    reg  [7:0] wr_data;
    wire [7:0] rd_data;
    wire       full, empty;

    async_fifo dut (
        .wr_clk(wr_clk), .wr_rst(wr_rst), .wr_en(wr_en), .wr_data(wr_data),
        .rd_clk(rd_clk), .rd_rst(rd_rst), .rd_en(rd_en), .rd_data(rd_data),
        .full(full), .empty(empty)
    );

    // Two unrelated clocks: 100 MHz write, ~71 MHz read
    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    // ---------------- Scoreboard ----------------
    reg [7:0] exp_mem [0:16383];     // every accepted write, in order
    integer   wr_cnt = 0;            // accepted writes
    integer   rd_cnt = 0;            // accepted reads
    integer   errors = 0;
    reg [7:0] exp_data;
    reg       chk = 0;

    // A write is accepted only when wr_en is high and the FIFO is not full
    always @(posedge wr_clk)
        if (!wr_rst && wr_en && !full) begin
            exp_mem[wr_cnt] = wr_data;
            wr_cnt = wr_cnt + 1;
        end

    // A read is accepted only when rd_en is high and the FIFO is not empty
    always @(posedge rd_clk) begin
        chk = 0;
        if (!rd_rst && rd_en && !empty) begin
            if (rd_cnt >= wr_cnt) begin
                errors = errors + 1;
                $display("ERROR @%0t: read accepted but nothing was written", $time);
            end
            else begin
                exp_data = exp_mem[rd_cnt];
                chk = 1;
            end
            rd_cnt = rd_cnt + 1;
        end
    end

    // rd_data is registered, so check it half a clock after the read edge
    always @(negedge rd_clk)
        if (chk && rd_data !== exp_data) begin
            errors = errors + 1;
            $display("ERROR @%0t: read #%0d expected %h got %h",
                     $time, rd_cnt-1, exp_data, rd_data);
        end

    // ---------------- Helpers ----------------
    task check(input cond, input [8*40-1:0] msg);
    begin
        if (cond) $display("PASS: %0s", msg);
        else begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    end
    endtask

    // Hold wr_en high for n write-clock cycles (back-to-back writes)
    task wr_cycles(input integer n);
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(negedge wr_clk);
            wr_en   = 1;
            wr_data = $random;
        end
        @(negedge wr_clk);
        wr_en = 0;
    end
    endtask

    // Hold rd_en high for n read-clock cycles (back-to-back reads)
    task rd_cycles(input integer n);
        integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(negedge rd_clk) rd_en = 1;
        @(negedge rd_clk);
        rd_en = 0;
    end
    endtask

    // Random reads and writes at the same time for 'duration' ns
    reg stop;
    task random_phase(input integer wr_pct, input integer rd_pct, input integer duration);
    begin
        stop = 0;
        fork
            begin
                while (!stop) begin
                    @(negedge wr_clk);
                    wr_en   = ({$random} % 100) < wr_pct;
                    wr_data = $random;
                end
                wr_en = 0;
            end
            begin
                while (!stop) begin
                    @(negedge rd_clk);
                    rd_en = ({$random} % 100) < rd_pct;
                end
                rd_en = 0;
            end
            begin
                #(duration);
                stop = 1;
            end
        join
    end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        wr_rst = 1; rd_rst = 1;
        wr_en  = 0; rd_en  = 0; wr_data = 0;
        #40;
        wr_rst = 0; rd_rst = 0;
        repeat (4) @(posedge rd_clk);

        $display("\n--- TEST 1: after reset ---");
        check(empty === 1, "empty after reset");
        check(full  === 0, "not full after reset");

        $display("\n--- TEST 2: fill with 8 back-to-back writes ---");
        wr_cycles(8);
        check(full === 1,   "full after 8 writes");
        check(wr_cnt == 8,  "8 writes accepted");

        $display("\n--- TEST 3: overflow attempt (3 writes while full) ---");
        wr_cycles(3);
        check(full === 1,   "still full");
        check(wr_cnt == 8,  "extra writes rejected");

        $display("\n--- TEST 4: drain with 8 back-to-back reads ---");
        repeat (4) @(posedge rd_clk);          // let write pointer cross to read side
        rd_cycles(8);
        check(rd_cnt == 8,  "8 reads accepted");
        check(empty === 1,  "empty after 8 reads");

        $display("\n--- TEST 5: underflow attempt (3 reads while empty) ---");
        rd_cycles(3);
        check(rd_cnt == 8,  "extra reads rejected");

        $display("\n--- TEST 6: random simultaneous read/write ---");
        random_phase(75, 25, 20000);           // write-heavy: FIFO tends to be full
        random_phase(25, 75, 20000);           // read-heavy:  FIFO tends to be empty
        random_phase(50, 50, 20000);           // balanced

        $display("\n--- TEST 7: drain everything ---");
        repeat (6) @(posedge rd_clk);
        @(negedge rd_clk) rd_en = 1;
        while (rd_cnt < wr_cnt) @(negedge rd_clk);
        rd_en = 0;
        repeat (6) @(posedge wr_clk);
        check(empty === 1,  "empty at end");
        check(full  === 0,  "not full at end");
        check(rd_cnt == wr_cnt, "every written word was read");

        $display("\nTotal words written = %0d, read = %0d", wr_cnt, rd_cnt);
        if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
        else             $display("\n*** %0d ERROR(S) ***\n", errors);
        $finish;
    end

    // Safety net in case something hangs
    initial begin
        #1000000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("async_fifo.vcd");
        $dumpvars(0, async_fifo_tb);
    end

endmodule