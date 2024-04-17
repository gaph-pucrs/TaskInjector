`ifndef TASK_INJECTOR_PKG
`define TASK_INJECTOR_PKG

package TaskInjectorPkg;

    parameter HEADER_SIZE = 13;

    parameter logic [31:0] MESSAGE_REQUEST        = 32'h00000000;
    parameter logic [31:0] MESSAGE_DELIVERY       = 32'h00000001;
    parameter logic [31:0] NEW_APP                = 32'h00000010;
    parameter logic [31:0] APP_ALLOCATION_REQUEST = 32'h00000026;
    parameter logic [31:0] DATA_AV                = 32'h00000031;
    parameter logic [31:0] APP_MAPPING_COMPLETE   = 32'h00000034;
    parameter logic [31:0] TASK_ALLOCATION        = 32'h00000040;

endpackage

`endif
