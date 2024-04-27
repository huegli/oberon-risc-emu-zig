const std = @import("std");
const SDL = @import("sdl2");
const target_os = @import("builtin").os;

const FPS = 60;

pub fn main() !void {
    const fullscreen = false;
    var zoom: f32 = 0.0;

    const risc_rect = SDL.SDL_Rect{
        .x = 0,
        .y = 0,
        .w = 1024,
        .h = 768,
    };

    if (SDL.SDL_Init(SDL.SDL_INIT_VIDEO) < 0)
        sdlPanic();
    defer SDL.SDL_Quit();

    SDL.SDL_EnableScreenSaver();
    _ = SDL.SDL_ShowCursor(0);
    _ = SDL.SDL_SetHint(SDL.SDL_HINT_RENDER_SCALE_QUALITY, "best");

    var window_flags: u32 = SDL.SDL_WINDOW_HIDDEN;
    var display: c_int = 0;

    if (fullscreen) {
        window_flags |= SDL.SDL_WINDOW_FULLSCREEN_DESKTOP;
        display = best_display(risc_rect);
    }
    if (zoom == 0.0) {
        var bounds: SDL.SDL_Rect = undefined;
        if (SDL.SDL_GetDisplayBounds(display, &bounds) == 0 and
            bounds.h >= risc_rect.h * 2 and bounds.w >= risc_rect.w * 2)
        {
            zoom = 2.0;
        } else {
            zoom = 1.0;
        }
    }

    const window = SDL.SDL_CreateWindow(
        "Project Oberon",
        SDL.SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), // FixMe: should be 'display'
        SDL.SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), // FixMe: should be 'display'
        @intFromFloat(@as(f32, risc_rect.w) * zoom),
        @intFromFloat(@as(f32, risc_rect.h) * zoom),
        window_flags,
    ) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyWindow(window);

    const renderer = SDL.SDL_CreateRenderer(window, -1, SDL.SDL_RENDERER_ACCELERATED) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyRenderer(renderer);

    const texture = SDL.SDL_CreateTexture(renderer, SDL.SDL_PIXELFORMAT_ABGR8888, SDL.SDL_TEXTUREACCESS_STREAMING, risc_rect.w, risc_rect.h) orelse sdlPanic();

    var display_rect: SDL.SDL_Rect = undefined;
    _ = scale_display(window, risc_rect, &display_rect);
    std.debug.print("x: {} y: {} w: {} h: {}", .{ display_rect.x, display_rect.y, display_rect.w, display_rect.h });

    SDL.SDL_ShowWindow(window);
    _ = SDL.SDL_RenderClear(renderer);
    _ = SDL.SDL_RenderCopy(renderer, texture, &risc_rect, &display_rect);

    mainLoop: while (true) {
        // const frame_start: u32 = SDL.SDL_GetTicks();

        var ev: SDL.SDL_Event = undefined;
        while (SDL.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                SDL.SDL_QUIT => break :mainLoop,

                else => {},
            }
        }

        _ = SDL.SDL_RenderClear(renderer);
        _ = SDL.SDL_RenderCopy(renderer, texture, &risc_rect, &display_rect);

        SDL.SDL_RenderPresent(renderer);

        // const frame_end: u32 = SDL.SDL_GetTicks();
        // const delay: u32 = frame_start + 16 - frame_end;
        const delay: u32 = 17;

        if (delay > 0) {
            SDL.SDL_Delay(delay);
        }
    }
}

fn sdlPanic() noreturn {
    const str = @as(?[*:0]const u8, SDL.SDL_GetError()) orelse "unknown error";
    @panic(std.mem.sliceTo(str, 0));
}

fn best_display(rect: SDL.SDL_Rect) u8 {
    var best: u8 = 0;
    const display_cnt: c_int = SDL.SDL_GetNumVideoDisplays();
    if (display_cnt < 0) sdlPanic();
    var i: c_int = 0;
    while (i < display_cnt) : (i += 1) {
        var bounds: SDL.SDL_Rect = undefined;
        if (SDL.SDL_GetDisplayBounds(@as(c_int, @truncate(i)), &bounds) == 0 and
            bounds.h == rect.h and bounds.w >= rect.w)
        {
            best = @intCast(i);
            if (bounds.w == rect.w) {
                break;
            }
        }
    }
    return best;
}

fn scale_display(window: *SDL.SDL_Window, risc_rect: SDL.SDL_Rect, display_rect: *SDL.SDL_Rect) f32 {
    var win_w: c_int = undefined;
    var win_h: c_int = undefined;
    SDL.SDL_GetWindowSize(window, &win_w, &win_h);
    const oberon_aspect: f32 = @as(f32, @floatFromInt(risc_rect.w)) / @as(f32, @floatFromInt(risc_rect.h));
    const window_aspect: f32 = @as(f32, @floatFromInt(win_w)) / @as(f32, @floatFromInt(win_h));

    var scale: f32 = undefined;
    if (oberon_aspect > window_aspect) {
        scale = @as(f32, @floatFromInt(win_w)) / @as(f32, @floatFromInt(risc_rect.w));
    } else {
        scale = @as(f32, @floatFromInt(win_h)) / @as(f32, @floatFromInt(risc_rect.h));
    }

    const w = @ceil(@as(f32, @floatFromInt(risc_rect.w)) * scale);
    const h = @ceil(@as(f32, @floatFromInt(risc_rect.h)) * scale);

    display_rect.*.w = @intFromFloat(w);
    display_rect.*.h = @intFromFloat(h);
    display_rect.*.x = @intFromFloat((@as(f32, @floatFromInt(win_w)) - w) / 2.0);
    display_rect.*.y = @intFromFloat((@as(f32, @floatFromInt(win_h)) - h) / 2.0);

    return scale;
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
