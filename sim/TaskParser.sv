/**
 * TaskInjector
 * @file TaskParser.sv
 *
 * @author Angelo Elias Dal Zotto (angelo.dalzotto@edu.pucrs.br)
 * GAPH - Hardware Design Support Group (https://corfu.pucrs.br)
 * PUCRS - Pontifical Catholic University of Rio Grande do Sul (http://pucrs.br/)
 *
 * @date May 2024
 *
 * @brief File parser that injects data into Task Injector
 */

module TaskParser
#(
    parameter FLIT_SIZE         = 32,
    parameter INJECT_MAPPER     = 0,
    parameter string START_FILE = "app_start.txt",
    parameter string APP_PATH   = "../applications"
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    output logic                     eoa_o,
    output logic                     tx_o,
    input  logic                     credit_i,
    output logic [(FLIT_SIZE - 1):0] data_o,
    output logic [15:0]              mapper_address_o
);

    int app_start_fd;

    initial begin
        app_start_fd = $fopen(START_FILE, "r");
        if (app_start_fd == '0) begin
            $display("[%7.3f] [TaskParser] Could not open %s", $time()/1_000_000.0, START_FILE);
            $finish();
        end
    end

    int unsigned     app_task_cnt;
    int unsigned     map_ttt_size;
    int unsigned     descr_size;
    int unsigned     binary_size;
    string           task_name;

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
                next_state = $feof(app_start_fd) ? LOAD_EOA  : LOAD_APP;
            LOAD_APP:
                next_state = INJECT_MAPPER       ? LOAD_TASK : WAIT_START_TIME;
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
                next_state = !(credit_i && descr_size == '0)
                    ? INJECT_GRAPH
                    : (app_task_cnt != '0)
                        ? LOAD_TASK
                        : LOAD_EOA;
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
                next_state = (INJECT_MAPPER && task_name == "mapper_task")
                    ? INJECT_DESCR_SIZE
                    : (app_task_cnt == '0) 
                        ? LOAD_NEXT_APP 
                        : LOAD_TASK;
            LOAD_EOA:
                next_state = LOAD_EOA;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            state <= INJECT_MAPPER ? LOAD_APP : LOAD_NEXT_APP;
        else
            state <= next_state;
    end

////////////////////////////////////////////////////////////////////////////////

    string           app_name;
    longint unsigned start_time;
    int              app_descr_fd;
    int              mapping;
    int              app_graph;
    int              task_descr_fd;
    int unsigned     text_size;
    int unsigned     data_size;
    int unsigned     bss_size;
    int unsigned     entry_point;
    logic [31:0]     binary;
    logic [31:0]     ma_ttt;
    string           descr_path;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            /* verilator lint_off BLKSEQ */
            app_name         = "";
            start_time       = '0;
            descr_size       = '0;
            app_task_cnt     = '0;
            app_descr_fd     = '0;
            mapping          = '0;
            app_graph        = '0;
            task_name        = "";
            task_descr_fd    = '0;
            text_size        = '0;
            data_size        = '0;
            bss_size         = '0;
            entry_point      = '0;
            binary           = '0;
            descr_path       = "";
            /* verilator lint_on BLKSEQ */  
            mapper_address_o <= '1;
            map_ttt_size     <= '0;
            binary_size      <= '0;
        end
        else begin
            case (state)
                LOAD_NEXT_APP: begin
                    $fscanf(app_start_fd, "%s\n", app_name);
                end
                LOAD_APP: begin
                    /* verilator lint_off BLKSEQ */
                    if (!INJECT_MAPPER)
                        descr_path = $sformatf("%s/%s.txt", APP_PATH, app_name);
                    else
                        descr_path = $sformatf("ma_tasks.txt");
                    app_descr_fd = $fopen(descr_path, "r");
                    /* verilator lint_on BLKSEQ */
                    
                    if (app_descr_fd == '0) begin
                        $display("[%7.3f] [TaskParser] Could not open %s", $time()/1_000_000.0, descr_path);
                        $finish();
                    end

                    if (!INJECT_MAPPER) begin
                        $fscanf(app_start_fd, "%d", start_time);
                        $fscanf(app_descr_fd, "%d", app_task_cnt);
                        $fscanf(app_descr_fd, "%d", descr_size);
                    end
                    else begin
                        $fscanf(app_start_fd, "%d", app_task_cnt);
                        if (app_task_cnt < 1) begin
                            $display("[%7.3f] [TaskParser] MA should have at least 1 task", $time()/1_000_000.0);
                            $finish();
                        end

                        /* verilator lint_off BLKSEQ */
                        descr_size   = app_task_cnt;
                        app_graph = '0;
                        /* verilator lint_on BLKSEQ */
                    end

                    $fscanf(app_start_fd, "%x", mapping);

                    if (INJECT_MAPPER) begin
                        if (mapping == '1) begin
                            $display("[%7.3f] [TaskParser] MA tasks should be statically mapped", $time()/1_000_000.0);
                            $finish();
                        end

                        mapper_address_o <= mapping[15:0];
                    end
                    
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
                    if (credit_i) begin
                        map_ttt_size <= map_ttt_size - 1'b1;
                        if (INJECT_MAPPER)
                            $fscanf(app_start_fd, "%x", ma_ttt);
                    end
                end
                INJECT_TTT: begin
                    if (credit_i) begin
                        if (map_ttt_size != '0)
                            $fscanf(app_start_fd, "%x", mapping);
                        else if (!INJECT_MAPPER)
                            $fscanf(app_descr_fd, "%d", app_graph);
                    end
                end
                INJECT_GRAPH: begin
                    if (credit_i) begin
                        /* verilator lint_off BLKSEQ */
                        descr_size = descr_size - 1'b1;
                        /* verilator lint_on BLKSEQ */
                        if (!INJECT_MAPPER)
                            $fscanf(app_descr_fd, "%d", app_graph);
                    end
                end
                LOAD_TASK: begin
                    // $display("[%7.3f] [TaskParser] Injection of %s descriptor finished", $time()/1_000_000.0, app_name);

                    $fscanf(app_descr_fd, "%s\n", task_name);

                    if (INJECT_MAPPER) begin
                        /* verilator lint_off BLKSEQ */
                        app_name = task_name;
                        /* verilator lint_on BLKSEQ */
                        if (task_descr_fd == '0 && task_name != "mapper_task") begin
                            $display("[%7.3f] [TaskParser] First MA task should be mapper_task. Found: %s", $time()/1_000_000.0, task_name);
                            $finish();
                        end
                    end

                    /* verilator lint_off BLKSEQ */
                    task_descr_fd = $fopen($sformatf("%s/%s/%s.txt", APP_PATH, app_name, task_name), "r");
                    /* verilator lint_on BLKSEQ */  
                    if (task_descr_fd == '0) begin
                        $display("[%7.3f] [TaskParser] Could not open %s/%s/%s.txt", $time()/1_000_000.0, APP_PATH, app_name, task_name);
                        $finish();
                    end

                    $fscanf(task_descr_fd, "%x",   text_size);
                    $fscanf(task_descr_fd, "%x",   data_size);
                    $fscanf(task_descr_fd, "%x",    bss_size);
                    $fscanf(task_descr_fd, "%x", entry_point);
                    $fscanf(task_descr_fd, "%x",      binary);
                    binary_size <= ((text_size + data_size) / 4) - 1; /* Convert to 32-bit */
                    $display("[%7.3f] [TaskParser] Injecting task %s", $time()/1_000_000.0, task_name);
                end
                INJECT_BINARY: begin
                    if (credit_i) begin
                        $fscanf(task_descr_fd, "%x", binary);
                        binary_size <= binary_size - 1'b1;
                    end
                end
                LOAD_FINISH: begin
                    $display("[%7.3f] [TaskParser] Injection of %s finished", $time()/1_000_000.0, task_name);
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

    logic [31:0] ttt;
    assign ttt   = INJECT_MAPPER  ? ma_ttt    : '1;

    logic [31:0] graph;
    assign graph = !INJECT_MAPPER ? app_graph : '0;

    always_comb begin
        case (state)
            INJECT_DESCR_SIZE: data_o = descr_size;
            INJECT_TASK_CNT:   data_o = map_ttt_size;
            INJECT_MAP:        data_o = mapping;
            INJECT_TTT:        data_o = ttt;
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

    assign eoa_o = (!INJECT_MAPPER && state == LOAD_EOA);

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
