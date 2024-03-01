const std = @import("std");

var allocator: std.mem.Allocator = undefined;

const src_main = @embedFile("root/main.zig");
const src_root = @embedFile("root/root.zig");
const build_exe = @embedFile("root/build_exe.zig");
const build_lib = @embedFile("root/build_lib.zig");
const zon_template = @embedFile("root/build.zig.zon");

fn usage() void {
    var args_it = std.process.args();
    const exe_name = args_it.next().?;

    const stderr = std.io.getStdErr().writer();
    stderr.print(
        \\Usage:
        \\  {s} <init-type>
        \\  
        \\  [init-type] {{ exe, lib }}
        \\
    , .{exe_name}) catch unreachable;
}

fn errorUsage(comptime err: anytype) blk: {
    const info = @typeInfo(@TypeOf(err));
    if (info != .ErrorSet) {
        @compileError("Expected error type.");
    }
    break :blk @TypeOf(err);
}!noreturn {
    usage();
    return err;
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer if (gpa.deinit() == .leak) {
        const stderr = std.io.getStdErr().writer();
        stderr.print("Memory leaked.\n", .{}) catch unreachable;
    };
    allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        try errorUsage(error.InvalidArgs);
    }

    const cmd_str = args[1];
    const cmd = Command.fromStr(cmd_str) orelse try errorUsage(error.InvalidCommand);

    const cwd = std.fs.cwd();
    var buf: [1024]u8 = undefined;
    const dir = blk: {
        const path = try cwd.realpathZ(".", buf[0..]);
        var split = std.mem.splitBackwardsScalar(u8, path, '/');

        break :blk split.next() orelse return error.RootDir; // wont't do this in root dir
    };

    try cmd.execute(dir);
}

const Command = enum {
    exe,
    lib,

    fn fromStr(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }

    fn execute(self: Command, dir: []const u8) anyerror!void {
        return switch (self) {
            .exe => initExe(dir),
            .lib => initLib(dir),
        };
    }

    fn initExe(dir: []const u8) anyerror!void {
        const cwd = std.fs.cwd();

        var src_dir = try cwd.makeOpenPath("src", .{});
        defer src_dir.close();

        // src/main.zig
        {
            try file_print(src_dir, "main.zig", src_main, "");
        }

        // build.zig
        {
            try file_print(cwd, "build.zig", build_exe, dir);
        }

        // build.zig.zon
        {
            try build_zig_zon(cwd, dir);
        }
    }

    fn initLib(dir: []const u8) anyerror!void {
        const cwd = std.fs.cwd();

        var src_dir = try cwd.makeOpenPath("src", .{});
        defer src_dir.close();

        // src/root.zig
        {
            try file_print(src_dir, "root.zig", src_root, "");
            // var root_file = try src_dir.createFile("root.zig", .{ .mode = .write_only });
            // defer root_file.close();
            //
            // try root_file.writeAll(src_root);
        }

        // build.zig
        {
            try file_print(cwd, "build.zig", build_lib, dir);
            // var build_file = try cwd.createFile("build.zig", .{ .mode = .write_only });
            // defer build_file.close();
            //
            // const build_script = try std.fmt.allocPrint(allocator, build_lib, .{dir});
            // defer allocator.free(build_script);
            //
            // try build_file.writeAll(build_script);
        }

        // build.zig.zon
        {
            try build_zig_zon(cwd, dir);
        }
    }

    fn file_print(
        root: std.fs.Dir,
        comptime file_name: []const u8,
        comptime template: []const u8,
        replacement: []const u8,
    ) anyerror!void {
        var file = try root.createFile(file_name, .{});
        defer file.close();

        const contents = try std.mem.replaceOwned(u8, allocator, template, "$", replacement);
        defer allocator.free(contents);

        try file.writeAll(contents);
    }

    fn build_zig_zon(root: std.fs.Dir, project_name: []const u8) anyerror!void {
        return file_print(root, "build.zig.zon", zon_template, project_name);
    }
};
