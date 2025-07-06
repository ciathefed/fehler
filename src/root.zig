const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const OutputFormat = enum {
    fehler,
    gcc,
};

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

/// Represents a position in source code with line and column information.
pub const Position = struct {
    line: usize,
    column: usize,
};

/// Represents a range in source code with start and end positions.
pub const SourceRange = struct {
    file: []const u8,
    start: Position,
    end: Position,

    /// Creates a single-character range at the specified position.
    pub fn single(file: []const u8, line: usize, column: usize) SourceRange {
        return SourceRange{
            .file = file,
            .start = Position{ .line = line, .column = column },
            .end = Position{ .line = line, .column = column },
        };
    }

    /// Creates a range spanning from start to end positions.
    pub fn span(file: []const u8, start_line: usize, start_col: usize, end_line: usize, end_col: usize) SourceRange {
        return SourceRange{
            .file = file,
            .start = Position{ .line = start_line, .column = start_col },
            .end = Position{ .line = end_line, .column = end_col },
        };
    }

    /// Returns true if this range spans multiple lines.
    pub fn isMultiline(self: SourceRange) bool {
        return self.start.line != self.end.line;
    }

    /// Returns true if this range is a single character.
    pub fn isSingleChar(self: SourceRange) bool {
        return self.start.line == self.end.line and self.start.column == self.end.column;
    }

    /// Returns the length of the range on a single line (only valid for single-line ranges).
    pub fn length(self: SourceRange) usize {
        if (self.isMultiline()) return 0;
        return if (self.end.column >= self.start.column) self.end.column - self.start.column + 1 else 1;
    }
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

/// A diagnostic message with optional source range and help text.
/// This is the primary data structure for representing compiler errors, warnings, and notes.
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    range: ?SourceRange = null,
    help: ?[]const u8 = null,
    code: ?[]const u8 = null,
    url: ?[]const u8 = null,

    /// Creates a new diagnostic with the specified severity and message.
    /// Additional properties can be added using the fluent interface methods.
    pub fn init(severity: Severity, message: []const u8) Diagnostic {
        return Diagnostic{
            .severity = severity,
            .message = message,
        };
    }

    /// Returns a copy of this diagnostic with the specified source range.
    /// This method follows the builder pattern for fluent construction of diagnostics.
    pub fn withRange(self: Diagnostic, range: SourceRange) Diagnostic {
        var diag = self;
        diag.range = range;
        return diag;
    }

    /// Returns a copy of this diagnostic with a single-character range.
    /// This method follows the builder pattern for fluent construction of diagnostics.
    pub fn withLocation(self: Diagnostic, file: []const u8, line: usize, column: usize) Diagnostic {
        var diag = self;
        diag.range = SourceRange.single(file, line, column);
        return diag;
    }

    /// Returns a copy of this diagnostic with the specified help text.
    /// This method follows the builder pattern for fluent construction of diagnostics.
    pub fn withHelp(self: Diagnostic, help: []const u8) Diagnostic {
        var diag = self;
        diag.help = help;
        return diag;
    }

    /// Returns a copy of this diagnostic with the specified error code.
    /// The code can be used to look up error documentation.
    pub fn withCode(self: Diagnostic, code: []const u8) Diagnostic {
        var diag = self;
        diag.code = code;
        return diag;
    }

    /// Returns a copy of this diagnostic with the specified documentation URL.
    /// Useful for linking to online resources about this error.
    pub fn withUrl(self: Diagnostic, url: []const u8) Diagnostic {
        var diag = self;
        diag.url = url;
        return diag;
    }
};

