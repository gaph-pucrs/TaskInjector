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

    /* Services inside MESSAGE_DELIVERY */
    parameter logic [7:0] NEW_APP                = 8'h00;
    parameter logic [7:0] APP_ALLOCATION_REQUEST = 8'h01;
    parameter logic [7:0] APP_MAPPING_COMPLETE   = 8'h02;
    parameter logic [7:0] TASK_TERMINATED        = 8'h06;
    parameter logic [7:0] REQUEST_FINISH         = 8'h10;

    /* "Raw" services */
    parameter logic [7:0] DATA_AV          = 8'h40;
    parameter logic [7:0] MESSAGE_REQUEST  = 8'h41;
    parameter logic [7:0] TASK_ALLOCATION  = 8'h42;
    parameter logic [7:0] MESSAGE_DELIVERY = 8'h43;
    parameter logic [7:0] MIGRATION_DATA   = 8'h51;

endpackage

`endif
