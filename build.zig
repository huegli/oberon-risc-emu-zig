const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    // Create a new instance of the SDL2 Sdk
    const sdk = Sdk.init(b, null);

    // Determine compilation target
    const target = b.standardTargetOptions(.{});

    // Create executable for our example
    const risc = b.addExecutable(.{
        .name = "risc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
    });
    sdk.link(risc, .dynamic); // link SDL2 as a shared library

    // Add "sdl2" package that exposes the SDL2 api (like SDL_Init or SDL_CreateWindow)
    risc.root_module.addImport("sdl2", sdk.getWrapperModule());

    // Install the executable into the prefix when invoking "zig build"
    b.installArtifact(risc);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(risc);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const host_system = @import("builtin").target;

const Build = std.Build;
const Step = Build.Step;
const LazyPath = Build.LazyPath;
const GeneratedFile = Build.GeneratedFile;
const Compile = Build.Step.Compile;

const Sdk = @This();

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("relToPath requires an absolute path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

const sdl2_symbol_definitions = @embedFile("sdl2/stubs/libSDL2.def");

build: *Build,
config_path: []const u8,

prepare_sources: *PrepareStubSourceStep,

/// Creates a instance of the Sdk and initializes internal steps.
/// Initialize once, use everywhere (in your `build` function).
pub fn init(b: *Build, maybe_config_path: ?[]const u8) *Sdk {
    const sdk = b.allocator.create(Sdk) catch @panic("out of memory");
    const config_path = maybe_config_path orelse std.fs.path.join(
        b.allocator,
        &[_][]const u8{
            b.pathFromRoot(".build_config"),
            "sdl.json",
        },
    ) catch @panic("out of memory");

    sdk.* = .{
        .build = b,
        .config_path = config_path,
        .prepare_sources = undefined,
    };
    sdk.prepare_sources = PrepareStubSourceStep.create(sdk);

    return sdk;
}

/// Returns a module with the raw SDL api with proper argument types, but no functional/logical changes
/// for a more *ziggy* feeling.
/// This is similar to the *C import* result.
pub fn getNativeModule(sdk: *Sdk) *Build.Module {
    const build_options = sdk.build.addOptions();
    build_options.addOption(bool, "vulkan", false);
    return sdk.build.createModule(.{
        .root_source_file = .{ .path = sdkPath("/sdl2/binding/sdl.zig") },
        .imports = &.{
            .{
                .name = sdk.build.dupe("build_options"),
                .module = build_options.createModule(),
            },
        },
    });
}

/// Returns a module with the raw SDL api with proper argument types, but no functional/logical changes
/// for a more *ziggy* feeling, with Vulkan support! The Vulkan module provided by `vulkan-zig` must be
/// provided as an argument.
/// This is similar to the *C import* result.
pub fn getNativeModuleVulkan(sdk: *Sdk, vulkan: *Build.Module) *Build.Module {
    const build_options = sdk.build.addOptions();
    build_options.addOption(bool, "vulkan", true);
    return sdk.build.createModule(.{
        .root_source_file = .{ .path = sdkPath("/sdl2/binding/sdl.zig") },
        .imports = &.{
            .{
                .name = sdk.build.dupe("build_options"),
                .module = build_options.createModule(),
            },
            .{
                .name = sdk.build.dupe("vulkan"),
                .module = vulkan,
            },
        },
    });
}

/// Returns the smart wrapper for the SDL api. Contains convenient zig types, tagged unions and so on.
pub fn getWrapperModule(sdk: *Sdk) *Build.Module {
    return sdk.build.createModule(.{
        .root_source_file = .{ .path = sdkPath("/sdl2/wrapper/sdl.zig") },
        .imports = &.{
            .{
                .name = sdk.build.dupe("sdl-native"),
                .module = sdk.getNativeModule(),
            },
        },
    });
}

/// Returns the smart wrapper with Vulkan support. The Vulkan module provided by `vulkan-zig` must be
/// provided as an argument.
pub fn getWrapperModuleVulkan(sdk: *Sdk, vulkan: *Build.Module) *Build.Module {
    return sdk.build.createModule(.{
        .root_source_file = .{ .path = sdkPath("/sdl2/wrapper/sdl.zig") },
        .imports = &.{
            .{
                .name = sdk.build.dupe("sdl-native"),
                .module = sdk.getNativeModuleVulkan(vulkan),
            },
            .{
                .name = sdk.build.dupe("vulkan"),
                .module = vulkan,
            },
        },
    });
}

pub fn linkTtf(_: *Sdk, exe: *Compile) void {
    const target = (std.zig.system.NativeTargetInfo.detect(exe.target) catch @panic("failed to detect native target info!")).target;

    // This is required on all platforms
    exe.linkLibC();

    if (target.os.tag == .linux) {
        exe.linkSystemLibrary("sdl2_ttf");
    } else if (target.os.tag == .windows) {
        @compileError("Not implemented yet");
    } else if (target.isDarwin()) {

        // on MacOS, we require a brew install
        // requires sdl_ttf to be installed via brew

        exe.linkSystemLibrary("sdl2_ttf");
        exe.linkSystemLibrary("freetype");
        exe.linkSystemLibrary("harfbuzz");
        exe.linkSystemLibrary("bz2");
        exe.linkSystemLibrary("zlib");
        exe.linkSystemLibrary("graphite2");
    } else {
        // on all other platforms, just try the system way:
        exe.linkSystemLibrary("sdl2_ttf");
    }
}

/// Links SDL2 to the given exe and adds required installs if necessary.
/// **Important:** The target of the `exe` must already be set, otherwise the Sdk will do the wrong thing!
pub fn link(sdk: *Sdk, exe: *Compile, linkage: std.builtin.LinkMode) void {
    // TODO: Implement

    const b = sdk.build;
    const target = exe.root_module.resolved_target.?;
    const is_native = target.query.isNativeOs();

    // This is required on all platforms
    exe.linkLibC();

    if (target.result.os.tag == .linux and !is_native) {
        // for cross-compilation to Linux, we use a magic trick:
        // we compile a stub .so file we will link against an SDL2.so even if that file
        // doesn't exist on our system

        const build_linux_sdl_stub = b.addSharedLibrary(.{
            .name = "SDL2",
            .target = exe.root_module.resolved_target.?,
            .optimize = exe.root_module.optimize.?,
        });
        build_linux_sdl_stub.addAssemblyFile(sdk.prepare_sources.getStubFile());

        // We need to link against libc
        exe.linkLibC();

        // link against the output of our stub
        exe.linkLibrary(build_linux_sdl_stub);
    } else if (target.result.os.tag == .linux) {
        // on linux with compilation for native target,
        // we should rely on the system libraries to "just work"
        exe.linkSystemLibrary("sdl2");
    } else if (target.result.os.tag == .windows) {
        const sdk_paths = sdk.getPaths(target) catch |err| {
            const writer = std.io.getStdErr().writer();

            const target_name = tripleName(sdk.build.allocator, target) catch @panic("out of memory");

            switch (err) {
                error.FileNotFound => {
                    writer.print("Could not auto-detect SDL2 sdk configuration. Please provide {s} with the following contents filled out:\n", .{
                        sdk.config_path,
                    }) catch @panic("io error");
                    writer.print("{{\n  \"{s}\": {{\n", .{target_name}) catch @panic("io error");
                    writer.writeAll(
                        \\    "include": "<path to sdl2 sdk>/include",
                        \\    "libs": "<path to sdl2 sdk>/lib",
                        \\    "bin": "<path to sdl2 sdk>/bin"
                        \\  }
                        \\}
                        \\
                    ) catch @panic("io error");
                    writer.writeAll(
                        \\
                        \\You can obtain a SDL2 sdk for windows from https://www.libsdl.org/download-2.0.php
                        \\
                    ) catch @panic("io error");
                },
                error.MissingTarget => {
                    writer.print("{s} is missing a SDK definition for {s}. Please add the following section to the file and fill the paths:\n", .{
                        sdk.config_path,
                        target_name,
                    }) catch @panic("io error");
                    writer.print("  \"{s}\": {{\n", .{target_name}) catch @panic("io error");
                    writer.writeAll(
                        \\  "include": "<path to sdl2 sdk>/include",
                        \\  "libs": "<path to sdl2 sdk>/lib",
                        \\  "bin": "<path to sdl2 sdk>/bin"
                        \\}
                    ) catch @panic("io error");
                    writer.writeAll(
                        \\
                        \\You can obtain a SDL2 sdk for windows from https://www.libsdl.org/download-2.0.php
                        \\
                    ) catch @panic("io error");
                },
                error.InvalidJson => {
                    writer.print("{s} contains invalid JSON. Please fix that file!\n", .{
                        sdk.config_path,
                    }) catch @panic("io error");
                },
                error.InvalidTarget => {
                    writer.print("{s} contains a invalid zig triple. Please fix that file!\n", .{
                        sdk.config_path,
                    }) catch @panic("io error");
                },
            }

            std.process.exit(1);
        };

        // linking on windows is sadly not as trivial as on linux:
        // we have to respect 6 different configurations {x86,x64}-{msvc,mingw}-{dynamic,static}

        if (target.result.abi == .msvc and linkage != .dynamic)
            @panic("SDL cannot be linked statically for MSVC");

        // These will be added for C-Imports or C files.
        if (target.result.abi != .msvc) {
            // SDL2 (mingw) ships the SDL include files under `include/SDL2/` which is very inconsitent with
            // all other platforms, so we just remove this prefix here
            const include_path = std.fs.path.join(b.allocator, &[_][]const u8{
                sdk_paths.include,
                "SDL2",
            }) catch @panic("out of memory");
            exe.addIncludePath(.{ .cwd_relative = include_path });
        } else {
            exe.addIncludePath(.{ .cwd_relative = sdk_paths.include });
        }

        // link the right libraries
        if (target.result.abi == .msvc) {
            // and links those as normal libraries
            exe.addLibraryPath(.{ .cwd_relative = sdk_paths.libs });
            exe.linkSystemLibrary2("SDL2", .{ .use_pkg_config = .no });
        } else {
            const file_name = switch (linkage) {
                .static => "libSDL2.a",
                .dynamic => "libSDL2.dll.a",
            };

            const lib_path = std.fs.path.join(b.allocator, &[_][]const u8{
                sdk_paths.libs,
                file_name,
            }) catch @panic("out of memory");

            exe.addObjectFile(.{ .cwd_relative = lib_path });

            if (linkage == .static) {
                // link all system libraries required for SDL2:
                const static_libs = [_][]const u8{
                    "setupapi",
                    "user32",
                    "gdi32",
                    "winmm",
                    "imm32",
                    "ole32",
                    "oleaut32",
                    "shell32",
                    "version",
                    "uuid",
                };
                for (static_libs) |lib|
                    exe.linkSystemLibrary(lib);
            }
        }

        if (linkage == .dynamic and exe.kind == .exe) {
            // On window, we need to copy SDL2.dll to the bin directory
            // for executables
            const sdl2_dll_path = std.fs.path.join(sdk.build.allocator, &[_][]const u8{
                sdk_paths.bin,
                "SDL2.dll",
            }) catch @panic("out of memory");
            sdk.build.installBinFile(sdl2_dll_path, "SDL2.dll");
        }
    } else if (target.result.isDarwin()) {
        // TODO: Implement cross-compilaton to macOS via system root provisioning
        if (!host_system.os.tag.isDarwin())
            @panic("Cannot cross-compile to macOS yet.");

        // on MacOS, we require a brew install
        // requires sdl2 and sdl2_image to be installed via brew
        exe.linkSystemLibrary("sdl2");

        exe.linkFramework("IOKit");
        exe.linkFramework("Cocoa");
        exe.linkFramework("CoreAudio");
        exe.linkFramework("Carbon");
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("AudioToolbox");
        exe.linkFramework("ForceFeedback");
        exe.linkFramework("GameController");
        exe.linkFramework("CoreHaptics");
        exe.linkSystemLibrary("iconv");
    } else {
        const triple_string = target.query.zigTriple(b.allocator) catch "unkown-unkown-unkown";
        std.log.warn("Linking SDL2 for {s} is not tested, linking might fail!", .{triple_string});

        // on all other platforms, just try the system way:
        exe.linkSystemLibrary("sdl2");
    }
}

