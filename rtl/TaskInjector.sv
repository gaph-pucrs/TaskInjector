/**
 * TaskInjector
 * @file TaskInjector.sv
 *
 * @author Angelo Elias Dal Zotto (angelo.dalzotto@edu.pucrs.br)
 * GAPH - Hardware Design Support Group (https://corfu.pucrs.br)
 * PUCRS - Pontifical Catholic University of Rio Grande do Sul (http://pucrs.br/)
 *
 * @date November 2023
 *
 * @brief Task Injector module
 */

`include "TaskInjectorPkg.sv"

module TaskInjector
    import TaskInjectorPkg::*;
#(
    parameter logic [31:0] INJECTOR_ADDRESS = 32'hE0000000,
    parameter              FLIT_SIZE        = 32,
    parameter              MAX_PAYLOAD_SIZE = 32,
    parameter              INJECT_MAPPER    = 0
)
(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  logic                     src_eoa_i,
    input  logic                     src_rx_i,
    output logic                     src_credit_o,
    input  logic [(FLIT_SIZE - 1):0] src_data_i,
    input  logic [15:0]              mapper_address_i,

    /* NoC Output */
    output logic                     noc_tx_o,
    output logic                     noc_eop_o,
    input  logic                     noc_credit_i,
    output logic [(FLIT_SIZE - 1):0] noc_data_o,

    /* NoC Input */
    input  logic                     noc_rx_i,
    input  logic                     noc_eop_i,
    output logic                     noc_credit_o,
    input  logic [(FLIT_SIZE - 1):0] noc_data_i
);

    localparam MAX_AUX_HEADER_SIZE = 3;

    typedef enum logic [13:0] {
        INJECTOR_IDLE             = 14'b00000000000001,
        INJECTOR_RECEIVE_APP_HASH = 14'b00000000000010,
        INJECTOR_RECEIVE_TASK_CNT = 14'b00000000000100,
        INJECTOR_SEND_DESCRIPTOR  = 14'b00000000001000,
        INJECTOR_MAP              = 14'b00000000010000,
        INJECTOR_RECEIVE_TXT_SZ   = 14'b00000000100000,
        INJECTOR_RECEIVE_DATA_SZ  = 14'b00000001000000,
        INJECTOR_RECEIVE_BSS_SZ   = 14'b00000010000000,
        INJECTOR_RECEIVE_ENTRY    = 14'b00000100000000,
        INJECTOR_SEND_TASK        = 14'b00001000000000,
        INJECTOR_NEXT_TASK        = 14'b00010000000000,
        INJECTOR_WAIT_COMPLETE    = 14'b00100000000000,
        INJECTOR_SEND_EOA         = 14'b01000000000000,
        INJECTOR_FINISHED         = 14'b10000000000000
    } inject_fsm_t;
    inject_fsm_t inject_state;

    typedef enum logic [5:0] {
        SEND_IDLE         = 6'b000001,
        SEND_DATA_AV      = 6'b000010,
        SEND_REQUEST      = 6'b000100,
        SEND_WAIT_REQUEST = 6'b001000,
        SEND_PACKET       = 6'b010000,
        SEND_FINISHED     = 6'b100000
    } send_fsm_t;
    send_fsm_t send_state;

    /* Signals below should have 1 bit more to hold 'size' and not just max value */
    logic [($clog2(HEADER_SIZE)):0]             out_header_idx;
    logic [($clog2(MAX_AUX_HEADER_SIZE+1)-1):0] aux_header_idx;
    logic [($clog2(MAX_AUX_HEADER_SIZE+1)-1):0] aux_header_size;

    typedef enum logic [9:0] {
        RECEIVE_IDLE         = 10'b0000000001,
        RECEIVE_HEADER       = 10'b0000000010,
        RECEIVE_PACKET       = 10'b0000000100,
        RECEIVE_SERVICE      = 10'b0000001000,
        RECEIVE_DELIVERY     = 10'b0000010000,
        RECEIVE_DROP         = 10'b0000100000,
        RECEIVE_WAIT_REQ     = 10'b0001000000,
        RECEIVE_WAIT_DLVR    = 10'b0010000000,
        RECEIVE_WAIT_ALLOC   = 10'b0100000000,
        RECEIVE_MAP_COMPLETE = 10'b1000000000 
    } receive_fsm_t;
    receive_fsm_t receive_state;

    /* verilator lint_off UNUSEDSIGNAL */
    logic [(HEADER_SIZE - 1):0]     [(FLIT_SIZE - 1):0] in_header;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [(MAX_PAYLOAD_SIZE - 1):0][(FLIT_SIZE - 1):0] in_payload;
    
////////////////////////////////////////////////////////////////////////////////
// Injector
////////////////////////////////////////////////////////////////////////////////

    logic [16:0] graph_size;
    logic [31:0] app_hash;
    logic [ 8:0] task_cnt;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            graph_size <= '0;
            task_cnt   <= '0;
        end
        else if (src_rx_i) begin
            case (inject_state)
                INJECTOR_IDLE:             graph_size <= src_data_i[16:0];
                INJECTOR_RECEIVE_APP_HASH: app_hash   <= src_data_i;
                INJECTOR_RECEIVE_TASK_CNT: task_cnt   <= src_data_i[8:0];
                default: ;
            endcase
        end
    end

    logic [7:0] current_task;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            current_task <= '0;
        else begin
            case (inject_state)
                INJECTOR_MAP:       current_task <= INJECT_MAPPER;
                INJECTOR_NEXT_TASK: current_task <= current_task + 1'b1;
                default: ;
            endcase
        end
    end

    inject_fsm_t inject_next_state;
    always_comb begin
        case (inject_state)
            INJECTOR_IDLE:
                inject_next_state = src_rx_i 
                    ? INJECTOR_RECEIVE_APP_HASH 
                    : src_eoa_i
                        ? INJECTOR_SEND_EOA
                        : INJECTOR_IDLE;
            INJECTOR_RECEIVE_APP_HASH:
                inject_next_state = src_rx_i 
                    ? INJECTOR_RECEIVE_TASK_CNT 
                    : INJECTOR_RECEIVE_APP_HASH;
            INJECTOR_RECEIVE_TASK_CNT:
                inject_next_state = src_rx_i 
                    ? INJECTOR_SEND_DESCRIPTOR 
                    : INJECTOR_RECEIVE_TASK_CNT;
            INJECTOR_SEND_DESCRIPTOR:
                inject_next_state = (send_state == SEND_FINISHED) 
                    ? INJECTOR_MAP 
                    : INJECTOR_SEND_DESCRIPTOR;
            INJECTOR_MAP:
                inject_next_state = !(receive_state == RECEIVE_WAIT_ALLOC) 
                    ? INJECTOR_MAP 
                    : (INJECT_MAPPER && task_cnt == 9'b1)
                        ? INJECTOR_WAIT_COMPLETE
                        : INJECTOR_RECEIVE_TXT_SZ;
            INJECTOR_RECEIVE_TXT_SZ:
                inject_next_state = src_rx_i 
                    ? INJECTOR_RECEIVE_DATA_SZ 
                    : INJECTOR_RECEIVE_TXT_SZ;
            INJECTOR_RECEIVE_DATA_SZ:
                inject_next_state = src_rx_i 
                    ? INJECTOR_RECEIVE_BSS_SZ 
                    : INJECTOR_RECEIVE_DATA_SZ;
            INJECTOR_RECEIVE_BSS_SZ:
                inject_next_state = src_rx_i 
                    ? INJECTOR_RECEIVE_ENTRY 
                    : INJECTOR_RECEIVE_BSS_SZ;
            INJECTOR_RECEIVE_ENTRY:
                inject_next_state = src_rx_i 
                    ? INJECTOR_SEND_TASK 
                    : INJECTOR_RECEIVE_ENTRY;
            INJECTOR_SEND_TASK:
                inject_next_state = !(send_state == SEND_FINISHED) 
                    ? INJECTOR_SEND_TASK
                    : (INJECT_MAPPER && task_cnt == '0)
                        ? INJECTOR_IDLE 
                        : INJECTOR_NEXT_TASK;
            INJECTOR_NEXT_TASK:
                inject_next_state = (current_task == 8'(task_cnt - 1'b1)) 
                    ? INJECTOR_WAIT_COMPLETE 
                    : INJECTOR_RECEIVE_TXT_SZ;
            INJECTOR_WAIT_COMPLETE:
                inject_next_state = (receive_state == RECEIVE_MAP_COMPLETE) 
                    ? INJECTOR_IDLE 
                    : INJECTOR_WAIT_COMPLETE;
            INJECTOR_SEND_EOA:
                inject_next_state = (send_state == SEND_FINISHED)
                    ? INJECTOR_FINISHED
                    : INJECTOR_SEND_EOA;
            INJECTOR_FINISHED:
                inject_next_state = INJECTOR_FINISHED;
            default:
                inject_next_state = INJECTOR_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            inject_state <= INJECT_MAPPER 
                ? INJECTOR_RECEIVE_TXT_SZ 
                : INJECTOR_IDLE;
        else
            inject_state <= inject_next_state;
    end

    always_comb begin
        if (send_state == SEND_PACKET) begin
            if (
                out_header_idx == HEADER_SIZE 
                && aux_header_idx == aux_header_size
            )
                src_credit_o = noc_credit_i;
            else
                src_credit_o = 1'b0;
        end
        else begin
            src_credit_o = (
                inject_state inside {
                    INJECTOR_IDLE,
                    INJECTOR_RECEIVE_APP_HASH, 
                    INJECTOR_RECEIVE_TXT_SZ, 
                    INJECTOR_RECEIVE_DATA_SZ, 
                    INJECTOR_RECEIVE_BSS_SZ, 
                    INJECTOR_RECEIVE_ENTRY
                }
            );
        end
    end

////////////////////////////////////////////////////////////////////////////////
// Send control
////////////////////////////////////////////////////////////////////////////////

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

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aux_header_idx <= '0;
        end
        else begin
            if (send_state inside {SEND_IDLE, SEND_WAIT_REQUEST})
                aux_header_idx  <= '0;
            else if (
                noc_credit_i 
                && out_header_idx == HEADER_SIZE 
                && aux_header_idx != aux_header_size
            )
                aux_header_idx  <= aux_header_idx + 1'b1;
        end
    end

    logic [(HEADER_SIZE - 1):0][(FLIT_SIZE - 1):0] out_header;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_header <= '0;
        end
        else begin
            if (receive_state == RECEIVE_WAIT_REQ) begin
                out_header    <= '0;
                out_header[0] <= in_header[8];       /* Target address   */
                out_header[1] <= HEADER_SIZE - 2;    /* Payload size     */
                out_header[2] <= MESSAGE_REQUEST;    /* Service          */
                out_header[3] <= in_header[3];       /* Producer task    */
                out_header[4] <= in_header[4];       /* Consumer task    */
                out_header[8] <= INJECTOR_ADDRESS;   /* Consumer address */
            end
            else begin
                case (inject_state) /* Priority to send without protocol to allocate task */
                    INJECTOR_RECEIVE_TXT_SZ: begin
                        out_header     <= '0;
                        out_header[0]  <= (INJECT_MAPPER && task_cnt == '0) /* Target address */
                            ? {16'b0, mapper_address_i}
                            : in_payload[current_task + 8'd2];
                        out_header[1]  <= src_data_i;                       /* Payload size   */
                        out_header[2]  <= TASK_ALLOCATION;                  /* Service        */
                        out_header[3]  <= (INJECT_MAPPER && task_cnt == '0) /* Task ID        */
                            ? '0
                            : {16'b0, in_payload[1][7:0], current_task[7:0]};
                        out_header[4]  <= (INJECT_MAPPER && task_cnt == '0) /* Mapper address */
                            ? '1
                            : {16'b0, mapper_address_i};
                        out_header[8]  <= (INJECT_MAPPER && task_cnt == '0) /* Mapper ID      */
                            ? '1
                            : '0;
                        out_header[10] <= src_data_i;                       /* Text size      */
                    end
                    INJECTOR_RECEIVE_DATA_SZ: begin
                        out_header[9] <= src_data_i; /* Data size */

                        if (src_rx_i)
                            out_header[1] <= out_header[1] + src_data_i;
                    end
                    INJECTOR_RECEIVE_BSS_SZ: begin
                        out_header[11] <= src_data_i; /* BSS size    */

                        if (src_rx_i) begin
                            /* Divide payload size by 4 */
                            out_header[1][(FLIT_SIZE - 3):0] <= 
                                out_header[1][(FLIT_SIZE - 1):2];
                            out_header[1][(FLIT_SIZE - 1):(FLIT_SIZE - 2)] <= 
                                '0;
                        end
                    end
                    INJECTOR_RECEIVE_ENTRY: begin
                        out_header[12] <= src_data_i; /* Entry point */

                        if (src_rx_i)
                            out_header[1] <= out_header[1] + (HEADER_SIZE - 2);
                    end
                    INJECTOR_SEND_DESCRIPTOR,
                    INJECTOR_SEND_EOA:          begin  /* Messages following the MPI protocol */
                        case (send_state)
                            SEND_IDLE: begin
                                /* DATA_AV to mapper task */
                                out_header    <= '0;
                                out_header[0] <= {16'b0, mapper_address_i}; /* Target address   */
                                out_header[1] <= HEADER_SIZE - 2;           /* Payload size     */
                                out_header[2] <= DATA_AV;                   /* Service          */
                                out_header[3] <= INJECTOR_ADDRESS;          /* Producer task    */
                                out_header[4] <= '0;                        /* Consumer task    */
                                out_header[8] <= INJECTOR_ADDRESS;          /* Producer address */
                            end
                            SEND_WAIT_REQUEST: begin
                                /* DELIVERY to mapper task */
                                out_header    <= '0;
                                out_header[0] <= in_header[8];      /* Target address */
                                out_header[2] <= MESSAGE_DELIVERY;  /* Service        */
                                out_header[3] <= in_header[3];      /* Producer task  */
                                out_header[4] <= in_header[4];      /* Consumer task  */

                                if (inject_state == INJECTOR_SEND_DESCRIPTOR) begin
                                    out_header[1] <= (                  /* Payload size            */
                                        {22'b0, task_cnt, 1'b0}         /* 2 flits per task        */
                                        + {15'b0, graph_size}           /* Graph size              */
                                        + (HEADER_SIZE + 2)             /* -2 + 3 (aux) + 1 (size) */
                                    );
                                    out_header[8] <= (
                                        {
                                            (
                                                {20'b0, task_cnt, 1'b0} 
                                                + {12'b0, graph_size}   /* Message length          */
                                                + 29'd4
                                            ), 
                                            2'b0
                                        }
                                    );
                                end
                                else if (inject_state == INJECTOR_SEND_EOA) begin
                                    out_header[1] <= (HEADER_SIZE - 1); /* Payload size   */
                                    out_header[8] <= 32'd4;             /* Message length */
                                end
                            end
                            default: ;
                        endcase
                    end
                    default: ;
                endcase
            end
        end
    end

    logic [(FLIT_SIZE - 1):0] out_sent_cnt;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_sent_cnt <= '0;
        end
        else begin
            if (send_state inside {SEND_IDLE, SEND_WAIT_REQUEST})
                out_sent_cnt <= '0;
            else if (noc_credit_i)
                out_sent_cnt <= out_sent_cnt + 1'b1;
        end
    end

    logic sent;
    assign sent      = noc_credit_i && (out_sent_cnt == out_header[1] + 1'b1);
    assign noc_eop_o = sent;

    send_fsm_t send_next_state;
    always_comb begin
        case (send_state)
            SEND_IDLE: begin
                if (receive_state == RECEIVE_WAIT_REQ) begin
                    send_next_state = SEND_REQUEST;
                end
                else begin
                    case (inject_state)
                        INJECTOR_SEND_DESCRIPTOR,
                        INJECTOR_SEND_EOA: 
                            send_next_state = SEND_DATA_AV;
                        INJECTOR_SEND_TASK:
                            send_next_state = SEND_PACKET;
                        default: 
                            send_next_state = SEND_IDLE;
                    endcase
                end
            end
            SEND_DATA_AV:
                send_next_state = sent ? SEND_WAIT_REQUEST : SEND_DATA_AV;
            SEND_REQUEST:
                send_next_state = sent ? SEND_FINISHED : SEND_REQUEST;
            SEND_WAIT_REQUEST: 
                send_next_state = (receive_state == RECEIVE_WAIT_DLVR) 
                    ? SEND_PACKET 
                    : SEND_WAIT_REQUEST;
            SEND_PACKET:
                send_next_state = sent ? SEND_FINISHED : SEND_PACKET;
            SEND_FINISHED:
                send_next_state = SEND_IDLE;
            default:
                send_next_state = SEND_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            send_state <= SEND_IDLE;
        else
            send_state <= send_next_state;
    end
    
    logic [(MAX_AUX_HEADER_SIZE - 1):0][(FLIT_SIZE - 1):0] aux_header;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aux_header      <= '0;
            aux_header_size <= '0;
        end
        else begin
            case (inject_state)
                INJECTOR_SEND_DESCRIPTOR: begin
                    if (send_state == SEND_WAIT_REQUEST) begin
                        aux_header_size <= 2'd3;
                        aux_header      <= '0;
                        aux_header[0]   <= NEW_APP;
                        aux_header[1]   <= INJECTOR_ADDRESS;
                        aux_header[2]   <= app_hash;
                    end
                end
                INJECTOR_SEND_EOA: begin
                    if (send_state == SEND_WAIT_REQUEST) begin
                        aux_header_size <= 2'd1;
                        aux_header      <= '0;
                        aux_header[0]   <= REQUEST_FINISH;
                    end
                end
                default: aux_header_size <= '0;
            endcase
        end
    end

    always_comb begin
        if (send_state == SEND_PACKET) begin
            if (
                out_header_idx == HEADER_SIZE 
                && aux_header_idx == aux_header_size
            )
                noc_tx_o = src_rx_i;
            else
                noc_tx_o = 1'b1;
        end
        else begin
            noc_tx_o = send_state inside {SEND_DATA_AV, SEND_REQUEST};
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

////////////////////////////////////////////////////////////////////////////////
// Receive control
////////////////////////////////////////////////////////////////////////////////

    logic [($clog2(HEADER_SIZE)):0] in_header_idx;
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

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            in_payload <= '0;
        end
        else begin
            if (noc_rx_i && noc_credit_o && in_header_idx == HEADER_SIZE)
                in_payload[in_payload_idx] <= noc_data_i;
        end
    end

    receive_fsm_t receive_next_state;
    always_comb begin
        case (receive_state)
            RECEIVE_IDLE: begin
                if (send_state == SEND_WAIT_REQUEST) begin
                    receive_next_state = RECEIVE_HEADER;
                end
                else begin
                    case (inject_state)
                        INJECTOR_MAP,
                        INJECTOR_WAIT_COMPLETE:
                            receive_next_state = RECEIVE_HEADER;
                        default:
                            receive_next_state = RECEIVE_IDLE;
                    endcase
                end
            end
            RECEIVE_HEADER:
                receive_next_state = noc_rx_i ? RECEIVE_PACKET : RECEIVE_HEADER;
            RECEIVE_PACKET: begin
                if (noc_rx_i) begin
                    if (noc_eop_i)
                        receive_next_state = RECEIVE_SERVICE;
                    else if (in_payload_idx == MAX_PAYLOAD_SIZE - 1)
                        receive_next_state = RECEIVE_DROP;
                    else
                        receive_next_state = RECEIVE_PACKET;
                end
                else begin
                    receive_next_state = RECEIVE_PACKET;
                end
            end
            RECEIVE_SERVICE: begin
                case (in_header[2])
                    DATA_AV:          receive_next_state = RECEIVE_WAIT_REQ;
                    MESSAGE_REQUEST:  receive_next_state = RECEIVE_WAIT_DLVR;
                    MESSAGE_DELIVERY: receive_next_state = RECEIVE_DELIVERY;
                    default:          receive_next_state = RECEIVE_IDLE;      /* Ignore */
                endcase
            end
            RECEIVE_DELIVERY: begin
                case (in_payload[0])
                    APP_ALLOCATION_REQUEST: 
                        receive_next_state = RECEIVE_WAIT_ALLOC;
                    APP_MAPPING_COMPLETE:
                        receive_next_state = RECEIVE_MAP_COMPLETE;
                    default:
                        receive_next_state = RECEIVE_IDLE;         /* Ignore */
                endcase
            end
            RECEIVE_DROP:
                receive_next_state = (noc_eop_i) 
                    ? RECEIVE_IDLE 
                    : RECEIVE_DROP;
            RECEIVE_WAIT_REQ:
                receive_next_state = (send_state == SEND_FINISHED) 
                    ? RECEIVE_IDLE 
                    : RECEIVE_WAIT_REQ;
            RECEIVE_WAIT_DLVR:
                receive_next_state = (send_state == SEND_FINISHED)
                    ? RECEIVE_IDLE 
                    : RECEIVE_WAIT_DLVR;
            RECEIVE_WAIT_ALLOC:
                receive_next_state = (inject_state == INJECTOR_WAIT_COMPLETE) 
                    ? RECEIVE_IDLE 
                    : RECEIVE_WAIT_ALLOC;
            RECEIVE_MAP_COMPLETE: 
                receive_next_state = RECEIVE_IDLE;
            default:
                receive_next_state = RECEIVE_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            receive_state <= RECEIVE_IDLE;
        else
            receive_state <= receive_next_state;
    end

    assign noc_credit_o = (
        receive_state inside {
            RECEIVE_HEADER, 
            RECEIVE_PACKET, 
            RECEIVE_DROP
        }
    );

endmodule
