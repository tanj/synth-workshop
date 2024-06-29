const std = @import("std");
const builtin = @import("builtin");
const Builder = std.Build;

const rp2040 = @import("microzig/bsp/raspberrypi/rp2040");
const MicroZig = @import("microzig/build");

const Demo = struct {
    target: MicroZig.Target,
    name: []const u8,
    file: []const u8,
};

const pico = rp2040.boards.raspberrypi.pico;
const demos: []const Demo = &.{
    // zig fmt: off
    .{ .target = pico, .name = "blinky",                 .file = "demos/00_blinky/main.zig" },
    .{ .target = pico, .name = "uart",                   .file = "demos/01_uart/uart.zig" },
    .{ .target = pico, .name = "uart_monitor",           .file = "demos/01_uart/monitor.zig" },
    .{ .target = pico, .name = "single_tone",            .file = "demos/02_single_tone/main.zig" },
    .{ .target = pico, .name = "volume_knob",            .file = "demos/03_volume_knob/main.zig" },
    .{ .target = pico, .name = "monophonic_keypad",      .file = "demos/04_monophonic_keypad/main.zig" },
    .{ .target = pico, .name = "adsr",                   .file = "demos/05_adsr/main.zig" },
    .{ .target = pico, .name = "additive_synthesis",     .file = "demos/06_additive_synthesis/main.zig" },
    .{ .target = pico, .name = "fm_synthesis_lfo",       .file = "demos/07_fm_synthesis/lfo.zig" },
    .{ .target = pico, .name = "fm_synthesis_operators", .file = "demos/07_fm_synthesis/operators.zig" },
    // zig fmt: on
};

pub fn build(b: *Builder) void {
    const mz = MicroZig.init(b, .{});
    const optimize = b.standardOptimizeOption(.{});

    // const raylib_zig_dep = b.dependency("raylib_zig", .{
    //     .optimize = optimize,
    // });
    //
    // const raylib_dep = b.dependency("raylib", .{
    //     .optimize = optimize,
    // });

    for (demos) |demo| {
        const workshop_module = b.createModule(.{
            .root_source_file = .{
                .path = "src/workshop.zig",
            },
        });
        // `add_firmware` basically works like addExecutable, but takes a
        // `microzig.Target` for target instead of a `std.zig.CrossTarget`.
        //
        // The target will convey all necessary information on the chip,
        // cpu and potentially the board as well.
        const firmware = mz.add_firmware(b, .{
            .name = demo.name,
            .target = demo.target,
            .optimize = optimize,
            .root_source_file = .{ .path = demo.file },
        });
        firmware.add_app_import("workshop", workshop_module, .{.depend_on_microzig = true});

        // `install_firmware()` is the MicroZig pendant to `Build.installArtifact()`
        // and allows installing the firmware as a typical firmware file.
        //
        // This will also install into `$prefix/firmware` instead of `$prefix/bin`.
        mz.install_firmware(b, firmware, .{});

        // For debugging, we also always install the firmware as an ELF file
        mz.install_firmware(b, firmware, .{ .format = .elf }); 
    }

    // monitor application
    // const monitor_exe = b.addExecutable(.{
    //     .name = "monitor",
    //     .root_source_file = .{ .path = "src/monitor_exe.zig" },
    //     .optimize = optimize,
    // });

    // monitor_exe.addModule("raylib", raylib_zig_dep.module("raylib"));
    // monitor_exe.linkLibrary(raylib_dep.artifact("raylib"));

    // const monitor_run = b.addRunArtifact(monitor_exe);
    // const monitor_step = b.step("monitor", "Run monitor application");
    // monitor_step.dependOn(&monitor_run.step);

    // tools
    const os_str = comptime enum_to_string(builtin.os.tag);
    const arch_str = comptime enum_to_string(builtin.cpu.arch);

    // openocd
    const openocd_subdir = comptime std.fmt.comptimePrint("tools/openocd/{s}-{s}", .{ arch_str, os_str });
    const openocd_scripts_dir = comptime std.fmt.comptimePrint("{s}/share/openocd/scripts", .{openocd_subdir});
    const openocd_exe = if (builtin.os.tag == .linux)
        "openocd"
    else
        comptime std.fmt.comptimePrint("{s}/bin/openocd{s}", .{
        openocd_subdir,
        if (builtin.os.tag == .windows) ".exe" else "",
    });

    // zig fmt: off
    const run_openocd = b.addSystemCommand(&.{
        openocd_exe,
        "-f", "interface/cmsis-dap.cfg",
        "-f", "target/rp2040.cfg",
        "-c", "adapter speed 5000",
    });
    // zig fmt: on

    // linux users need to build their own openocd
    if (builtin.os.tag == .linux) {
        run_openocd.addArgs(&.{ "-s", openocd_scripts_dir });
    }

    const openocd = b.step("openocd", "run openocd for your debugger");
    openocd.dependOn(&run_openocd.step);
}

fn enum_to_string(comptime val: anytype) []const u8 {
    const Enum = @TypeOf(val);
    return inline for (@typeInfo(Enum).Enum.fields) |field| {
        if (val == @field(Enum, field.name))
            break field.name;
    } else unreachable;
}
