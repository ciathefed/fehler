const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

/// ANSI color codes and formatting constants for terminal output.
const Colors = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const cyan = "\x1b[36m";
    const white = "\x1b[37m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
};

/// Represents a location in source code with file, line, and column information.
pub const SourceLoc = struct {
    file: []const u8,
    line: usize,
    column: usize,
};

/// Severity levels for diagnostics, determining color and label presentation.
pub const Severity = enum {
    err,
    warn,
    note,

    /// Returns the ANSI color code associated with this severity level.
    pub fn color(self: Severity) []const u8 {
        return switch (self) {
            .err => Colors.red,
            .warn => Colors.yellow,
            .note => Colors.blue,
        };
    }

    /// Returns the human-readable label for this severity level.
    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warning",
            .note => "note",
        };
    }
};

/// A diagnostic message with optional source location and help text.
/// This is the primary data structure for representing compiler errors, warnings, and notes.
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    location: ?SourceLoc = null,
    help: ?[]const u8 = null,

    /// Creates a new diagnostic with the specified severity and message.
    /// Additional properties can be added using the fluent interface methods.
    pub fn init(severity: Severity, message: []const u8) Diagnostic {
        return Diagnostic{
            .severity = severity,
            .message = message,
        };
    }

    /// Returns a copy of this diagnostic with the specified source location.
    /// This method follows the builder pattern for fluent construction of diagnostics.
    pub fn withLocation(self: Diagnostic, location: SourceLoc) Diagnostic {
        var diag = self;
        diag.location = location;
        return diag;
    }

    /// Returns a copy of this diagnostic with the specified help text.
    /// This method follows the builder pattern for fluent construction of diagnostics.
    pub fn withHelp(self: Diagnostic, help: []const u8) Diagnostic {
        var diag = self;
        diag.help = help;
        return diag;
    }
};

/// A comprehensive error reporting system that manages source files and formats diagnostics.
/// This reporter can store multiple source files and display rich error messages with
/// source code context, similar to modern compiler error output.
pub const ErrorReporter = struct {
    allocator: Allocator,
    sources: std.StringHashMap([]const u8),

    /// Initializes a new ErrorReporter with the given allocator.
    /// The reporter starts with no source files registered.
    pub fn init(allocator: Allocator) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .sources = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitializes the ErrorReporter, freeing all stored source content.
    /// This must be called to prevent memory leaks.
    pub fn deinit(self: *ErrorReporter) void {
        var iterator = self.sources.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.sources.deinit();
    }

    /// Adds a source file to the reporter for later reference in diagnostics.
    /// The content is duplicated and owned by the reporter.
    pub fn addSource(self: *ErrorReporter, filename: []const u8, content: []const u8) !void {
        if (self.sources.get(filename)) |old_content| {
            self.allocator.free(old_content);
        }

        const owned_content = try self.allocator.dupe(u8, content);
        try self.sources.put(filename, owned_content);
    }

    /// Reports a single diagnostic to stdout with color formatting.
    /// If the diagnostic has a location and the source file is available,
    /// displays a source code snippet with the error location highlighted.
    pub fn report(self: *ErrorReporter, diagnostic: Diagnostic) void {
        print("{s}{s}{s}: {s}{s}\n", .{
            diagnostic.severity.color(),
            Colors.bold,
            diagnostic.severity.label(),
            Colors.reset,
            diagnostic.message,
        });

        if (diagnostic.location) |loc| {
            print("  {s}{s}{s}:{}:{}{s}\n", .{
                Colors.cyan,
                Colors.bold,
                loc.file,
                loc.line,
                loc.column,
                Colors.reset,
            });

            self.printSourceSnippet(loc) catch {};
        }

        if (diagnostic.help) |help| {
            print("  {s}{s}help{s}: {s}\n", .{
                Colors.cyan,
                Colors.bold,
                Colors.reset,
                help,
            });
        }

        print("\n", .{});
    }

    /// Reports multiple diagnostics in sequence.
    /// Each diagnostic is printed with the same formatting as `report()`.
    pub fn reportMany(self: *ErrorReporter, diagnostics: []const Diagnostic) void {
        for (diagnostics) |diagnostic| {
            self.report(diagnostic);
        }
    }

    /// Prints a source code snippet showing the context around a diagnostic location.
    /// Shows 2 lines before and after the error location, with the error line highlighted
    /// and a caret (^) pointing to the specific column.
    fn printSourceSnippet(self: *ErrorReporter, loc: SourceLoc) !void {
        const source = self.sources.get(loc.file) orelse return;

        var lines = std.mem.splitScalar(u8, source, '\n');
        var current_line: usize = 1;
        const context_start = if (loc.line > 2) loc.line - 2 else 1;
        const context_end = loc.line + 2;

        while (current_line < context_start and lines.next() != null) {
            current_line += 1;
        }

        while (current_line <= context_end) {
            if (lines.next()) |line| {
                defer current_line += 1;

                const line_num_width = 4;
                if (current_line == loc.line) {
                    print("  {s}{s}{d:>4} |{s} {s}\n", .{
                        Colors.red,
                        Colors.bold,
                        current_line,
                        Colors.reset,
                        line,
                    });

                    var i: usize = 0;
                    print("  {s}", .{Colors.red});
                    while (i < line_num_width + 1) : (i += 1) {
                        print(" ", .{});
                    }
                    print("  ", .{});
                    i = 1;
                    while (i < loc.column) : (i += 1) {
                        print(" ", .{});
                    }
                    print("^{s}\n", .{Colors.reset});
                } else {
                    print("  {s}{d:>4} |{s} {s}\n", .{
                        Colors.dim,
                        current_line,
                        Colors.reset,
                        line,
                    });
                }
            } else {
                break;
            }
        }
    }
};

