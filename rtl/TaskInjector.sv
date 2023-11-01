module TaskInjector
    import TaskInjectorPkg::*;
#(
    parameter FLIT_SIZE        = 32,
    parameter MAPPER_ADDRESS   = 0,
    parameter MAX_PAYLOAD_SIZE = 32
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  logic                     src_rx_i,
    output logic                     src_credit_o,
    input  logic [(FLIT_SIZE - 1):0] src_data_i,

    /* NoC Output */
    output logic                     noc_tx_o,
    input  logic                     noc_credit_i,
    output logic [(FLIT_SIZE - 1):0] noc_data_o,

    /* NoC Input */
    input  logic                     noc_rx_i,
    output logic                     noc_credit_o,
    input  logic [(FLIT_SIZE - 1):0] noc_data_i,
);

    localparam HEADER_SIZE = 13;

    typedef enum logic [] {
        SEND_IDLE,
        SEND_DATA_AV,
        SEND_WAIT_REQUEST
    } send_fsm_t;

    send_fsm_t send_state;

    typedef enum logic [] {
        RECEIVE_HEADER,
        RECEIVE_SIZE,
        RECEIVE_WAIT_DLVR
    } receive_fsm_t;

    receive_fsm_t receive_state;

    typedef enum logic [] {
        INJECTOR_IDLE,
        INJECTOR_SEND_DESCRIPTOR
    } inject_fsm_t;

    inject_fsm_t inject_state;

