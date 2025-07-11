const std = @import("std");
const testing = std.testing;

const felher = @import("root.zig");
const ErrorReporter = felher.ErrorReporter;
const Diagnostic = felher.Diagnostic;
const Severity = felher.Severity;
const SourceRange = felher.SourceRange;
const Position = felher.Position;

test "SourcePos creation" {
    const pos = Position{ .line = 10, .column = 5 };
    try testing.expectEqual(@as(usize, 10), pos.line);
    try testing.expectEqual(@as(usize, 5), pos.column);
}

test "SourceRange single character" {
    const range = SourceRange.single("test.zig", 10, 5);

    try testing.expectEqualStrings("test.zig", range.file);
    try testing.expectEqual(@as(usize, 10), range.start.line);
    try testing.expectEqual(@as(usize, 5), range.start.column);
    try testing.expectEqual(@as(usize, 10), range.end.line);
    try testing.expectEqual(@as(usize, 5), range.end.column);
    try testing.expect(range.isSingleChar());
    try testing.expect(!range.isMultiline());
}

test "SourceRange span" {
    const range = SourceRange.span("test.zig", 10, 5, 12, 8);

    try testing.expectEqualStrings("test.zig", range.file);
    try testing.expectEqual(@as(usize, 10), range.start.line);
    try testing.expectEqual(@as(usize, 5), range.start.column);
    try testing.expectEqual(@as(usize, 12), range.end.line);
    try testing.expectEqual(@as(usize, 8), range.end.column);
    try testing.expect(!range.isSingleChar());
    try testing.expect(range.isMultiline());
}

test "SourceRange single line span" {
    const range = SourceRange.span("test.zig", 10, 5, 10, 15);

    try testing.expect(!range.isSingleChar());
    try testing.expect(!range.isMultiline());
    try testing.expectEqual(@as(usize, 11), range.length());
}

test "Diagnostic with range" {
    const range = SourceRange.span("example.zig", 42, 10, 42, 20);
    const diag = Diagnostic.init(.err, "test error")
        .withRange(range);

    try testing.expectEqual(Severity.err, diag.severity);
    try testing.expectEqualStrings("test error", diag.message);
    try testing.expect(diag.range != null);
    try testing.expectEqualStrings("example.zig", diag.range.?.file);
    try testing.expectEqual(@as(usize, 42), diag.range.?.start.line);
    try testing.expectEqual(@as(usize, 10), diag.range.?.start.column);
    try testing.expectEqual(@as(usize, 42), diag.range.?.end.line);
    try testing.expectEqual(@as(usize, 20), diag.range.?.end.column);
}

test "Diagnostic with location (backward compatibility)" {
    const diag = Diagnostic.init(.warn, "test warning")
        .withLocation("test.zig", 15, 8);

    try testing.expectEqual(Severity.warn, diag.severity);
    try testing.expectEqualStrings("test warning", diag.message);
    try testing.expect(diag.range != null);
    try testing.expectEqualStrings("test.zig", diag.range.?.file);
    try testing.expectEqual(@as(usize, 15), diag.range.?.start.line);
    try testing.expectEqual(@as(usize, 8), diag.range.?.start.column);
    try testing.expectEqual(@as(usize, 15), diag.range.?.end.line);
    try testing.expectEqual(@as(usize, 8), diag.range.?.end.column);
    try testing.expect(diag.range.?.isSingleChar());
}

test "createDiagnostic convenience function" {
    const diag = felher.createDiagnostic(.err, "syntax error", "main.zig", 15, 8);

    try testing.expectEqual(Severity.err, diag.severity);
    try testing.expectEqualStrings("syntax error", diag.message);
    try testing.expect(diag.range != null);
    try testing.expectEqualStrings("main.zig", diag.range.?.file);
    try testing.expectEqual(@as(usize, 15), diag.range.?.start.line);
    try testing.expectEqual(@as(usize, 8), diag.range.?.start.column);
    try testing.expect(diag.range.?.isSingleChar());
}

