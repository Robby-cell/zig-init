const std = @import("std");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    try std.testing.expect(add(2, 3) == 5);
}