////////////////////////////////////////////////////////////////////////////////
// Injector
////////////////////////////////////////////////////////////////////////////////

    logic [7:0] task_cnt;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            task_cnt <= '0;
        else if (inject_state == INJECTOR_IDLE)
            task_cnt <= src_data_i; /* @todo add update on MAP */
    end

    logic [7:0] current_task;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            current_task <= '0;
        else begin
            if (inject_state == INJECTOR_MAP)
                current_task <= '0;
            else if (inject_state == INJECTOR_NEXT_TASK)
                current_task <= current_task + 1'b1;
        end
    end

    inject_fsm_t inject_next_state;
    always_comb begin
        case (inject_state)
            INJECTOR_IDLE:             inject_next_state = src_rx_i                                ? INJECTOR_SEND_DESCRIPTOR : INJECTOR_IDLE;
            INJECTOR_SEND_DESCRIPTOR:  inject_next_state = (send_state == SEND_FINISHED)           ? INJECTOR_MAP             : INJECTOR_SEND_DESCRIPTOR;
            INJECTOR_MAP:              inject_next_state = (receive_state == RECEIVE_WAIT_ALLOC)   ? INJECTOR_RECEIVE_TXT_SZ  : INJECTOR_MAP;
            INJECTOR_RECEIVE_TXT_SZ:   inject_next_state = src_rx_i                                ? INJECTOR_RECEIVE_DATA_SZ : INJECTOR_RECEIVE_TXT_SZ;
            INJECTOR_RECEIVE_DATA_SZ:  inject_next_state = src_rx_i                                ? INJECTOR_RECEIVE_BSS_SZ  : INJECTOR_RECEIVE_DATA_SZ;
            INJECTOR_RECEIVE_BSS_SZ:   inject_next_state = src_rx_i                                ? INJECTOR_RECEIVE_ENTRY   : INJECTOR_RECEIVE_BSS_SZ;
            INJECTOR_RECEIVE_ENTRY:    inject_next_state = src_rx_i                                ? INJECTOR_SEND_TASK       : INJECTOR_RECEIVE_ENTRY;
            INJECTOR_SEND_TASK:        inject_next_state = (send_state == SEND_FINISHED)           ? INJECTOR_NEXT_TASK       : INJECTOR_SEND_TASK;
            INJECTOR_NEXT_TASK:        inject_next_state = (current_task == task_cnt - 1'b1)       ? INJECTOR_WAIT_COMPLETE   : INJECTOR_RECEIVE_TXT_SZ;
            INJECTOR_WAIT_COMPLETE:    inject_next_state = (receive_state == RECEIVE_MAP_COMPLETE) ? INJECTOR_IDLE            : INJECTOR_WAIT_COMPLETE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            inject_state <= INJECTOR_IDLE;
        else
            inject_state <= inject_next_state;
    end

    always_comb begin
        if (send_state == SEND_PACKET) begin
            if (out_header_idx == HEADER_SIZE && aux_header_idx == aux_header_size)
                src_credit_o = noc_credit_i;
            else
                src_credit_o = 1'b0;
        end
        else if (inject_state inside {INJECTOR_RECEIVE_TXT_SZ, INJECTOR_RECEIVE_DATA_SZ, INJECTOR_RECEIVE_BSS_SZ, INJECTOR_RECEIVE_ENTRY}) begin
            src_credit_o = 1'b1;
        end
        else begin
            src_credit_o = 1'b0;
        end
    end

////////////////////////////////////////////////////////////////////////////////
// Send control
////////////////////////////////////////////////////////////////////////////////

    logic [(HEADER_SIZE - 1):0][(FLIT_SIZE - 1):0] out_header;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_header <= '0;
        end
        else begin
            if (receive_state == RECEIVE_WAIT_REQ) begin
                out_header    <= '0;       /* @todo change to in_header fields */
                out_header[0] <= MAPPER_ADDRESS;     /* Target address */
                out_header[1] <= HEADER_SIZE - 2'd2; /* Payload size   */
                out_header[2] <= MESSAGE_REQUEST;    /* Service        */
                out_header[3] <= '0;                 /* Producer task  */
                out_header[4] <= INJECTOR_ADDRESSS;  /* Consumer task  */
                out_header[8] <= INJECTOR_ADDRESSS;  /* Source address */
            end
            else begin
                case (inject_state)
                    INJECTOR_SEND_DESCRIPTOR: begin
                        case (send_state)
                            SEND_IDLE: begin
                                /* DATA_AV for App descriptor */
                                out_header    <= '0;
                                out_header[0] <= MAPPER_ADDRESS;     /* Target address */
                                out_header[1] <= HEADER_SIZE - 2'd2; /* Payload size   */
                                out_header[2] <= DATA_AV;            /* Service        */
                                out_header[3] <= INJECTOR_ADDRESSS;  /* Producer task  */
                                out_header[4] <= '0;                 /* Consumer task  */
                                out_header[8] <= INJECTOR_ADDRESSS;  /* Source address */
                            end
                            SEND_WAIT_REQUEST: begin
                                /* DELIVERY for App descriptor */
                                out_header    <= '0;   /* @todo change to in_header fields */
                                out_header[0] <= MAPPER_ADDRESS;                        /* Target address */
                                out_header[1] <= {task_cnt, 1'b0} + HEADER_SIZE + 1'b1; /* Payload size   */
                                out_header[2] <= MESSAGE_DELIVERY;                      /* Service        */
                                out_header[3] <= INJECTOR_ADDRESSS;                     /* Producer task  */
                                out_header[4] <= '0;                                    /* Consumer task  */
                                out_header[8] <= {({task_cnt, 1'b0} + 2'd3), 2'b0};     /* Message length */
                            end
                            default: ;
                        endcase
                    end
                    INJECTOR_RECEIVE_TXT_SZ: begin
                        out_header     <= '0;
                        out_header[0]  <= in_payload[current_task + 2'd2];    /* Target address */
                        out_header[1]  <= src_data_i;                         /* Payload size   */
                        out_header[2]  <= TASK_ALLOCATION;                    /* Service        */
                        out_header[3]  <= {in_payload[1][7:0], current_task}; /* Task ID        */
                        out_header[4]  <= MAPPER_ADDRESS;                     /* Mapper address */
                        out_header[8]  <= '0;                                 /* Mapper ID      */
                        out_header[10] <= src_data_i;                         /* Text size      */
                    end
                    INJECTOR_RECEIVE_DATA_SZ: begin
                        out_header[9] <= src_data_i; /* Data size */

                        if (src_rx_i)
                            out_header[1] <= out_header[1] + src_data_i;
                    end
                    INJECTOR_RECEIVE_BSS_SZ: begin
                        out_header[11] <= src_data_i; /* BSS size */

                        if (src_rx_i) begin
                            /* Divide payload size by 4 */
                            out_header[1][(FLIT_SIZE - 3):0]               <= out_header[1][(FLIT_SIZE - 1):2];
                            out_header[1][(FLIT_SIZE - 1):(FLIT_SIZE - 2)] <= '0;
                        end
                    end
                    INJECTOR_RECEIVE_ENTRY: begin
                        out_header[12] <= src_data_i; /* Entry point */

                        if (src_rx_i)
                            out_header[1] <= out_header[1] + HEADER_SIZE - 2'd2;
                    end
                    default: ;
                endcase
            end
        end            
    end

    logic [(FLIT_SIZE - 1):0] out_header_idx;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_header_idx <= '0;
        end
        else begin
            if (send_state inside {SEND_IDLE, SEND_WAIT_REQUEST})
                out_header_idx <= '0;
            else if (noc_credit_i && out_header_idx != HEADER_SIZE)
                out_header_idx <= out_header_idx + 1'b1;
        end
    end

    logic      [(FLIT_SIZE - 1):0] aux_header_size;
    logic [1:0][(FLIT_SIZE - 1):0] aux_header;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aux_header      <= '0;
            aux_header_size <= '0;
        end
        else begin
            case (inject_state)
                INJECTOR_SEND_DESCRIPTOR: begin
                    if (send_state == SEND_WAIT_REQUEST) begin
                        aux_header_size <= 2'd2;
                        aux_header      <= '0;
                        aux_header[0]   <= NEW_APP;
                        aux_header[1]   <= INJECTOR_ADDRESSS;
                    end
                end
                default: aux_header_size <= '0;
            endcase
        end
    end

    logic [(FLIT_SIZE - 1):0] aux_header_idx;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aux_header_idx  <= '0;
        end
        else begin
            if (send_state inside {SEND_IDLE, SEND_WAIT_REQUEST})
                aux_header_idx  <= '0;
            else if (noc_credit_i && out_header_idx == HEADER_SIZE && aux_header_idx != aux_header_size)
                aux_header_idx  <= aux_header_idx + 1'b1;
        end
    end

    logic sent;
    assign sent = noc_credit_i && (out_sent_cnt  == out_header[1] + 1'b1);

    send_fsm_t send_next_state;
    always_comb begin
        case (send_state)
            SEND_IDLE: begin
                case (inject_state)
                    INJECTOR_SEND_DESCRIPTOR: send_next_state = SEND_DATA_AV;
                    INJECTOR_MAP:             send_next_state = (receive_state == RECEIVE_WAIT_REQ) ? SEND_REQUEST : SEND_IDLE;
                    INJECTOR_SEND_TASK:       send_next_state = SEND_PACKET;
                    INJECTOR_WAIT_COMPLETE:   send_next_state = (receive_state == RECEIVE_WAIT_REQ) ? SEND_REQUEST : SEND_IDLE;
                    default:                  send_next_state = SEND_IDLE;
                endcase
            end
            SEND_DATA_AV:       send_next_state = sent                                 ? SEND_WAIT_REQUEST : SEND_DATA_AV;
            SEND_REQUEST:       send_next_state = sent                                 ? SEND_FINISHED     : SEND_REQUEST;
            SEND_WAIT_REQUEST:  send_next_state = (receive_state == RECEIVE_WAIT_DLVR) ? SEND_PACKET       : SEND_WAIT_REQUEST;
            SEND_PACKET:        send_next_state = sent                                 ? SEND_FINISHED     : SEND_PACKET;
            SEND_FINISHED:      send_next_state = SEND_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            send_state <= SEND_IDLE;
        else
            send_state <= send_next_state;
    end

    logic [(FLIT_SIZE - 1):0] out_sent_cnt;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_sent_cnt <= '0;
        end
        else begin
            if (send_state inside {SEND_IDLE, SEND_WAIT_REQUEST, SEND_FINISHED})
                out_sent_cnt <= '0;
            else if (noc_credit_i)
                out_sent_cnt <= out_sent_cnt + 1'b1;
        end
    end

    always_comb begin
        if (out_header_idx != HEADER_SIZE)
            noc_data_o = out_header[out_header_idx];
        else if (aux_header_idx != aux_header_size)
            noc_data_o = aux_header[aux_header_idx];
        else
            noc_data_o = src_data_i;
    end

    always_comb begin
        if (send_state == SEND_DATA_AV) begin
            noc_tx_o = 1'b1;
        end
        else if (send_state == SEND_PACKET) begin
            if (out_header_idx != HEADER_SIZE || aux_header_idx != aux_header_size)
                noc_tx_o = 1'b1;
            else
                noc_tx_o = src_rx_i;
        end
        else begin
            noc_tx_o = 1'b0;
        end
    end

////////////////////////////////////////////////////////////////////////////////
// Receive control
////////////////////////////////////////////////////////////////////////////////

    logic [(FLIT_SIZE - 1):0] in_header_idx;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            in_header_idx <= '0;
        end
        else begin
            if (receive_state == RECEIVE_IDLE)
                in_header_idx <= '0;
            else if (noc_rx_i && noc_credit_o && in_header_idx != HEADER_SIZE)
                in_header_idx <= in_header_idx + 1'b1;
        end
    end

    logic [(HEADER_SIZE - 1):0][(FLIT_SIZE - 1):0] in_header;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            in_header <= '0;
        end
        else begin
            if (noc_rx_i && noc_credit_o && in_header_idx != HEADER_SIZE)
                in_header[in_header_idx] <= noc_data_i;
        end
    end

    logic [(FLIT_SIZE - 1):0] in_payload_idx;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            in_payload_idx <= '0;
        end
        else begin
            if (receive_state == RECEIVE_IDLE)
                in_payload_idx <= '0;
            else if (noc_rx_i && noc_credit_o && in_header_idx == HEADER_SIZE)
                in_payload_idx <= in_payload_idx + 1'b1;
        end
    end

    logic [(MAX_PAYLOAD_SIZE - 1):0][(FLIT_SIZE - 1):0] in_payload;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            in_payload <= '0;
        end
        else begin
            if (noc_rx_i && noc_credit_o && in_header_idx == HEADER_SIZE)
                in_payload[in_payload_idx] <= noc_data_i;
        end
    end

    logic [(FLIT_SIZE - 1):0] receive_cntr;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            receive_cntr <= '0;
        end
        else begin
            if (receive_state == RECEIVE_SERVICE)
                receive_cntr <= 1'b1;
            else if (noc_rx_i && (receive_state inside {RECEIVE_REQUEST, RECEIVE_DATA_AV, RECEIVE_DELIVERY}))
                receive_cntr <= receive_cntr + 1'b1;
        end
    end

    receive_fsm_t receive_next_state;

    always_comb begin
        case (receive_state)
            RECEIVE_IDLE: begin
                if (send_state == SEND_WAIT_REQUEST)
                    receive_next_state = RECEIVE_HEADER;
                else if (inject_state == INJECTOR_MAP)
                    receive_next_state = RECEIVE_HEADER;
                else
                    receive_next_state = RECEIVE_IDLE;
            end
            RECEIVE_HEADER:    receive_next_state = (noc_rx_i) ? RECEIVE_SIZE    : RECEIVE_HEADER;
            RECEIVE_SIZE:      receive_next_state = (noc_rx_i) ? RECEIVE_SERVICE : RECEIVE_SIZE;
            RECEIVE_SERVICE: begin
                if (noc_rx_i) begin
                    case (noc_data_i)
                        MESSAGE_REQUEST:  receive_next_state = RECEIVE_REQUEST;
                        DATA_AV:          receive_next_state = RECEIVE_DATA_AV;
                        MESSAGE_DELIVERY: receive_next_state = RECEIVE_DELIVERY;
                        default:          receive_next_state = RECEIVE_DROP;
                    endcase
                end
            end
            RECEIVE_REQUEST: begin
                if (noc_rx_i) begin
                    if (receive_cntr == in_header[1] - 1'b1)
                        receive_next_state = RECEIVE_WAIT_DLVR;
                    else if (receive_cntr == HEADER_SIZE - 2'd3)
                        receive_next_state = RECEIVE_DROP;
                    else
                        receive_next_state = RECEIVE_REQUEST;
                end
            end
            RECEIVE_DATA_AV: begin
                if (noc_rx_i) begin
                    if (receive_cntr == in_header[1] - 1'b1)
                        receive_next_state = RECEIVE_WAIT_REQ;
                    else if (receive_cntr == HEADER_SIZE - 2'd3)
                        receive_next_state = RECEIVE_DROP;
                    else
                        receive_next_state = RECEIVE_DATA_AV;
                end
            end
            RECEIVE_DELIVERY: begin
                if (noc_rx_i) begin
                    if (receive_cntr == in_header[1] - 1'b1) begin
                        case (in_payload[0])
                            APP_ALLOCATION_REQUEST: receive_next_state = RECEIVE_WAIT_ALLOC;
                            APP_MAPPING_COMPLETE:   receive_next_state = RECEIVE_MAP_COMPLETE;
                            default:                receive_next_state = RECEIVE_IDLE;    /* Ignore */
                        endcase
                    end
                    else if (receive_cntr == MAX_PAYLOAD_SIZE + HEADER_SIZE - 2'd3) begin
                        receive_next_state = RECEIVE_DROP;
                    end
                    else begin
                        receive_next_state = RECEIVE_DELIVERY;
                    end
                end
            end
            RECEIVE_WAIT_REQ:     receive_next_state = (send_state == SEND_FINISHED)            ? RECEIVE_IDLE : RECEIVE_WAIT_REQ;
            RECEIVE_WAIT_DLVR:    receive_next_state = (send_state == SEND_FINISHED)            ? RECEIVE_IDLE : RECEIVE_WAIT_DLVR;
            RECEIVE_WAIT_ALLOC:   receive_next_state = (inject_state == INJECTOR_WAIT_COMPLETE) ? RECEIVE_IDLE : RECEIVE_WAIT_ALLOC;
            RECEIVE_MAP_COMPLETE: receive_next_state = RECEIVE_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            receive_state <= RECEIVE_IDLE;
        else
            receive_state <= receive_next_state;
    end

    assign noc_credit_o = !(receive_state inside {RECEIVE_IDLE, RECEIVE_WAIT_DLVR, RECEIVE_WAIT_REQ});

endmodule
