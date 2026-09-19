/*
 * Copyright (c) 2024-2026 Your Name / Snake Game Adaptation
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

    // VGA timing generation module
    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(~rst_n),
        .mode(ui_in[7:6]), // Mode selector from input switches
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // Grid coordinates (Scaling VGA pixels down into blocks)
    wire [5:0] grid_x = hpos[9:4]; 
    wire [5:0] grid_y = vpos[9:4];

    // Snake and Food state tracking registers
    reg [5:0] snake_x;
    reg [5:0] snake_y;
    reg [5:0] food_x;
    reg [5:0] food_y;

    // Counter to control game speed tick rates
    reg [23:0] move_counter;

    // Palette color wires
    wire [5:0] bg_color;
    wire [5:0] snake_color;
    wire [5:0] food_color;

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

    // Game logic for snake positioning and user input controls
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            snake_x      <= 6'd20;
            snake_y      <= 6'd15;
            food_x       <= 6'd10;
            food_y       <= 6'd10;
            move_counter <= 0;
        end else begin
            move_counter <= move_counter + 1;
            
            // Slow down movement ticks so the snake is playable
            if (move_counter == 24'd5000000) begin
                move_counter <= 0;
                
                // Direction inputs using lower bits of ui_in (Up, Down, Left, Right)
                case (ui_in[3:0])
                    4'b0001: snake_y <= snake_y - 1'b1; // Up
                    4'b0010: snake_y <= snake_y + 1'b1; // Down
                    4'b0100: snake_x <= snake_x - 1'b1; // Left
                    4'b1000: snake_x <= snake_x + 1'b1; // Right
                    default: snake_x <= snake_x + 1'b1; // Auto-move right by default
                endcase

                // Simple food collision check and repositioning logic
                if ((snake_x == food_x) && (snake_y == food_y)) begin
                    food_x <= (move_counter[7:2] % 6'd38) + 2'd2;
                    food_y <= (move_counter[13:8] % 6'd28) + 2'd2;
                end
            end
        end
    end

    // Rendering checks for objects on the active grid
    wire is_snake = (grid_x == snake_x) && (grid_y == snake_y);
    wire is_food  = (grid_x == food_x) && (grid_y == food_y);

    // Multiplex final pixel colors sent to the VGA connector
    wire [5:0] RGB = display_on ? (is_snake ? snake_color : (is_food ? food_color : bg_color)) : 6'd0;

endmodule
