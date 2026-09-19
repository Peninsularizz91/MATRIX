/*
 * Copyright (c) 2024-2026 CJ TORRES / Continuous Snake Game with Score Display
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_glyph_mode (
    input  wire [7:0] ui_in,    // Dedicated inputs (Direction controls: Up, Down, Left, Right)
    output wire [7:0] uo_out,   // Dedicated outputs (VGA Pmod signals)
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // always 1 when powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // VGA signals
    wire hsync, vsync, display_on;
    wire [10:0] hpos;
    wire [9:0] vpos;

    // TinyVGA PMOD color mapping layout
    assign uo_out = {hsync, RGB[0], RGB[2], RGB[4], vsync, RGB[1], RGB[3], RGB[5]};

    assign uio_out = 0;
    assign uio_oe  = 0;

    // Suppress unused signals warning
    wire _unused_ok = &{ena, uio_in, ui_in[7:4]};

    // VGA timing generation module[cite: 2]
    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(~rst_n),
        .mode(ui_in[7:6]), 
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // Grid coordinates (Scaling VGA pixels down into 16x16 blocks)
    wire [5:0] grid_x = hpos[9:4]; 
    wire [5:0] grid_y = vpos[9:4];

    // 3-Square Snake Registers (Head + 2 Body Segments)
    reg [5:0] head_x, head_y;
    reg [5:0] seg1_x, seg1_y;
    reg [5:0] seg2_x, seg2_y;

    // Food and Score registers
    reg [5:0] food_x;
    reg [5:0] food_y;
    reg [3:0] score; // Score from 0 to 9

    // Counter to control game speed tick rates
    reg [23:0] move_counter;

    // Palette color wires[cite: 1]
    wire [5:0] bg_color;
    wire [5:0] snake_color;
    wire [5:0] food_color;
    wire [5:0] text_color;

    // Palette ROM instances mapping to purple/violet theme[cite: 1]
    palette_rom bg_rom(
        .cid(3'd0), // Black background
        .pid(2'd2), 
        .color(bg_color)
    );

    palette_rom snake_rom(
        .cid(3'd3), // Vibrant purple for the snake
        .pid(2'd2), 
        .color(snake_color)
    );

    palette_rom food_rom(
        .cid(3'd5), // Lighter purple for food/apple
        .pid(2'd2), 
        .color(food_color)
    );

    palette_rom text_rom(
        .cid(3'd6), // Bright white-purple for score display
        .pid(2'd2), 
        .color(text_color)
    );

    // Game logic for continuous wrapping movement and score updates
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            head_x       <= 6'd20;
            head_y       <= 6'd15;
            seg1_x       <= 6'd19;
            seg1_y       <= 6'd15;
            seg2_x       <= 6'd18;
            seg2_y       <= 6'd15;
            food_x       <= 6'd10;
            food_y       <= 6'd10;
            score        <= 4'd0;
            move_counter <= 0;
        end else begin
            move_counter <= move_counter + 1;
            
            // Movement tick update speed
            if (move_counter == 24'd2500000) begin
                move_counter <= 0;
                
                // Shift body segments forward
                seg2_x <= seg1_x; 
                seg2_y <= seg1_y;
                seg1_x <= head_x; 
                seg1_y <= head_y;

                // Direction inputs with screen wrapping (no death upon hitting borders)
                case (ui_in[3:0])
                    4'b0001: head_y <= (head_y == 0) ? 6'd29 : head_y - 1'b1; // Up
                    4'b0010: head_y <= (head_y == 29) ? 6'd0 : head_y + 1'b1; // Down
                    4'b0100: head_x <= (head_x == 0) ? 6'd39 : head_x - 1'b1; // Left
                    4'b1000: head_x <= (head_x == 39) ? 6'd0 : head_x + 1'b1; // Right
                    default: head_x <= (head_x == 39) ? 6'd0 : head_x + 1'b1; // Auto-move right
                endcase

                // Food collision check: Eat food, increase score (max 9), and reposition food
                if ((head_x == food_x) && (head_y == food_y)) begin
                    if (score < 4'd9) score <= score + 1'b1;
                    food_x <= (move_counter[7:2] % 6'd36) + 6'd2;
                    food_y <= (move_counter[13:8] % 6'd26) + 6'd2;
                end
            end
        end
    end

    // --- Score Display via glyphs_rom ---
    // Position score at the upper left (Column 2, Row 1)
    wire [5:0] xb = hpos[10:3];
    wire [5:0] yb = vpos[5:0];
    wire is_score_area = (xb >= 6'd2 && xb <= 6'd3) && (yb >= 6'd2 && yb <= 6'd3);
    
    wire [3:0] glyph_y = vpos[3:0];
    wire [2:0] glyph_x = hpos[2:0];
    wire [5:0] glyph_char = (xb == 6'd2) ? 6'd28 : (6'd36 + {2'b00, score}); // Displays "S:" or numerical score mapping
    
    wire score_pixel;
    glyphs_rom score_glyph(
        .c(glyph_char),
        .y(glyph_y),
        .x(glyph_x),
        .pixel(score_pixel)
    );

    // Check if current grid matches any part of the 3-square snake
    wire is_snake = (grid_x == head_x && grid_y == head_y) || 
                    (grid_x == seg1_x && grid_y == seg1_y) || 
                    (grid_x == seg2_x && grid_y == seg2_y);

    // Check if current grid matches the food block
    wire is_food  = (grid_x == food_x) && (grid_y == food_y);

    // Multiplex final pixel colors sent to the VGA connector
    wire [5:0] RGB = display_on ? (is_score_area && score_pixel ? text_color : (is_snake ? snake_color : (is_food ? food_color : bg_color))) : 6'd0;

endmodule
