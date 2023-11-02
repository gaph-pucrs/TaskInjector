module AppParser
#(
    parameter PATH          = "",
    parameter SIM_FREQ      = 100_000,
    parameter FLIT_SIZE     = 32
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  logic                     tick_cnt_i,

    output logic                     eoa_o,
    output logic                     tx_o,
    input  logic                     credit_i,
    output logic [(FLIT_SIZE - 1):0] data_o
);

    parameter MS_DIV = SIM_FREQ / 1_000;
    
    unsigned ms_cnt;
    assign ms_cnt = tick_cnt_i / MS_DIV;

    initial begin

    ////////////////////////////////////////////////////////////////////////////
    // Reset control
    ////////////////////////////////////////////////////////////////////////////

        eoa_o <= 1'b0;
        tx_o   = 1'b0;
        data_o = '0;
        @(posedge rst_ni);
    
    ////////////////////////////////////////////////////////////////////////////
    // Application start control
    ////////////////////////////////////////////////////////////////////////////

        int app_start_fd = $fopen({PATH, "/app_start.txt"}, "r");

        if (app_start_fd == '0) begin
            $display("[TaskParser] Could not open app_start.txt");
            $finish();
        end

        while (!feof(app_start_fd)) begin
            string app_name;
            $fgets(app_name, app_start_fd);

            unsigned start_time;
            $fscanf(app_start_fd, "%u", start_time);

            wait(ms_cnt >= start_time);

        ////////////////////////////////////////////////////////////////////////
        // Descriptor injection
        ////////////////////////////////////////////////////////////////////////

            $fscanf(app_start_fd, "%u", data_o);
            unsigned descr_size = data_o;

            tx_o = 1'b1;

            wait(credit_i == 1'b1); /* Inform injector of descriptor size */
            @posedge(clk_i);

            $fscanf(app_start_fd, "%u", data_o);
            unsigned app_task_cnt = data_o;

            wait(credit_i == 1'b1); /* Inform injector (and inject) app task count */
            @posedge(clk_i);

            for (int t = 0; t < app_task_cnt; t++) begin
                $fscanf(app_start_fd, "%u", data_o);
                wait(credit_i == 1'b1); /* Inject task mapping  */
                @posedge(clk_i);

                data_o = FLIT_SIZE'(1);
                wait(credit_i == 1'b1); /* Inject task type tag */
                @posedge(clk_i);
            end

            int app_descr_fd = $fopen({PATH, "/applications/", app_name, ".txt"}, "r");

            for (int g = 0; g < descr_size; g++) begin
                $fscanf(app_descr_fd, "%u", data_o);
                wait(credit_i == 1'b1); /* Inject graph descriptor  */
                @posedge(clk_i);
            end

        ////////////////////////////////////////////////////////////////////////
        // Task injection
        ////////////////////////////////////////////////////////////////////////
            for (int t = 0; t < app_task_cnt; t++) begin
                string task_name;
                $fgets(task_name, app_descr_fd);

                int task_descr_fd = $fopen({PATH, "/applications/", app_name, "/", task_name, ".txt"}, "r");

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
            end

            $fclose(app_descr_fd);
        end

        $fclose(app_start_fd);

        eoa_o = 1'b1;
        tx_o  = 1'b0;
    end

endmodule