test "createDiagnosticRange convenience function" {
    const diag = felher.createDiagnosticRange(.warn, "long identifier", "main.zig", 15, 8, 15, 25);

    try testing.expectEqual(Severity.warn, diag.severity);
    try testing.expectEqualStrings("long identifier", diag.message);
    try testing.expect(diag.range != null);
    try testing.expectEqualStrings("main.zig", diag.range.?.file);
    try testing.expectEqual(@as(usize, 15), diag.range.?.start.line);
    try testing.expectEqual(@as(usize, 8), diag.range.?.start.column);
    try testing.expectEqual(@as(usize, 15), diag.range.?.end.line);
    try testing.expectEqual(@as(usize, 25), diag.range.?.end.column);
    try testing.expect(!diag.range.?.isSingleChar());
    try testing.expect(!diag.range.?.isMultiline());
}

test "ErrorReporter with range diagnostics" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    const source =
        \\const std = @import("std");
        \\const print = std.debug.print;
        \\
        \\pub fn main() void {
        \\    const very_long_variable_name = 42;
        \\    const y = x + "hello"; // Type mismatch error
        \\    print("Result: {}\n", .{y});
        \\}
    ;

    try reporter.addSource("example.zig", source);

    const diagnostics = [_]Diagnostic{
        felher.createDiagnosticRange(.err, "type mismatch: cannot add integer and string", "example.zig", 6, 15, 6, 23),
        felher.createDiagnosticRange(.warn, "variable name is too long", "example.zig", 5, 11, 5, 35),
        felher.createDiagnostic(.err, "undefined variable 'x'", "example.zig", 6, 15),
    };

    try testing.expectEqual(@as(usize, 3), diagnostics.len);
    try testing.expectEqual(Severity.err, diagnostics[0].severity);
    try testing.expectEqual(Severity.warn, diagnostics[1].severity);
    try testing.expectEqual(Severity.err, diagnostics[2].severity);
}

test "Multi-line range" {
    const range = SourceRange.span("test.zig", 5, 10, 8, 15);

    try testing.expect(range.isMultiline());
    try testing.expect(!range.isSingleChar());
    try testing.expectEqual(@as(usize, 5), range.start.line);
    try testing.expectEqual(@as(usize, 10), range.start.column);
    try testing.expectEqual(@as(usize, 8), range.end.line);
    try testing.expectEqual(@as(usize, 15), range.end.column);
}

test "ErrorReporter integration with ranges" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    const source_code =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const name = "World";
        \\    const greeting = try std.fmt.allocPrint(allocator, "Hello, {}!", .{name});
        \\    defer allocator.free(greeting);
        \\
        \\    std.debug.print("{s}\n", .{greeting});
        \\}
    ;

    try reporter.addSource("hello.zig", source_code);

    const single_char = felher.createDiagnostic(.err, "missing semicolon", "hello.zig", 10, 1);
    const short_range = felher.createDiagnosticRange(.warn, "unused variable", "hello.zig", 6, 11, 6, 18);
    const long_range = felher.createDiagnosticRange(.note, "function signature", "hello.zig", 3, 1, 3, 25);

    try testing.expect(single_char.range.?.isSingleChar());
    try testing.expect(!short_range.range.?.isSingleChar());
    try testing.expect(!short_range.range.?.isMultiline());
    try testing.expect(!long_range.range.?.isMultiline());
    try testing.expectEqual(@as(usize, 8), short_range.range.?.length());
    try testing.expectEqual(@as(usize, 25), long_range.range.?.length());
}

test "emitSarif outputs valid JSON with basic diagnostic" {
    var buffer: [1024]u8 = undefined;

    const diag1 = Diagnostic.init(.err, "invalid token")
        .withLocation("main.zig", 1, 2)
        .withCode("E001");

    const diag2 = Diagnostic.init(.err, "invalid token")
        .withLocation("main.zig", 3, 4)
        .withCode("E001");

    var stream = std.io.fixedBufferStream(&buffer);
    try felher.emitSarif(&[_]Diagnostic{ diag1, diag2 }, stream.writer());

    const json = buffer[0..stream.pos];
    try testing.expect(std.mem.indexOf(u8, json, "\"message\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "invalid token") != null);
    try testing.expect(std.mem.indexOf(u8, json, "main.zig") != null);
    try testing.expect(std.mem.indexOf(u8, json, "E001") != null);
}
