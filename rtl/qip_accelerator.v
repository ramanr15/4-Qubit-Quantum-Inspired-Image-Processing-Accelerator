// =====================================================================
// FINAL SOURCE
// Configurable 4-Qubit Quantum-Inspired Image Processing Accelerator
// File: qip_accelerator.v
// Verilog-2001 | Xilinx Vivado 2025.2
// =====================================================================
`timescale 1ns / 1ps
module qip_accelerator #(
    parameter WIDTH = 16,
    parameter FRAC  = 12
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [7:0]  pix0,
    input  wire [7:0]  pix1,
    input  wire [7:0]  pix2,
    input  wire [7:0]  pix3,

    input  wire [1:0]  mode,

    output reg         busy,
    output reg         done,
    output reg [7:0]   result_pixel
);

    // ================================================================
    // Q4.12 constants
    // ================================================================

    localparam signed [WIDTH-1:0] INV_SQRT2 = 16'sd2896;
    localparam signed [WIDTH-1:0] COS_22     = 16'sd3784;
    localparam signed [WIDTH-1:0] SIN_22     = 16'sd1567;
    localparam signed [WIDTH-1:0] COS_11     = 16'sd4017;
    localparam signed [WIDTH-1:0] SIN_11     = 16'sd799;

    // ================================================================
    // FSM
    // ================================================================

    localparam S_IDLE       = 4'd0,
               S_INIT       = 4'd1,
               S_GATE1      = 4'd2,
               S_GATE2      = 4'd3,
               S_GATE3      = 4'd4,
               S_CNOT       = 4'd5,
               S_MEAS_INIT  = 4'd6,
               S_MEAS_RUN   = 4'd7,
               S_SCALE      = 4'd8,
               S_OUTPUT     = 4'd9,
               S_DONE       = 4'd10;

    reg [3:0] state;
    reg [3:0] next_state;

    // ================================================================
    // 4-qubit state vector: 16 real fixed-point amplitudes
    // Internal only - no 256-bit external I/O
    // ================================================================

    reg signed [WIDTH-1:0] amp      [0:15];
    reg signed [WIDTH-1:0] amp_next [0:15];

    integer i;
    integer j;

    // ================================================================
    // Latched inputs
    // ================================================================

    reg [7:0] p0_r;
    reg [7:0] p1_r;
    reg [7:0] p2_r;
    reg [7:0] p3_r;
    reg [1:0] mode_r;

    // ================================================================
    // Multi-cycle measurement registers
    // ================================================================

    reg [4:0]  meas_index;

    reg [63:0] total_energy;
    reg [63:0] selected_energy;
    reg [63:0] auxiliary_energy;

    reg signed [(2*WIDTH)-1:0] square_value;

    reg [63:0] scaled_value;
    reg [7:0]  measured_value;

    // ================================================================
    // Fixed-point multiply
    // ================================================================

    function signed [WIDTH-1:0] fp_mult;

        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;

        reg signed [(2*WIDTH)-1:0] product;

        begin
            product = a * b;
            fp_mult = product >>> FRAC;
        end

    endfunction

    // ================================================================
    // FSM state register
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst)
            state <= S_IDLE;
        else
            state <= next_state;

    end

    // ================================================================
    // FSM next-state logic
    // ================================================================

    always @(*) begin

        case (state)

            S_IDLE:
                next_state = start ? S_INIT : S_IDLE;

            S_INIT:
                next_state = S_GATE1;

            S_GATE1:
                next_state = S_GATE2;

            S_GATE2:
                next_state = S_GATE3;

            S_GATE3:
                next_state = S_CNOT;

            S_CNOT:
                next_state = S_MEAS_INIT;

            S_MEAS_INIT:
                next_state = S_MEAS_RUN;

            S_MEAS_RUN:
                next_state =
                    (meas_index == 5'd15) ? S_SCALE : S_MEAS_RUN;

            S_SCALE:
                next_state = S_OUTPUT;

            S_OUTPUT:
                next_state = S_DONE;

            S_DONE:
                next_state = S_IDLE;

            default:
                next_state = S_IDLE;

        endcase

    end

    // ================================================================
    // Busy and done
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
        end
        else begin

            done <= 1'b0;

            case (state)

                S_IDLE:
                    busy <= start;

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end

                default:
                    busy <= 1'b1;

            endcase

        end

    end

    // ================================================================
    // Latch inputs
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            p0_r   <= 8'd0;
            p1_r   <= 8'd0;
            p2_r   <= 8'd0;
            p3_r   <= 8'd0;
            mode_r <= 2'b00;

        end
        else if ((state == S_IDLE) && start) begin

            p0_r   <= pix0;
            p1_r   <= pix1;
            p2_r   <= pix2;
            p3_r   <= pix3;
            mode_r <= mode;

        end

    end

    // ================================================================
    // Quantum-inspired combinational gate processing
    // ================================================================

    always @(*) begin

        for (i = 0; i < 16; i = i + 1)
            amp_next[i] = amp[i];

        case (state)

            // --------------------------------------------------------
            // Encode four pixels into the first four amplitudes
            //
            // 8-bit pixel << 4 gives a bounded Q4.12 representation:
            // 255 -> 4080, close to 1.0 in Q4.12.
            // --------------------------------------------------------

            S_INIT: begin

                for (i = 0; i < 16; i = i + 1)
                    amp_next[i] = {WIDTH{1'b0}};

                amp_next[0] = $signed({4'b0000, p0_r, 4'b0000});
                amp_next[1] = $signed({4'b0000, p1_r, 4'b0000});
                amp_next[2] = $signed({4'b0000, p2_r, 4'b0000});
                amp_next[3] = $signed({4'b0000, p3_r, 4'b0000});

            end

            // --------------------------------------------------------
            // GATE 1
            // --------------------------------------------------------

            S_GATE1: begin

                case (mode_r)

                    // EDGE:
                    // q0 Hadamard-like difference extraction
                    2'b00: begin

                        for (i = 0; i < 8; i = i + 1) begin

                            amp_next[2*i] =
                                fp_mult(
                                    amp[2*i] + amp[2*i+1],
                                    INV_SQRT2
                                );

                            amp_next[2*i+1] =
                                fp_mult(
                                    amp[2*i] - amp[2*i+1],
                                    INV_SQRT2
                                );

                        end

                    end

                    // SHARPEN:
                    // Signed local rotation
                    2'b01: begin

                        for (i = 0; i < 8; i = i + 1) begin

                            amp_next[2*i] =
                                fp_mult(amp[2*i], COS_22)
                                +
                                fp_mult(amp[2*i+1], SIN_22);

                            amp_next[2*i+1] =
                                -fp_mult(amp[2*i], SIN_22)
                                +
                                fp_mult(amp[2*i+1], COS_22);

                        end

                    end

                    // SMOOTH:
                    // q0 average/difference separation
                    2'b10: begin

                        for (i = 0; i < 8; i = i + 1) begin

                            amp_next[2*i] =
                                fp_mult(
                                    amp[2*i] + amp[2*i+1],
                                    INV_SQRT2
                                );

                            amp_next[2*i+1] =
                                fp_mult(
                                    amp[2*i] - amp[2*i+1],
                                    INV_SQRT2
                                );

                        end

                    end

                    // FEATURE:
                    // 45-degree mixing
                    2'b11: begin

                        for (i = 0; i < 8; i = i + 1) begin

                            amp_next[2*i] =
                                fp_mult(amp[2*i], INV_SQRT2)
                                -
                                fp_mult(amp[2*i+1], INV_SQRT2);

                            amp_next[2*i+1] =
                                fp_mult(amp[2*i], INV_SQRT2)
                                +
                                fp_mult(amp[2*i+1], INV_SQRT2);

                        end

                    end

                    default: begin
                    end

                endcase

            end

            // --------------------------------------------------------
            // GATE 2
            // --------------------------------------------------------

            S_GATE2: begin

                case (mode_r)

                    // EDGE:
                    // q1 Hadamard-like vertical difference extraction
                    2'b00: begin

                        for (j = 0; j < 4; j = j + 1) begin

                            amp_next[4*j] =
                                fp_mult(
                                    amp[4*j] + amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+2] =
                                fp_mult(
                                    amp[4*j] - amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+1] =
                                fp_mult(
                                    amp[4*j+1] + amp[4*j+3],
                                    INV_SQRT2
                                );

                            amp_next[4*j+3] =
                                fp_mult(
                                    amp[4*j+1] - amp[4*j+3],
                                    INV_SQRT2
                                );

                        end

                    end

                    // SHARPEN:
                    // q1 difference extraction
                    2'b01: begin

                        for (j = 0; j < 4; j = j + 1) begin

                            amp_next[4*j] =
                                fp_mult(
                                    amp[4*j] + amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+2] =
                                fp_mult(
                                    amp[4*j] - amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+1] =
                                fp_mult(
                                    amp[4*j+1] + amp[4*j+3],
                                    INV_SQRT2
                                );

                            amp_next[4*j+3] =
                                fp_mult(
                                    amp[4*j+1] - amp[4*j+3],
                                    INV_SQRT2
                                );

                        end

                    end

                    // SMOOTH:
                    // Small neighboring rotation
                    2'b10: begin

                        for (i = 0; i < 8; i = i + 1) begin

                            amp_next[2*i] =
                                fp_mult(amp[2*i], COS_11)
                                -
                                fp_mult(amp[2*i+1], SIN_11);

                            amp_next[2*i+1] =
                                fp_mult(amp[2*i], SIN_11)
                                +
                                fp_mult(amp[2*i+1], COS_11);

                        end

                    end

                    // FEATURE:
                    // q1 Hadamard-like mixing
                    2'b11: begin

                        for (j = 0; j < 4; j = j + 1) begin

                            amp_next[4*j] =
                                fp_mult(
                                    amp[4*j] + amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+2] =
                                fp_mult(
                                    amp[4*j] - amp[4*j+2],
                                    INV_SQRT2
                                );

                            amp_next[4*j+1] =
                                fp_mult(
                                    amp[4*j+1] + amp[4*j+3],
                                    INV_SQRT2
                                );

                            amp_next[4*j+3] =
                                fp_mult(
                                    amp[4*j+1] - amp[4*j+3],
                                    INV_SQRT2
                                );

                        end

                    end

                    default: begin
                    end

                endcase

            end

            // --------------------------------------------------------
            // GATE 3
            // --------------------------------------------------------

            S_GATE3: begin

                case (mode_r)

                    // EDGE:
                    // q2 rotation
                    2'b00: begin

                        for (j = 0; j < 2; j = j + 1) begin
                            for (i = 0; i < 4; i = i + 1) begin

                                amp_next[8*j+i] =
                                    fp_mult(
                                        amp[8*j+i],
                                        COS_22
                                    )
                                    -
                                    fp_mult(
                                        amp[8*j+i+4],
                                        SIN_22
                                    );

                                amp_next[8*j+i+4] =
                                    fp_mult(
                                        amp[8*j+i],
                                        SIN_22
                                    )
                                    +
                                    fp_mult(
                                        amp[8*j+i+4],
                                        COS_22
                                    );

                            end
                        end

                    end

                    // SHARPEN:
                    // Strong q2 feature mixing
                    2'b01: begin

                        for (j = 0; j < 2; j = j + 1) begin
                            for (i = 0; i < 4; i = i + 1) begin

                                amp_next[8*j+i] =
                                    fp_mult(
                                        amp[8*j+i],
                                        INV_SQRT2
                                    )
                                    -
                                    fp_mult(
                                        amp[8*j+i+4],
                                        INV_SQRT2
                                    );

                                amp_next[8*j+i+4] =
                                    fp_mult(
                                        amp[8*j+i],
                                        INV_SQRT2
                                    )
                                    +
                                    fp_mult(
                                        amp[8*j+i+4],
                                        INV_SQRT2
                                    );

                            end
                        end

                    end

                    // SMOOTH:
                    // Attenuate high-frequency odd channels
                    2'b10: begin

                        for (i = 1; i < 16; i = i + 2)
                            amp_next[i] = amp[i] >>> 1;

                    end

                    // FEATURE:
                    // q2 Hadamard-like mixing
                    2'b11: begin

                        for (j = 0; j < 2; j = j + 1) begin
                            for (i = 0; i < 4; i = i + 1) begin

                                amp_next[8*j+i] =
                                    fp_mult(
                                        amp[8*j+i]
                                        +
                                        amp[8*j+i+4],
                                        INV_SQRT2
                                    );

                                amp_next[8*j+i+4] =
                                    fp_mult(
                                        amp[8*j+i]
                                        -
                                        amp[8*j+i+4],
                                        INV_SQRT2
                                    );

                            end
                        end

                    end

                    default: begin
                    end

                endcase

            end

            // --------------------------------------------------------
            // Correct basis-index CNOT permutations
            // --------------------------------------------------------

            S_CNOT: begin

                case (mode_r)

                    // q1 control -> q0 target
                    2'b00: begin

                        for (i = 0; i < 16; i = i + 1) begin

                            if (((i & 2) != 0) &&
                                ((i & 1) == 0)) begin

                                amp_next[i]   = amp[i+1];
                                amp_next[i+1] = amp[i];

                            end

                        end

                    end

                    // q2 control -> q0 target
                    2'b01: begin

                        for (i = 0; i < 16; i = i + 1) begin

                            if (((i & 4) != 0) &&
                                ((i & 1) == 0)) begin

                                amp_next[i]   = amp[i+1];
                                amp_next[i+1] = amp[i];

                            end

                        end

                    end

                    // q2 control -> q1 target
                    2'b10: begin

                        for (i = 0; i < 16; i = i + 1) begin

                            if (((i & 4) != 0) &&
                                ((i & 2) == 0)) begin

                                amp_next[i]   = amp[i+2];
                                amp_next[i+2] = amp[i];

                            end

                        end

                    end

                    // q3 control -> q0 target
                    2'b11: begin

                        for (i = 0; i < 16; i = i + 1) begin

                            if (((i & 8) != 0) &&
                                ((i & 1) == 0)) begin

                                amp_next[i]   = amp[i+1];
                                amp_next[i+1] = amp[i];

                            end

                        end

                    end

                    default: begin
                    end

                endcase

            end

            default: begin
            end

        endcase

    end

    // ================================================================
    // Single sequential amplitude driver
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            for (i = 0; i < 16; i = i + 1)
                amp[i] <= {WIDTH{1'b0}};

        end
        else begin

            case (state)

                S_INIT,
                S_GATE1,
                S_GATE2,
                S_GATE3,
                S_CNOT: begin

                    for (i = 0; i < 16; i = i + 1)
                        amp[i] <= amp_next[i];

                end

                default: begin
                    // Hold amplitudes
                end

            endcase

        end

    end

    // ================================================================
    // Multi-cycle measurement
    //
    // One amplitude is squared per clock cycle.
    // This replaces 16 parallel squares + huge combinational division.
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            meas_index       <= 5'd0;
            total_energy     <= 64'd0;
            selected_energy  <= 64'd0;
            auxiliary_energy <= 64'd0;
            square_value     <= 0;

        end
        else if (state == S_MEAS_INIT) begin

            meas_index       <= 5'd0;
            total_energy     <= 64'd0;
            selected_energy  <= 64'd0;
            auxiliary_energy <= 64'd0;
            square_value     <= 0;

        end
        else if (state == S_MEAS_RUN) begin

            // Full-width signed square is always non-negative
            square_value = amp[meas_index] * amp[meas_index];

            total_energy <=
                total_energy + $unsigned(square_value);

            case (mode_r)

                // EDGE:
                // Energy in difference-sensitive channels
                2'b00: begin

                    if ((meas_index[1:0]) != 2'b00)
                        selected_energy <=
                            selected_energy
                            +
                            $unsigned(square_value);

                end

                // SHARPEN:
                // Separate high-frequency and low-frequency energies
                2'b01: begin

                    if ((meas_index[1:0]) != 2'b00)
                        selected_energy <=
                            selected_energy
                            +
                            $unsigned(square_value);
                    else
                        auxiliary_energy <=
                            auxiliary_energy
                            +
                            $unsigned(square_value);

                end

                // SMOOTH:
                // Energy in low-frequency/even channels
                2'b10: begin

                    if (meas_index[0] == 1'b0)
                        selected_energy <=
                            selected_energy
                            +
                            $unsigned(square_value);

                end

                // FEATURE:
                // Weighted basis-state energy
                2'b11: begin

                    selected_energy <=
                        selected_energy
                        +
                        ($unsigned(square_value)
                         * meas_index);

                end

                default: begin
                end

            endcase

            if (meas_index < 5'd15)
                meas_index <= meas_index + 5'd1;

        end

    end

    // ================================================================
    // Divider-free output scaling
    //
    // Uses shifts and saturation only.
    // No variable hardware division.
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            scaled_value   <= 64'd0;
            measured_value <= 8'd0;

        end
        else if (state == S_SCALE) begin

            case (mode_r)

                // ----------------------------------------------------
                // EDGE
                // Difference-channel energy scaling
                // ----------------------------------------------------

                2'b00: begin

                    scaled_value =
                        selected_energy >> 20;

                    if (scaled_value > 64'd255)
                        measured_value <= 8'd255;
                    else
                        measured_value <=
                            scaled_value[7:0];

                end

                // ----------------------------------------------------
                // SHARPEN
                //
                // High-frequency energy plus a smaller low-frequency
                // contribution. This is input-sensitive and replaces
                // the previous constant/saturated 190 behavior.
                // ----------------------------------------------------

                2'b01: begin

                    scaled_value =
                        (selected_energy >> 20)
                        +
                        (auxiliary_energy >> 22);

                    if (scaled_value > 64'd255)
                        measured_value <= 8'd255;
                    else
                        measured_value <=
                            scaled_value[7:0];

                end

                // ----------------------------------------------------
                // SMOOTH
                // Low-frequency channel energy
                // ----------------------------------------------------

                2'b10: begin

                    scaled_value =
                        selected_energy >> 21;

                    if (scaled_value > 64'd255)
                        measured_value <= 8'd255;
                    else
                        measured_value <=
                            scaled_value[7:0];

                end

                // ----------------------------------------------------
                // FEATURE
                // Weighted state-energy signature
                // ----------------------------------------------------

                2'b11: begin

                    scaled_value =
                        selected_energy >> 23;

                    if (scaled_value > 64'd255)
                        measured_value <= 8'd255;
                    else
                        measured_value <=
                            scaled_value[7:0];

                end

                default:
                    measured_value <= 8'd0;

            endcase

        end

    end

    // ================================================================
    // Final output
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst)
            result_pixel <= 8'd0;

        else if (state == S_OUTPUT)
            result_pixel <= measured_value;

    end

endmodule
