const std = @import("std");

var allocator: std.mem.Allocator = undefined;

const src_main = @embedFile("root/main.zig");
const src_root = @embedFile("root/root.zig");
const build_exe = @embedFile("root/build_exe.zig");
const build_lib = @embedFile("root/build_lib.zig");
const zon_template = @embedFile("root/build.zig.zon");

const cxx_main = @embedFile("root/cxx/main.cc");
const cmake_template = @embedFile("root/cxx//CMakeLists.txt");

fn usage() void {
    var args_it = std.process.args();
    const exe_name = args_it.next().?;

    const stderr = std.io.getStdErr().writer();
    stderr.print(
        \\Usage:
        \\  {s} <init-type>
        \\  
        \\  [init-type] {{ exe, lib, c++ }}
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

    @"c++",

    fn fromStr(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }

    fn execute(self: Command, dir: []const u8) anyerror!void {
        return switch (self) {
            .exe => initExe(dir),
            .lib => initLib(dir),
            .@"c++" => initCxx(dir),
        };
    }

    fn initExe(dir: []const u8) anyerror!void {
        const cwd = std.fs.cwd();

        var src_dir = try cwd.makeOpenPath("src", .{});
        defer src_dir.close();

        // src/main.zig
        {
            try file_print(.{ .root = src_dir, .file_name = "main.zig", .template = src_main });
        }

        // build.zig
        {
            try file_print(.{ .root = cwd, .file_name = "build.zig", .template = build_exe, .replacement = dir });
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
            try file_print(.{ .root = src_dir, .file_name = "root.zig", .template = src_root });
        }

        // build.zig
        {
            try file_print(.{ .root = cwd, .file_name = "build.zig", .template = build_lib, .replacement = dir });
        }

        // build.zig.zon
        {
            try build_zig_zon(cwd, dir);
        }
    }

    fn initCxx(dir: []const u8) anyerror!void {
        const cwd = std.fs.cwd();

        var src_dir = try cwd.makeOpenPath("src", .{});
        defer src_dir.close();

        {
            try file_print(.{ .root = src_dir, .file_name = "main.cc", .template = cxx_main });
        }

        {
            try file_print(.{
                .root = cwd,
                .file_name = "CMakeLists.txt",
                .template = cmake_template,
                .from = "PR_NAME",
                .replacement = dir,
            });
        }
    }

    const FilePrintProps = struct {
        root: std.fs.Dir,
        file_name: []const u8 = "",
        template: []const u8 = "",
        from: []const u8 = "$",
        replacement: []const u8 = "",
    };
    fn file_print(p: FilePrintProps) anyerror!void {
        var file = try p.root.createFile(p.file_name, .{});
        defer file.close();

        const contents = try std.mem.replaceOwned(u8, allocator, p.template, p.from, p.replacement);
        defer allocator.free(contents);

        try file.writeAll(contents);
    }

    fn build_zig_zon(root: std.fs.Dir, project_name: []const u8) anyerror!void {
        return file_print(.{ .root = root, .file_name = "build.zig.zon", .template = zon_template, .replacement = project_name });
    }
};
