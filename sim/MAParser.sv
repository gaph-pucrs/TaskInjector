module MAParser
#(
    parameter PATH          = "",
    parameter FLIT_SIZE     = 32
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    output logic                     tx_o,
    input  logic                     credit_i,
    output logic [(FLIT_SIZE - 1):0] data_o,

    output logic [15:0]              mapper_address_o
);

    string task_name;

    int ma_start_fd;
    int ma_tasks_fd;
    int task_descr_fd;

    int unsigned ma_task_cnt;
    int unsigned binary_size;

    initial begin
    
    ////////////////////////////////////////////////////////////////////////////
    // Mapper task address fetch
    ////////////////////////////////////////////////////////////////////////////
    
        ma_start_fd = $fopen({PATH, "/ma_start.txt"}, "r");

        if (ma_start_fd == '0) begin
            $display("[TaskParser] Could not open ma_start.txt");
            $finish();
        end

        $fscanf(ma_start_fd, "%u", ma_task_cnt);
        if (ma_task_cnt < 1) begin
            $display("[TaskParser] MA should have at least 1 task");
            $finish();
        end

        $fscanf(ma_start_fd, "%x", mapper_address_o);

        if (mapper_address_o == '1) begin
            $display("[TaskParser] mapper_task should be statically mapped");
            $finish();
        end

        ma_tasks_fd = $fopen({PATH, "/management/ma_tasks.txt"}, "r");
        if (ma_tasks_fd == '0) begin
            $display("[MAParser] Could not open management/ma_tasks.txt");
            $finish();
        end

        $fscanf(ma_tasks_fd, "%s\n", task_name);

        if (task_name != "mapper_task") begin
            $display("[MAParser] First MA task should be mapper_task. Found: %s", task_name);
            $finish();
        end
        
    ////////////////////////////////////////////////////////////////////////////
    // Reset control
    ////////////////////////////////////////////////////////////////////////////

        tx_o   = 1'b0;
        data_o = '0;
        @(posedge rst_ni);

    ////////////////////////////////////////////////////////////////////////////
    // Mapper injection
    ////////////////////////////////////////////////////////////////////////////

        task_descr_fd = $fopen($sformatf("%s/management/%s/%s.txt", PATH, task_name, task_name), "r");
        if (task_descr_fd == '0) begin
            $display("[MAParser] Could not open %s", task_name);
            $finish();
        end

        tx_o   = 1'b1;

        $display("[%0d] [MAParser] Injecting task %s to PE %0x", $time(), task_name, mapper_address_o);

        $fscanf(task_descr_fd, "%x", data_o);
        binary_size = data_o;

        @(posedge clk_i iff credit_i == 1'b1); /* Inject text size  */

        $fscanf(task_descr_fd, "%x", data_o);
        binary_size += data_o;
        
        @(posedge clk_i iff credit_i == 1'b1); /* Inject data size  */

        $fscanf(task_descr_fd, "%x", data_o);
        @(posedge clk_i iff credit_i == 1'b1); /* Inject BSS size  */

        $fscanf(task_descr_fd, "%x", data_o);
        @(posedge clk_i iff credit_i == 1'b1); /* Inject entry point */

        binary_size /= 4;   /* Convert to 32-bit words */
        for (int b = 0; b < binary_size; b++) begin
            $fscanf(task_descr_fd, "%x", data_o);
            @(posedge clk_i iff credit_i == 1'b1);
        end

        $display("[%0d] [MAParser] Injection of %s finished", $time(), task_name);

        $fclose(task_descr_fd);

    ////////////////////////////////////////////////////////////////////////////
    // Descriptor injection
    ////////////////////////////////////////////////////////////////////////////

        $display("[%0d] [MAParser] Injecting MA descriptor", $time());

        data_o = ma_task_cnt;
        @(posedge clk_i iff credit_i == 1'b1); /* Inject graph descriptor size */
        @(posedge clk_i iff credit_i == 1'b1); /* Inject number of tasks */

        data_o = {16'b0, mapper_address_o};
        @(posedge clk_i iff credit_i == 1'b1); /* Inject mapping of first task (mapper) */

        $fscanf(ma_start_fd, "%x", data_o);
        @(posedge clk_i iff credit_i == 1'b1); /* Inject task type tag of first task (mapper) */

        for (int t = 1; t < ma_task_cnt; t++) begin
            $fscanf(ma_start_fd, "%x", data_o);
            @(posedge clk_i iff credit_i == 1'b1); /* Inject mapping + ttt of remaining tasks */
        end

        $fclose(ma_start_fd);

        data_o = '0;    /* Insert null descriptor graph for MA */
        for (int t = 0; t < ma_task_cnt; t++) begin
            @(posedge clk_i iff credit_i == 1'b1); /* Inject mapping + ttt of remaining tasks */
        end

        $display("[%0d] [MAParser] Injection of MA descriptor finished", $time());

    ////////////////////////////////////////////////////////////////////////////
    // Remaining tasks injection
    ////////////////////////////////////////////////////////////////////////////

        for (int t = 1; t < ma_task_cnt; t++) begin
            $fgets(task_name, ma_tasks_fd);

            task_descr_fd = $fopen({PATH, "/management/", task_name, "/", task_name, ".txt"}, "r");

            $fscanf(task_descr_fd, "%x", data_o);
            binary_size = data_o;

            @(posedge clk_i iff credit_i == 1'b1); /* Inject text size  */

            $fscanf(task_descr_fd, "%x", data_o);
            binary_size += data_o;
            
            @(posedge clk_i iff credit_i == 1'b1); /* Inject data size  */

            $fscanf(task_descr_fd, "%x", data_o);
            @(posedge clk_i iff credit_i == 1'b1); /* Inject BSS size  */

            $fscanf(task_descr_fd, "%x", data_o);
            @(posedge clk_i iff credit_i == 1'b1); /* Inject entry point */

            binary_size /= 4;   /* Convert to 32-bit words */
            for (int b = 0; b < binary_size; b++) begin
                $fscanf(task_descr_fd, "%x", data_o);
                @(posedge clk_i iff credit_i == 1'b1);
            end

            $fclose(task_descr_fd);
        end

        tx_o  = 1'b0;
    end

endmodule