/// Convenience function to create a diagnostic with location information.
/// This is equivalent to calling `Diagnostic.init().withLocation()` but more concise.
pub fn createDiagnostic(
    severity: Severity,
    message: []const u8,
    file: []const u8,
    line: usize,
    column: usize,
) Diagnostic {
    return Diagnostic.init(severity, message)
        .withLocation(SourceLoc{
        .file = file,
        .line = line,
        .column = column,
    });
}

const testing = std.testing;

test "SourceLoc creation and access" {
    const loc = SourceLoc{
        .file = "test.zig",
        .line = 10,
        .column = 5,
    };

    try testing.expectEqualStrings("test.zig", loc.file);
    try testing.expectEqual(@as(usize, 10), loc.line);
    try testing.expectEqual(@as(usize, 5), loc.column);
}

test "Severity color and label mapping" {
    try testing.expectEqualStrings("\x1b[31m", Severity.err.color());
    try testing.expectEqualStrings("\x1b[33m", Severity.warn.color());
    try testing.expectEqualStrings("\x1b[34m", Severity.note.color());

    try testing.expectEqualStrings("error", Severity.err.label());
    try testing.expectEqualStrings("warning", Severity.warn.label());
    try testing.expectEqualStrings("note", Severity.note.label());
}

test "Diagnostic creation and initialization" {
    const diag = Diagnostic.init(.err, "test error message");

    try testing.expectEqual(Severity.err, diag.severity);
    try testing.expectEqualStrings("test error message", diag.message);
    try testing.expectEqual(@as(?SourceLoc, null), diag.location);
    try testing.expectEqual(@as(?[]const u8, null), diag.help);
}

test "Diagnostic fluent interface - withLocation" {
    const original = Diagnostic.init(.warn, "test warning");
    const loc = SourceLoc{
        .file = "example.zig",
        .line = 42,
        .column = 10,
    };

    const with_location = original.withLocation(loc);

    try testing.expectEqual(Severity.warn, with_location.severity);
    try testing.expectEqualStrings("test warning", with_location.message);
    try testing.expect(with_location.location != null);
    try testing.expectEqualStrings("example.zig", with_location.location.?.file);
    try testing.expectEqual(@as(usize, 42), with_location.location.?.line);
    try testing.expectEqual(@as(usize, 10), with_location.location.?.column);
}