const Paths = struct {
    include: []const u8,
    libs: []const u8,
    bin: []const u8,
};

fn getPaths(sdk: *Sdk, target_local: std.Build.ResolvedTarget) error{ MissingTarget, FileNotFound, InvalidJson, InvalidTarget }!Paths {
    const json_data = std.fs.cwd().readFileAlloc(sdk.build.allocator, sdk.config_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => |e| @panic(@errorName(e)),
    };

    const parsed = std.json.parseFromSlice(std.json.Value, sdk.build.allocator, json_data, .{}) catch return error.InvalidJson;
    var root_node = parsed.value.object;
    var config_iterator = root_node.iterator();
    while (config_iterator.next()) |entry| {
        const config_target = sdk.build.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = entry.key_ptr.* }) catch return error.InvalidTarget,
        );

        if (target_local.result.cpu.arch != config_target.result.cpu.arch)
            continue;
        if (target_local.result.os.tag != config_target.result.os.tag)
            continue;
        if (target_local.result.abi != config_target.result.abi)
            continue;
        // load paths

        const node = entry.value_ptr.*.object;

        return Paths{
            .include = node.get("include").?.string,
            .libs = node.get("libs").?.string,
            .bin = node.get("bin").?.string,
        };
    }
    return error.MissingTarget;
}

