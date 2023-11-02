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

    output logic [15:0]              mapper_address_o;
);

    initial begin
    
    ////////////////////////////////////////////////////////////////////////////
    // Mapper task address fetch
    ////////////////////////////////////////////////////////////////////////////
    
        int ma_start_fd = $fopen({PATH, "/ma_start.txt"}, "r");

        if (ma_start_fd == '0) begin
            $display("[TaskParser] Could not open ma_start.txt");
            $finish();
        end

        unsigned ma_task_cnt;
        $fscanf(ma_start_fd, "%u", ma_task_cnt);
        if (ma_task_cnt < 1) begin
            $display("[TaskParser] MA should have at least 1 task");
            $finish();
        end

        $fscanf(ma_start_fd, "%d", mapper_address_o);

        if (mapper_address_o == '1) begin
            $display("[TaskParser] mapper_task should be statically mapped");
            $finish();
        end

        int ma_tasks_fd = $fopen({PATH, "/management/ma_tasks.txt"}, "r");
        if (ma_tasks_fd == '0) begin
            $display("[MAParser] Could not open management/ma_tasks.txt");
            $finish();
        end

        string task_name;
        $fgets(task_name, ma_tasks_fd);

        if (task_name != "mapper_task") begin
            $display("[MAParser] First MA task should be mapper_task");
            $finish();
        end
        
    ////////////////////////////////////////////////////////////////////////////
    // Reset control
    ////////////////////////////////////////////////////////////////////////////

        eoa_o <= 1'b0;
        tx_o   = 1'b0;
        data_o = '0;
        @(posedge rst_ni);

    ////////////////////////////////////////////////////////////////////////////
    // Mapper injection
    ////////////////////////////////////////////////////////////////////////////

        int task_descr_fd = $fopen({PATH, "/management/", task_name, "/", task_name, ".txt"}, "r");

        $fscanf(task_descr_fd, "%u", data_o);
        unsigned binary_size = data_o;

        wait(credit_i == 1'b1); /* Inject text size  */
        @posedge(clk_i);

        $fscanf(task_descr_fd, "%u", data_o);
        binary_size += data_o;
        
        wait(credit_i == 1'b1); /* Inject data size  */
        @posedge(clk_i);

        $fscanf(task_descr_fd, "%u", data_o);
        wait(credit_i == 1'b1); /* Inject BSS size  */
        @posedge(clk_i);

        $fscanf(task_descr_fd, "%u", data_o);
        wait(credit_i == 1'b1); /* Inject entry point */
        @posedge(clk_i);

        binary_size /= 4;   /* Convert to 32-bit words */
        for (int b = 0; b < binary_size; b++) begin
            $fscanf(task_descr_fd, "%u", data_o);
            wait(credit_i == 1'b1);
            @posedge(clk_i);
        end

        $fclose(task_descr_fd);

    ////////////////////////////////////////////////////////////////////////////
    // Descriptor injection
    ////////////////////////////////////////////////////////////////////////////

        data_o = ma_task_cnt;
        wait(credit_i == 1'b1); /* Inject graph descriptor size */
        @posedge(clk_i);
        wait(credit_i == 1'b1); /* Inject number of tasks */
        @posedge(clk_i);

        data_o = mapper_address_o;
        wait(credit_i == 1'b1); /* Inject mapping of first task (mapper) */
        @posedge(clk_i);

        $fscanf(ma_start_fd, "%u", data_o);
        wait(credit_i == 1'b1); /* Inject task type tag of first task (mapper) */
        @posedge(clk_i);

        for (int t = 1; t < ma_task_cnt; t++) begin
            $fscanf(ma_start_fd, "%u", data_o);
            wait(credit_i == 1'b1); /* Inject mapping + ttt of remaining tasks */
            @posedge(clk_i);
        end

        $fclose(ma_start_fd);

        data_o = '0;    /* Insert null descriptor graph for MA */
        for (int t = 0; t < ma_task_cnt; t++) begin
            wait(credit_i == 1'b1); /* Inject mapping + ttt of remaining tasks */
            @posedge(clk_i);
        end

    ////////////////////////////////////////////////////////////////////////////
    // Remaining tasks injection
    ////////////////////////////////////////////////////////////////////////////

        for (int t = 1; t < ma_task_cnt; t++) begin
            $fgets(task_name, ma_tasks_fd);

            task_descr_fd = $fopen({PATH, "/management/", task_name, "/", task_name, ".txt"}, "r");

            $fscanf(task_descr_fd, "%u", data_o);
            binary_size = data_o;

            wait(credit_i == 1'b1); /* Inject text size  */
            @posedge(clk_i);

            $fscanf(task_descr_fd, "%u", data_o);
            binary_size += data_o;
            
            wait(credit_i == 1'b1); /* Inject data size  */
            @posedge(clk_i);

            $fscanf(task_descr_fd, "%u", data_o);
            wait(credit_i == 1'b1); /* Inject BSS size  */
            @posedge(clk_i);

            $fscanf(task_descr_fd, "%u", data_o);
            wait(credit_i == 1'b1); /* Inject entry point */
            @posedge(clk_i);

            binary_size /= 4;   /* Convert to 32-bit words */
            for (int b = 0; b < binary_size; b++) begin
                $fscanf(task_descr_fd, "%u", data_o);
                wait(credit_i == 1'b1);
                @posedge(clk_i);
            end

            $fclose(task_descr_fd);
        end

        tx_o  = 1'b0;
    end

endmodule
