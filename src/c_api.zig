const std = @import("std");
const fehler = @import("root.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const c_allocator = gpa.allocator();

pub const FehlerReporter = opaque {};

pub const FehlerDiagnostic = opaque {};

pub const FehlerSeverity = enum(c_int) {
    fatal = 0,
    err = 1,
    warn = 2,
    note = 3,
    todo = 4,
    unimplemented = 5,
};

pub const FehlerFormat = enum(c_int) {
    fehler = 0,
    gcc = 1,
    msvc = 2,
};

pub const FehlerPosition = extern struct {
    line: usize,
    column: usize,
};

pub const FehlerSourceRange = extern struct {
    file: [*:0]const u8,
    start: FehlerPosition,
    end: FehlerPosition,
};

export fn fehler_reporter_create() ?*FehlerReporter {
    const reporter = c_allocator.create(fehler.ErrorReporter) catch return null;
    reporter.* = fehler.ErrorReporter.init(c_allocator);
    return @ptrCast(reporter);
}

export fn fehler_reporter_destroy(reporter: *FehlerReporter) void {
    const r: *fehler.ErrorReporter = @ptrCast(@alignCast(reporter));
    r.deinit();
    c_allocator.destroy(r);
}

export fn fehler_reporter_set_format(reporter: *FehlerReporter, format: FehlerFormat) void {
    const r: *fehler.ErrorReporter = @ptrCast(@alignCast(reporter));
    r.format = switch (format) {
        .fehler => .fehler,
        .gcc => .gcc,
        .msvc => .msvc,
    };
}

export fn fehler_reporter_add_source(
    reporter: *FehlerReporter,
    filename: [*:0]const u8,
    content: [*:0]const u8,
) c_int {
    const r: *fehler.ErrorReporter = @ptrCast(@alignCast(reporter));
    const filename_slice = std.mem.span(filename);
    const content_slice = std.mem.span(content);
    r.addSource(filename_slice, content_slice) catch return -1;
    return 0;
}

export fn fehler_reporter_report(reporter: *FehlerReporter, diagnostic: *FehlerDiagnostic) void {
    const r: *fehler.ErrorReporter = @ptrCast(@alignCast(reporter));
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    r.report(d.*);
}

export fn fehler_diagnostic_create(
    severity: FehlerSeverity,
    message: [*:0]const u8,
) ?*FehlerDiagnostic {
    const diag = c_allocator.create(fehler.Diagnostic) catch return null;
    const message_slice = std.mem.span(message);
    const owned_message = c_allocator.dupe(u8, message_slice) catch {
        c_allocator.destroy(diag);
        return null;
    };

    const sev = switch (severity) {
        .fatal => fehler.Severity.fatal,
        .err => fehler.Severity.err,
        .warn => fehler.Severity.warn,
        .note => fehler.Severity.note,
        .todo => fehler.Severity.todo,
        .unimplemented => fehler.Severity.unimplemented,
    };

    diag.* = fehler.Diagnostic.init(sev, owned_message);
    return @ptrCast(diag);
}

export fn fehler_diagnostic_destroy(diagnostic: *FehlerDiagnostic) void {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    c_allocator.free(d.message);
    if (d.help) |help| c_allocator.free(help);
    if (d.code) |code| c_allocator.free(code);
    if (d.url) |url| c_allocator.free(url);
    c_allocator.destroy(d);
}

export fn fehler_diagnostic_set_location(
    diagnostic: *FehlerDiagnostic,
    file: [*:0]const u8,
    line: usize,
    column: usize,
) c_int {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    const file_slice = std.mem.span(file);
    d.range = fehler.SourceRange.single(file_slice, line, column);
    return 0;
}

export fn fehler_diagnostic_set_range(
    diagnostic: *FehlerDiagnostic,
    file: [*:0]const u8,
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
) c_int {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    const file_slice = std.mem.span(file);
    d.range = fehler.SourceRange.span(file_slice, start_line, start_col, end_line, end_col);
    return 0;
}

export fn fehler_diagnostic_set_help(
    diagnostic: *FehlerDiagnostic,
    help: [*:0]const u8,
) c_int {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    const help_slice = std.mem.span(help);
    const owned_help = c_allocator.dupe(u8, help_slice) catch return -1;
    if (d.help) |old_help| c_allocator.free(old_help);
    d.help = owned_help;
    return 0;
}

export fn fehler_diagnostic_set_code(
    diagnostic: *FehlerDiagnostic,
    code: [*:0]const u8,
) c_int {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    const code_slice = std.mem.span(code);
    const owned_code = c_allocator.dupe(u8, code_slice) catch return -1;
    if (d.code) |old_code| c_allocator.free(old_code);
    d.code = owned_code;
    return 0;
}

export fn fehler_diagnostic_set_url(
    diagnostic: *FehlerDiagnostic,
    url: [*:0]const u8,
) c_int {
    const d: *fehler.Diagnostic = @ptrCast(@alignCast(diagnostic));
    const url_slice = std.mem.span(url);
    const owned_url = c_allocator.dupe(u8, url_slice) catch return -1;
    if (d.url) |old_url| c_allocator.free(old_url);
    d.url = owned_url;
    return 0;
}

export fn fehler_report_simple(
    reporter: *FehlerReporter,
    severity: FehlerSeverity,
    message: [*:0]const u8,
    file: [*:0]const u8,
    line: usize,
    column: usize,
) void {
    const diag = fehler_diagnostic_create(severity, message) orelse return;
    defer fehler_diagnostic_destroy(diag);
    _ = fehler_diagnostic_set_location(diag, file, line, column);
    fehler_reporter_report(reporter, diag);
}

export fn fehler_report_range(
    reporter: *FehlerReporter,
    severity: FehlerSeverity,
    message: [*:0]const u8,
    file: [*:0]const u8,
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
) void {
    const diag = fehler_diagnostic_create(severity, message) orelse return;
    defer fehler_diagnostic_destroy(diag);
    _ = fehler_diagnostic_set_range(diag, file, start_line, start_col, end_line, end_col);
    fehler_reporter_report(reporter, diag);
}

export fn fehler_version() [*:0]const u8 {
    return "0.6.1";
}