const PrepareStubSourceStep = struct {
    const Self = @This();

    step: Step,
    sdk: *Sdk,

    assembly_source: GeneratedFile,

    pub fn create(sdk: *Sdk) *PrepareStubSourceStep {
        const psss = sdk.build.allocator.create(Self) catch @panic("out of memory");

        psss.* = .{
            .step = Step.init(
                .{
                    .id = .custom,
                    .name = "Prepare SDL2 stub sources",
                    .owner = sdk.build,
                    .makeFn = make,
                },
            ),
            .sdk = sdk,
            .assembly_source = .{ .step = &psss.step },
        };

        return psss;
    }

    pub fn getStubFile(self: *Self) LazyPath {
        return .{ .generated = &self.assembly_source };
    }

    fn make(step: *Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self: *Self = @fieldParentPtr("step", step);

        var cache = CacheBuilder.init(self.sdk.build, "sdl");

        cache.addBytes(sdl2_symbol_definitions);

        var dirpath = try cache.createAndGetDir();
        defer dirpath.dir.close();

        var file = try dirpath.dir.createFile("sdl.S", .{});
        defer file.close();

        var writer = file.writer();
        try writer.writeAll(".text\n");

        var iter = std.mem.split(u8, sdl2_symbol_definitions, "\n");
        while (iter.next()) |line| {
            const sym = std.mem.trim(u8, line, " \r\n\t");
            if (sym.len == 0)
                continue;
            try writer.print(".global {s}\n", .{sym});
            try writer.writeAll(".align 4\n");
            try writer.print("{s}:\n", .{sym});
            try writer.writeAll("  .byte 0\n");
        }

        self.assembly_source.path = try std.fs.path.join(self.sdk.build.allocator, &[_][]const u8{
            dirpath.path,
            "sdl.S",
        });
    }
};

