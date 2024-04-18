module AppParser
#(
    parameter FLIT_SIZE     = 32
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    output logic                     eoa_o,
    output logic                     tx_o,
    input  logic                     credit_i,
    output logic [(FLIT_SIZE - 1):0] data_o
);
    
    string app_name;
    string task_name;

    int app_start_fd;
    int app_descr_fd;
    int task_descr_fd;

    longint unsigned start_time;
    int unsigned descr_size;
    int unsigned app_task_cnt;
    int unsigned binary_size;

    initial begin


        app_start_fd = $fopen("app_start.txt", "r");
        if (app_start_fd == '0) begin
            $display("[AppParser] Could not open app_start.txt");
            $finish();
        end

    ////////////////////////////////////////////////////////////////////////////
    // Reset control
    ////////////////////////////////////////////////////////////////////////////

        eoa_o  = 1'b0;
        tx_o   = 1'b0;
        data_o = '0;
        @(posedge clk_i iff rst_ni == 1'b1);
    
    ////////////////////////////////////////////////////////////////////////////
    // Application start control
    ////////////////////////////////////////////////////////////////////////////
        while (!$feof(app_start_fd)) begin
            $fscanf(app_start_fd, "%s\n", app_name);

            $fscanf(app_start_fd, "%d", start_time);

            @(posedge clk_i iff ($time() / 1_000_000 ) >= start_time);

            $display("[%0d] [AppParser] Injecting %s descriptor", $time(), app_name);

        ////////////////////////////////////////////////////////////////////////
        // Descriptor injection
        ////////////////////////////////////////////////////////////////////////

            $fscanf(app_start_fd, "%d", descr_size);
            data_o = descr_size;

            tx_o = 1'b1;
            @(posedge clk_i iff credit_i == 1'b1); /* Inject graph descriptor size */

            $fscanf(app_start_fd, "%d", app_task_cnt);
            data_o = app_task_cnt;
            @(posedge clk_i iff credit_i == 1'b1); /* Inject number of tasks */

            for (int t = 0; t < app_task_cnt; t++) begin
                $fscanf(app_start_fd, "%x", data_o);
                @(posedge clk_i iff credit_i == 1'b1); /* Inject mapping  */

                data_o = FLIT_SIZE'('1); // -1
                @(posedge clk_i iff credit_i == 1'b1); /* Inject task type tag */
            end

            app_descr_fd = $fopen($sformatf("applications/%s.txt", app_name), "r");
            if (app_descr_fd == '0) begin
                $display("[AppParser] Could not open applications/%s.txt", app_name);
                $finish();
            end

            for (int g = 0; g < descr_size; g++) begin
                $fscanf(app_descr_fd, "%d", data_o);
                @(posedge clk_i iff credit_i == 1'b1); /* Inject graph descriptor  */
            end

            $display("[%0d] [AppParser] Injection of %s descriptor finished", $time(), app_name);

        ////////////////////////////////////////////////////////////////////////
        // Task injection
        ////////////////////////////////////////////////////////////////////////
            for (int t = 0; t < app_task_cnt; t++) begin
                $fscanf(app_descr_fd, "%s\n", task_name);

                task_descr_fd = $fopen($sformatf("applications/%s/%s.txt", app_name, task_name), "r");
                if (task_descr_fd == '0) begin
                    $display("[AppParser] Could not open applications/%s/%s.txt", app_name, task_name);
                    $finish();
                end

                $display("[%0d] [AppParser] Injecting task %s", $time(), task_name);

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

                $display("[%0d] [AppParser] Injection of %s finished", $time(), task_name);

                $fclose(task_descr_fd);
            end

            $fclose(app_descr_fd);
            tx_o   = 1'b0;
        end

        $fclose(app_start_fd);

        eoa_o = 1'b1;
    end

endmodule
