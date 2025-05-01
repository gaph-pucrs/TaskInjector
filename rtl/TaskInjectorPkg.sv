/**
 * TaskInjector
 * @file TaskInjectorPkg.sv
 *
 * @author Angelo Elias Dal Zotto (angelo.dalzotto@edu.pucrs.br)
 * GAPH - Hardware Design Support Group (https://corfu.pucrs.br)
 * PUCRS - Pontifical Catholic University of Rio Grande do Sul (http://pucrs.br/)
 *
 * @date November 2023
 *
 * @brief Task Injector package
 */

`ifndef TASK_INJECTOR_PKG
`define TASK_INJECTOR_PKG

package TaskInjectorPkg;

    parameter HEADER_SIZE = 13;

    /* Services inside MESSAGE_DELIVERY */
    parameter logic [31:0] NEW_APP                = 32'h00000000;
    parameter logic [31:0] APP_ALLOCATION_REQUEST = 32'h00000001;
    parameter logic [31:0] APP_MAPPING_COMPLETE   = 32'h00000002;
    parameter logic [31:0] TASK_TERMINATED        = 32'h00000005;
    parameter logic [31:0] REQUEST_FINISH         = 32'h0000000B;

    /* "Raw" services */
    parameter logic [31:0] DATA_AV                = 32'h00000040;
    parameter logic [31:0] MESSAGE_REQUEST        = 32'h00000041;
    parameter logic [31:0] TASK_ALLOCATION        = 32'h00000042;
    parameter logic [31:0] MESSAGE_DELIVERY       = 32'h00000043;
    parameter logic [31:0] MIGRATION_DATA_BSS     = 32'h00000045;

endpackage

`endif