test "Diagnostic fluent interface - withHelp" {
    const original = Diagnostic.init(.note, "test note");
    const with_help = original.withHelp("try using --verbose flag");

    try testing.expectEqual(Severity.note, with_help.severity);
    try testing.expectEqualStrings("test note", with_help.message);
    try testing.expect(with_help.help != null);
    try testing.expectEqualStrings("try using --verbose flag", with_help.help.?);
}

test "Diagnostic fluent interface - chaining" {
    const loc = SourceLoc{
        .file = "chain.zig",
        .line = 1,
        .column = 1,
    };

    const chained = Diagnostic.init(.err, "chained error")
        .withLocation(loc)
        .withHelp("check the documentation");

    try testing.expectEqual(Severity.err, chained.severity);
    try testing.expectEqualStrings("chained error", chained.message);
    try testing.expect(chained.location != null);
    try testing.expectEqualStrings("chain.zig", chained.location.?.file);
    try testing.expect(chained.help != null);
    try testing.expectEqualStrings("check the documentation", chained.help.?);
}

test "ErrorReporter initialization and deinitialization" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    try testing.expectEqual(@as(usize, 0), reporter.sources.count());
}

test "ErrorReporter addSource" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    const source_content = "const x = 42;\nconst y = x + 1;";
    try reporter.addSource("test.zig", source_content);

    try testing.expectEqual(@as(usize, 1), reporter.sources.count());

    const stored_content = reporter.sources.get("test.zig");
    try testing.expect(stored_content != null);
    try testing.expectEqualStrings(source_content, stored_content.?);
}

test "ErrorReporter addSource multiple files" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    try reporter.addSource("file1.zig", "content1");
    try reporter.addSource("file2.zig", "content2");
    try reporter.addSource("file3.zig", "content3");

    try testing.expectEqual(@as(usize, 3), reporter.sources.count());
    try testing.expectEqualStrings("content1", reporter.sources.get("file1.zig").?);
    try testing.expectEqualStrings("content2", reporter.sources.get("file2.zig").?);
    try testing.expectEqualStrings("content3", reporter.sources.get("file3.zig").?);
}

test "ErrorReporter addSource overwrites existing" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    try reporter.addSource("test.zig", "original content");
    try reporter.addSource("test.zig", "new content");

    try testing.expectEqual(@as(usize, 1), reporter.sources.count());
    try testing.expectEqualStrings("new content", reporter.sources.get("test.zig").?);
}

test "createDiagnostic convenience function" {
    const diag = createDiagnostic(.err, "syntax error", "main.zig", 15, 8);

    try testing.expectEqual(Severity.err, diag.severity);
    try testing.expectEqualStrings("syntax error", diag.message);
    try testing.expect(diag.location != null);
    try testing.expectEqualStrings("main.zig", diag.location.?.file);
    try testing.expectEqual(@as(usize, 15), diag.location.?.line);
    try testing.expectEqual(@as(usize, 8), diag.location.?.column);
}

test "ErrorReporter with sample diagnostics" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    const source =
        \\const std = @import("std");
        \\const print = std.debug.print;
        \\
        \\pub fn main() void {
        \\    const x = 42;
        \\    const y = x + "hello"; // Type mismatch error
        \\    print("Result: {}\n", .{y});
        \\}
    ;

    try reporter.addSource("example.zig", source);

    const diagnostics = [_]Diagnostic{
        createDiagnostic(.err, "type mismatch: cannot add integer and string", "example.zig", 6, 15),
        Diagnostic.init(.note, "consider converting the string to an integer")
            .withHelp("use std.fmt.parseInt() to convert strings to integers"),
        Diagnostic.init(.warn, "unused variable 'y'")
            .withLocation(SourceLoc{ .file = "example.zig", .line = 6, .column = 11 }),
    };

    try testing.expectEqual(@as(usize, 3), diagnostics.len);
    try testing.expectEqual(Severity.err, diagnostics[0].severity);
    try testing.expectEqual(Severity.note, diagnostics[1].severity);
    try testing.expectEqual(Severity.warn, diagnostics[2].severity);
}

