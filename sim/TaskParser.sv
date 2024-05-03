module TaskParser
#(
    parameter FLIT_SIZE = 32,
    parameter string START_FILE = "app_start.txt"
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    output logic                     eoa_o,
    output logic                     tx_o,
    input  logic                     credit_i,
    output logic [(FLIT_SIZE - 1):0] data_o
);

    int app_start_fd;

    initial begin
        app_start_fd = $fopen(START_FILE, "r");
        if (app_start_fd == '0) begin
            $display("[TaskParser] Could not open %s.txt", START_FILE);
            $finish();
        end
    end

    int unsigned     app_task_cnt;
    int unsigned     map_ttt_size;
    int unsigned     descr_size;
    int unsigned     binary_size;

////////////////////////////////////////////////////////////////////////////////

    typedef enum {  
        LOAD_NEXT_APP,
        LOAD_CHECK_EOF,
        LOAD_APP,
        WAIT_START_TIME,
        INJECT_DESCR_SIZE,
        INJECT_TASK_CNT,
        INJECT_MAP,
        INJECT_TTT,
        INJECT_GRAPH,
        LOAD_TASK,
        INJECT_TEXT,
        INJECT_DATA,
        INJECT_BSS,
        INJECT_ENTRY,
        INJECT_BINARY,
        LOAD_FINISH,
        LOAD_NEXT_TASK,
        LOAD_EOA
    } fsm_t;

    fsm_t state;
    fsm_t next_state;

    logic can_start;

    always_comb begin
        case (state)
            LOAD_NEXT_APP:
                next_state = LOAD_CHECK_EOF;
            LOAD_CHECK_EOF:
                next_state = $feof(app_start_fd) ? LOAD_EOA : LOAD_APP;
            LOAD_APP:
                next_state = WAIT_START_TIME;
            WAIT_START_TIME:
                next_state = can_start ? INJECT_DESCR_SIZE : WAIT_START_TIME;
            INJECT_DESCR_SIZE:
                next_state = credit_i  ? INJECT_TASK_CNT   : INJECT_DESCR_SIZE;
            INJECT_TASK_CNT:
                next_state = credit_i  ? INJECT_MAP        : INJECT_TASK_CNT;
            INJECT_MAP:
                next_state = credit_i  ? INJECT_TTT        : INJECT_MAP;
            INJECT_TTT:
                next_state = !credit_i
                    ? INJECT_TTT
                    : map_ttt_size == '0 
                        ? INJECT_GRAPH
                        : INJECT_MAP;
            INJECT_GRAPH:
                next_state = (credit_i && descr_size == '0)
                    ? LOAD_TASK
                    : INJECT_GRAPH;
            LOAD_TASK:
                next_state = INJECT_TEXT;
            INJECT_TEXT:
                next_state = credit_i ? INJECT_DATA   : INJECT_TEXT;
            INJECT_DATA:
                next_state = credit_i ? INJECT_BSS    : INJECT_DATA;
            INJECT_BSS:
                next_state = credit_i ? INJECT_ENTRY  : INJECT_BSS;
            INJECT_ENTRY:
                next_state = credit_i ? INJECT_BINARY : INJECT_ENTRY;
            INJECT_BINARY:
                next_state = (credit_i && binary_size == '0)
                    ? LOAD_FINISH
                    : INJECT_BINARY;
            LOAD_FINISH:
                next_state = LOAD_NEXT_TASK;
            LOAD_NEXT_TASK:
                next_state = (app_task_cnt == '0) ? LOAD_NEXT_APP : LOAD_TASK;
            LOAD_EOA:
                next_state = LOAD_EOA;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            state <= LOAD_NEXT_APP;
        else
            state <= next_state;
    end

////////////////////////////////////////////////////////////////////////////////

    string           app_name;
    longint unsigned start_time;
    int              app_descr_fd;
    int              mapping;
    int              graph;
    string           task_name;
    int              task_descr_fd;
    int unsigned     text_size;
    int unsigned     data_size;
    int unsigned     bss_size;
    int unsigned     entry_point;
    logic [31:0]     binary;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            /* verilator lint_off BLKSEQ */
            app_name      = "";
            start_time    = '0;
            descr_size    = '0;
            app_task_cnt  = '0;
            app_descr_fd  = '0;
            mapping       = '0;
            graph         = '0;
            task_name     = "";
            task_descr_fd = '0;
            text_size     = '0;
            data_size     = '0;
            bss_size      = '0;
            entry_point   = '0;
            binary        = '0;
            /* verilator lint_on BLKSEQ */  
            map_ttt_size <= '0;
            binary_size  <= '0;
        end
        else begin
            case (state)
                LOAD_NEXT_APP: begin
                    $fscanf(app_start_fd, "%s\n",   app_name);
                end
                LOAD_APP: begin
                    $fscanf(app_start_fd, "%d",   start_time);
                    $fscanf(app_start_fd, "%d",   descr_size);
                    $fscanf(app_start_fd, "%d", app_task_cnt);
                    $fscanf(app_start_fd, "%x",      mapping);
                    /* verilator lint_off BLKSEQ */
                    app_descr_fd = $fopen($sformatf("applications/%s.txt", app_name), "r");
                    /* verilator lint_on BLKSEQ */
                    if (app_descr_fd == '0) begin
                        $display("[TaskParser] Could not open applications/%s.txt", app_name);
                        $finish();
                    end
                    $fscanf(app_descr_fd, "%d",        graph);
                    map_ttt_size <= app_task_cnt;
                end
                INJECT_DESCR_SIZE: begin
                    if (credit_i) begin
                        $display("[%7.3f] [TaskParser] Injecting %s descriptor", $time()/1_000_000.0, app_name);
                        /* verilator lint_off BLKSEQ */
                        descr_size = descr_size - 1'b1;
                        /* verilator lint_on BLKSEQ  */
                    end
                end
                INJECT_MAP: begin
                    if (credit_i)
                        map_ttt_size <= map_ttt_size - 1'b1;
                end
                INJECT_TTT: begin
                    if (credit_i)
                        $fscanf(app_start_fd, "%x", mapping);
                end
                INJECT_GRAPH: begin
                    if (credit_i) begin
                        $fscanf(app_descr_fd, "%d",        graph);
                        /* verilator lint_off BLKSEQ */
                        descr_size = descr_size - 1'b1;
                        /* verilator lint_on BLKSEQ */
                    end
                end
                LOAD_TASK: begin
                    $display("[%7.3f] [AppParser] Injection of %s descriptor finished", $time()/1_000_000.0, app_name);
                    $fscanf(app_descr_fd, "%s\n", task_name);
                    /* verilator lint_off BLKSEQ */
                    task_descr_fd = $fopen($sformatf("applications/%s/%s.txt", app_name, task_name), "r");
                    /* verilator lint_on BLKSEQ */
                    if (task_descr_fd == '0) begin
                        $display("[TaskParser] Could not open applications/%s/%s.txt", app_name, task_name);
                        $finish();
                    end
                    $fscanf(task_descr_fd, "%x",   text_size);
                    $fscanf(task_descr_fd, "%x",   data_size);
                    $fscanf(task_descr_fd, "%x",    bss_size);
                    $fscanf(task_descr_fd, "%x", entry_point);
                    $fscanf(task_descr_fd, "%x",      binary);
                    binary_size <= ((text_size + data_size) / 4) - 1; /* Convert to 32-bit */
                    $display("[%7.3f] [AppParser] Injecting task %s", $time()/1_000_000.0, task_name);
                end
                INJECT_BINARY: begin
                    if (credit_i) begin
                        $fscanf(task_descr_fd, "%x", binary);
                        binary_size <= binary_size - 1'b1;
                    end
                end
                LOAD_FINISH: begin
                    $display("[%7.3f] [AppParser] Injection of %s finished", $time()/1_000_000.0, task_name);
                    $fclose(task_descr_fd);
                    /* verilator lint_off BLKSEQ */
                    app_task_cnt = app_task_cnt - 1'b1;
                    /* verilator lint_on BLKSEQ */
                end
                LOAD_NEXT_TASK: begin
                    if (app_task_cnt == '0)
                        $fclose(app_descr_fd);
                end
            endcase
        end
    end

////////////////////////////////////////////////////////////////////////////////

    assign can_start = (($time() / 1_000_000 ) >= start_time);

    always_comb begin
        case (state)
            INJECT_DESCR_SIZE: data_o = descr_size;
            INJECT_TASK_CNT:   data_o = app_task_cnt;
            INJECT_MAP:        data_o = mapping;
            INJECT_TTT:        data_o = FLIT_SIZE'('1); // -1
            INJECT_GRAPH:      data_o = graph;
            INJECT_TEXT:       data_o = text_size;
            INJECT_DATA:       data_o = data_size;
            INJECT_BSS:        data_o = bss_size;
            INJECT_ENTRY:      data_o = entry_point;
            INJECT_BINARY:     data_o = binary;
            default:           data_o = '0;
        endcase
    end


////////////////////////////////////////////////////////////////////////////////

    assign eoa_o = (state == LOAD_EOA);

    assign tx_o = state inside {
        INJECT_DESCR_SIZE,
        INJECT_TASK_CNT,
        INJECT_MAP,
        INJECT_TTT,
        INJECT_GRAPH,
        INJECT_TEXT,
        INJECT_DATA,
        INJECT_BSS,
        INJECT_ENTRY,
        INJECT_BINARY
    };

    final begin
        $fclose(app_start_fd);
    end

endmodule
