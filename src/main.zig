const std = @import("std");
const SDL = @import("sdl2");
const target_os = @import("builtin").os;

const FPS = 60;

pub fn main() !void {
    const fullscreen = false;
    var zoom: f64 = 0.0;

    const risc_rect = SDL.SDL_Rect{
        .x = 0,
        .y = 0,
        .w = 640,
        .h = 480,
    };

    if (SDL.SDL_Init(SDL.SDL_INIT_VIDEO) < 0)
        sdlPanic();
    defer SDL.SDL_Quit();

    SDL.SDL_EnableScreenSaver();
    _ = SDL.SDL_ShowCursor(0);
    _ = SDL.SDL_SetHint(SDL.SDL_HINT_RENDER_SCALE_QUALITY, "best");

    var window_flags: u32 = SDL.SDL_WINDOW_HIDDEN;
    var display: c_uint = 0;

    if (fullscreen) {
        window_flags |= SDL.SDL_WINDOW_FULLSCREEN_DESKTOP;
        display = 0;
    }
    if (zoom == 0.0) {
        // SDL_Rect bounds;
        // if (SDL_GetDisplayBounds(display, &bounds) == 0 &&
        //     bounds.h >= risc_rect.h * 2 && bounds.w >= risc_rect.w * 2) {
        // zoom = 2;
        // } else {
        // zoom = 1;
        // }
        zoom = 1.0;
    }
    const window = SDL.SDL_CreateWindow(
        "Project Oberon",
        SDL.SDL_WINDOWPOS_CENTERED,
        SDL.SDL_WINDOWPOS_CENTERED,
        // @as(c_int, SDL.SDL_WINDOWPOS_UNDEFINED_DISPLAY(display)),
        // @as(c_int, SDL.SDL_WINDOWPOS_UNDEFINED_DISPLAY(display)),
        //@as(c_int, 640 * zoom),
        //@as(c_int, 480 * zoom),
        640,
        480,
        window_flags,
    ) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyWindow(window);

    const renderer = SDL.SDL_CreateRenderer(window, -1, SDL.SDL_RENDERER_ACCELERATED) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyRenderer(renderer);

    const texture = SDL.SDL_CreateTexture(renderer, SDL.SDL_PIXELFORMAT_ABGR8888, SDL.SDL_TEXTUREACCESS_STREAMING, risc_rect.w, risc_rect.h) orelse sdlPanic();

    const display_rect = SDL.SDL_Rect{ .x = 0, .y = 0, .w = 640, .h = 480 };

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
        // const delay: i32 = frame_start + 1000 / FPS - frame_end;
        const delay = 16;

        if (delay > 0) {
            SDL.SDL_Delay(delay);
        }
    }
}

fn sdlPanic() noreturn {
    const str = @as(?[*:0]const u8, SDL.SDL_GetError()) orelse "unknown error";
    @panic(std.mem.sliceTo(str, 0));
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