test "ErrorReporter memory management" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    const test_cases = [_]struct { filename: []const u8, content: []const u8 }{
        .{ .filename = "file0.zig", .content = "const value0 = 0;" },
        .{ .filename = "file1.zig", .content = "const value1 = 10;" },
        .{ .filename = "file2.zig", .content = "const value2 = 20;" },
        .{ .filename = "file3.zig", .content = "const value3 = 30;" },
        .{ .filename = "file4.zig", .content = "const value4 = 40;" },
        .{ .filename = "file5.zig", .content = "const value5 = 50;" },
        .{ .filename = "file6.zig", .content = "const value6 = 60;" },
        .{ .filename = "file7.zig", .content = "const value7 = 70;" },
        .{ .filename = "file8.zig", .content = "const value8 = 80;" },
        .{ .filename = "file9.zig", .content = "const value9 = 90;" },
    };

    for (test_cases) |test_case| {
        try reporter.addSource(test_case.filename, test_case.content);
    }

    try testing.expectEqual(@as(usize, 10), reporter.sources.count());

    try testing.expect(reporter.sources.contains("file0.zig"));
    try testing.expect(reporter.sources.contains("file9.zig"));
    try testing.expect(!reporter.sources.contains("file10.zig"));

    try testing.expectEqualStrings("const value0 = 0;", reporter.sources.get("file0.zig").?);
    try testing.expectEqualStrings("const value9 = 90;", reporter.sources.get("file9.zig").?);
}

test "SourceLoc edge cases" {
    const loc_zero = SourceLoc{
        .file = "",
        .line = 0,
        .column = 0,
    };

    const loc_large = SourceLoc{
        .file = "very_long_filename_that_might_cause_issues.zig",
        .line = std.math.maxInt(usize),
        .column = std.math.maxInt(usize),
    };

    try testing.expectEqualStrings("", loc_zero.file);
    try testing.expectEqual(@as(usize, 0), loc_zero.line);
    try testing.expectEqual(@as(usize, 0), loc_zero.column);

    try testing.expectEqualStrings("very_long_filename_that_might_cause_issues.zig", loc_large.file);
    try testing.expectEqual(std.math.maxInt(usize), loc_large.line);
    try testing.expectEqual(std.math.maxInt(usize), loc_large.column);
}

test "Diagnostic with empty strings" {
    const diag = Diagnostic.init(.note, "")
        .withHelp("");

    try testing.expectEqualStrings("", diag.message);
    try testing.expectEqualStrings("", diag.help.?);
}

test "ErrorReporter with empty source" {
    var reporter = ErrorReporter.init(testing.allocator);
    defer reporter.deinit();

    try reporter.addSource("empty.zig", "");

    const stored = reporter.sources.get("empty.zig");
    try testing.expect(stored != null);
    try testing.expectEqualStrings("", stored.?);
}

test "ErrorReporter integration example" {
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

    const error_diag = createDiagnostic(.err, "expected '}', found end of file", "hello.zig", 10, 1);

    const warning_diag = Diagnostic.init(.warn, "variable 'greeting' is never used")
        .withLocation(SourceLoc{ .file = "hello.zig", .line = 6, .column = 22 })
        .withHelp("consider removing unused variables or prefixing with '_'");

    const note_diag = Diagnostic.init(.note, "compilation terminated due to previous error");

    try testing.expectEqual(Severity.err, error_diag.severity);
    try testing.expectEqual(Severity.warn, warning_diag.severity);
    try testing.expectEqual(Severity.note, note_diag.severity);

    try testing.expect(error_diag.location != null);
    try testing.expect(warning_diag.location != null);
    try testing.expect(warning_diag.help != null);
    try testing.expect(note_diag.location == null);
}
