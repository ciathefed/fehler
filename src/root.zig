const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const OutputFormat = enum {
    fehler,
    gcc,
    msvc,
};

/// ANSI color codes and formatting constants for terminal output.
const Colors = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
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
    fatal,
    err,
    warn,
    note,
    todo,
    unimplemented,

    /// Returns the ANSI color code associated with this severity level.
    pub fn color(self: Severity) []const u8 {
        return switch (self) {
            .fatal => Colors.red,
            .err => Colors.red,
            .warn => Colors.yellow,
            .note => Colors.blue,
            .todo => Colors.magenta,
            .unimplemented => Colors.cyan,
        };
    }

    /// Returns the human-readable label for this severity level.
    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .fatal => "fatal",
            .err => "error",
            .warn => "warning",
            .note => "note",
            .todo => "todo",
            .unimplemented => "unimplemented",
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
    format: OutputFormat,

    /// Initializes a new ErrorReporter with the given allocator.
    /// The reporter starts with no source files registered.
    /// Uses the default output format (Fehler).
    pub fn init(allocator: Allocator) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .sources = std.StringHashMap([]const u8).init(allocator),
            .format = .fehler,
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

    /// Returns a copy of this reporter with the specified output format.
    /// Allows changing the format without breaking API compatibility.
    pub fn withFormat(self: ErrorReporter, format: OutputFormat) ErrorReporter {
        var reporter = self;
        reporter.format = format;
        return reporter;
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
        switch (self.format) {
            .fehler => self.printFehler(diagnostic),
            .gcc => self.printGcc(diagnostic),
            .msvc => self.printMsvc(diagnostic),
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

    fn printMsvc(self: *ErrorReporter, diagnostic: Diagnostic) void {
        _ = self;
        if (diagnostic.range) |range| {
            const code = diagnostic.code orelse "";
            print("{s}({d},{d}): {s} {s}: {s}\n", .{
                range.file,
                range.start.line,
                range.start.column,
                diagnostic.severity.label(),
                code,
                diagnostic.message,
            });
        } else {
            print("{s}: {s}\n", .{ diagnostic.severity.label(), diagnostic.message });
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

test {
    _ = @import("tests.zig");
}