/// A comprehensive error reporting system that manages source files and formats diagnostics.
/// This reporter can store multiple source files and display rich error messages with
/// source code context, similar to modern compiler error output.
pub const ErrorReporter = struct {
    allocator: Allocator,
    sources: std.StringHashMap([]const u8),
    output_format: OutputFormat,

    /// Initializes a new ErrorReporter with the given allocator.
    /// The reporter starts with no source files registered.
    pub fn init(allocator: Allocator, output_format: OutputFormat) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .sources = std.StringHashMap([]const u8).init(allocator),
            .output_format = output_format,
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
    /// If the diagnostic has a range and the source file is available,
    /// displays a source code snippet with the error range highlighted.
    pub fn report(self: *ErrorReporter, diagnostic: Diagnostic) void {
        switch (self.output_format) {
            .fehler => self.printFehler(diagnostic),
            .gcc => self.printGcc(diagnostic),
        }
    }

    fn printFehler(self: *ErrorReporter, diagnostic: Diagnostic) void {
        if (diagnostic.code) |code| {
            print("{s}{s}{s}[{s}]{s}: {s}\n", .{
                diagnostic.severity.color(),
                Colors.bold,
                diagnostic.severity.label(),
                code,
                Colors.reset,
                diagnostic.message,
            });
        } else {
            print("{s}{s}{s}{s}: {s}\n", .{
                diagnostic.severity.color(),
                Colors.bold,
                diagnostic.severity.label(),
                Colors.reset,
                diagnostic.message,
            });
        }

        if (diagnostic.range) |range| {
            if (range.isMultiline()) {
                print("  {s}{s}{s}:{}:{}{s}\n", .{
                    Colors.cyan,
                    Colors.bold,
                    range.file,
                    range.start.line,
                    range.start.column,
                    Colors.reset,
                });
            } else {
                print("  {s}{s}{s}:{}:{}{s}\n", .{
                    Colors.cyan,
                    Colors.bold,
                    range.file,
                    range.start.line,
                    range.start.column,
                    Colors.reset,
                });
            }

            const color = diagnostic.severity.color();
            self.printSourceSnippet(range, color) catch {};
        }

        if (diagnostic.help) |help| {
            print("  {s}{s}help{s}: {s}\n", .{
                Colors.cyan,
                Colors.bold,
                Colors.reset,
                help,
            });
        }

        if (diagnostic.url) |url| {
            print("  {s}{s}see{s}: {s}\n", .{
                Colors.blue,
                Colors.bold,
                Colors.reset,
                url,
            });
        }

        print("\n", .{});
    }

    fn printGcc(self: *ErrorReporter, diagnostic: Diagnostic) void {
        _ = self;
        const color = diagnostic.severity.color();
        if (diagnostic.range) |range| {
            print("{s}{s}:{d}:{d}: {s}{s}: {s}{s}{s}{s}\n", .{
                Colors.bold,
                range.file,
                range.start.line,
                range.start.column,
                color,
                diagnostic.severity.label(),
                Colors.reset,
                Colors.bold,
                diagnostic.message,
                Colors.reset,
            });
        } else {
            print("{s}{s}{s}: {s}{s}{s}{s}\n", .{
                Colors.bold,
                color,
                diagnostic.severity.label(),
                Colors.reset,
                Colors.bold,
                diagnostic.message,
                Colors.reset,
            });
        }
    }

    /// Reports multiple diagnostics in sequence.
    /// Each diagnostic is printed with the same formatting as `report()`.
    pub fn reportMany(self: *ErrorReporter, diagnostics: []const Diagnostic) void {
        for (diagnostics) |diagnostic| {
            self.report(diagnostic);
        }
    }

    /// Prints a source code snippet showing the context around a diagnostic range.
    /// Shows 2 lines before and after the error location, with the error range highlighted
    /// using carets (^) for single characters or tildes (~) for ranges.
    fn printSourceSnippet(self: *ErrorReporter, range: SourceRange, color: []const u8) !void {
        const source = self.sources.get(range.file) orelse return;

        var lines = std.mem.splitScalar(u8, source, '\n');
        var current_line: usize = 1;

        const context_start = if (range.start.line > 2) range.start.line - 2 else 1;
        const context_end = if (range.isMultiline()) range.end.line + 2 else range.start.line + 2;

        while (current_line < context_start and lines.next() != null) {
            current_line += 1;
        }

        while (current_line <= context_end) {
            if (lines.next()) |line| {
                defer current_line += 1;

                const line_num_width = 4;
                const is_error_line = current_line >= range.start.line and current_line <= range.end.line;

                if (is_error_line) {
                    print("  {s}{s}{d:>4} |{s} {s}\n", .{
                        Colors.red,
                        Colors.bold,
                        current_line,
                        Colors.reset,
                        line,
                    });

                    self.printUnderline(range, current_line, line_num_width, color);
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

    /// Prints the underline (carets or tildes) for a specific line in a range.
    fn printUnderline(
        self: *ErrorReporter,
        range: SourceRange,
        line_num: usize,
        line_num_width: usize,
        color: []const u8,
    ) void {
        _ = self;

        print("  {s}", .{color});

        var i: usize = 0;
        while (i < line_num_width + 1) : (i += 1) {
            print(" ", .{});
        }
        print("  ", .{});

        if (range.isMultiline()) {
            if (line_num == range.start.line) {
                i = 1;
                while (i < range.start.column) : (i += 1) {
                    print(" ", .{});
                }
                print("~", .{});
                i = range.start.column + 1;
                while (i <= 80) : (i += 1) {
                    print("~", .{});
                }
            } else if (line_num == range.end.line) {
                i = 1;
                while (i <= range.end.column) : (i += 1) {
                    print("~", .{});
                }
            } else {
                i = 0;
                while (i < 80) : (i += 1) {
                    print("~", .{});
                }
            }
        } else {
            i = 1;
            while (i < range.start.column) : (i += 1) {
                print(" ", .{});
            }

            if (range.isSingleChar()) {
                print("^", .{});
            } else {
                const range_length = range.length();
                var j: usize = 0;
                while (j < range_length) : (j += 1) {
                    print("~", .{});
                }
            }
        }

        print("{s}\n", .{Colors.reset});
    }
};

/// Convenience function to create a diagnostic with single-character location information.
pub fn createDiagnostic(
    severity: Severity,
    message: []const u8,
    file: []const u8,
    line: usize,
    column: usize,
) Diagnostic {
    return Diagnostic.init(severity, message)
        .withLocation(file, line, column);
}

/// Convenience function to create a diagnostic with range information.
pub fn createDiagnosticRange(
    severity: Severity,
    message: []const u8,
    file: []const u8,
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
) Diagnostic {
    return Diagnostic.init(severity, message)
        .withRange(SourceRange.span(file, start_line, start_col, end_line, end_col));
}

const testing = std.testing;

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
    const diag = createDiagnostic(.err, "syntax error", "main.zig", 15, 8);

    try testing.expectEqual(Severity.err, diag.severity);
    try testing.expectEqualStrings("syntax error", diag.message);
    try testing.expect(diag.range != null);
    try testing.expectEqualStrings("main.zig", diag.range.?.file);
    try testing.expectEqual(@as(usize, 15), diag.range.?.start.line);
    try testing.expectEqual(@as(usize, 8), diag.range.?.start.column);
    try testing.expect(diag.range.?.isSingleChar());
}

test "createDiagnosticRange convenience function" {
    const diag = createDiagnosticRange(.warn, "long identifier", "main.zig", 15, 8, 15, 25);

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
    var reporter = ErrorReporter.init(testing.allocator, .fehler);
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
        createDiagnosticRange(.err, "type mismatch: cannot add integer and string", "example.zig", 6, 15, 6, 23),
        createDiagnosticRange(.warn, "variable name is too long", "example.zig", 5, 11, 5, 35),
        createDiagnostic(.err, "undefined variable 'x'", "example.zig", 6, 15),
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
    var reporter = ErrorReporter.init(testing.allocator, .fehler);
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

    // Test different types of ranges
    const single_char = createDiagnostic(.err, "missing semicolon", "hello.zig", 10, 1);
    const short_range = createDiagnosticRange(.warn, "unused variable", "hello.zig", 6, 11, 6, 18);
    const long_range = createDiagnosticRange(.note, "function signature", "hello.zig", 3, 1, 3, 25);

    try testing.expect(single_char.range.?.isSingleChar());
    try testing.expect(!short_range.range.?.isSingleChar());
    try testing.expect(!short_range.range.?.isMultiline());
    try testing.expect(!long_range.range.?.isMultiline());
    try testing.expectEqual(@as(usize, 8), short_range.range.?.length());
    try testing.expectEqual(@as(usize, 25), long_range.range.?.length());
}