fn tripleName(allocator: std.mem.Allocator, target_local: std.Build.ResolvedTarget) ![]u8 {
    const arch_name = @tagName(target_local.result.cpu.arch);
    const os_name = @tagName(target_local.result.os.tag);
    const abi_name = @tagName(target_local.result.abi);

    return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ arch_name, os_name, abi_name });
}

const CacheBuilder = struct {
    const Self = @This();

    build: *std.Build,
    hasher: std.crypto.hash.Sha1,
    subdir: ?[]const u8,

    pub fn init(builder: *std.Build, subdir: ?[]const u8) Self {
        return Self{
            .build = builder,
            .hasher = std.crypto.hash.Sha1.init(.{}),
            .subdir = if (subdir) |s|
                builder.dupe(s)
            else
                null,
        };
    }

    pub fn addBytes(self: *Self, bytes: []const u8) void {
        self.hasher.update(bytes);
    }

    pub fn addFile(self: *Self, file: LazyPath) !void {
        const path = file.getPath(self.build);

        const data = try std.fs.cwd().readFileAlloc(self.build.allocator, path, 1 << 32); // 4 GB
        defer self.build.allocator.free(data);

        self.addBytes(data);
    }

    fn createPath(self: *Self) ![]const u8 {
        var hash: [20]u8 = undefined;
        self.hasher.final(&hash);

        const path = if (self.subdir) |subdir|
            try std.fmt.allocPrint(
                self.build.allocator,
                "{s}/{s}/o/{}",
                .{
                    self.build.cache_root.path.?,
                    subdir,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            )
        else
            try std.fmt.allocPrint(
                self.build.allocator,
                "{s}/o/{}",
                .{
                    self.build.cache_root.path.?,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            );

        return path;
    }

    pub const DirAndPath = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };
    pub fn createAndGetDir(self: *Self) !DirAndPath {
        const path = try self.createPath();
        return DirAndPath{
            .path = path,
            .dir = try std.fs.cwd().makeOpenPath(path, .{}),
        };
    }

    pub fn createAndGetPath(self: *Self) ![]const u8 {
        const path = try self.createPath();
        try std.fs.cwd().makePath(path);
        return path;
    }
};
