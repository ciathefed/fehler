/**
 * Fehler - Diagnostic Reporting Library
 *
 * A rich, colorful compiler-style diagnostic reporting library
 * with support for source ranges, multiple output formats, and SARIF export.
 *
 * Version: 0.6.1
 * License: MIT
 */

#ifndef FEHLER_H
#define FEHLER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/**
 * Opaque handle to an ErrorReporter instance.
 * Manages source files and formats diagnostics for output.
 */
typedef struct FehlerReporter FehlerReporter;

/**
 * Opaque handle to a Diagnostic instance.
 * Represents a single error, warning, or note with optional source location.
 */
typedef struct FehlerDiagnostic FehlerDiagnostic;

/**
 * Severity levels for diagnostics.
 * Determines the color and label used when displaying the diagnostic.
 */
typedef enum FehlerSeverity {
    FEHLER_SEVERITY_FATAL = 0,
    FEHLER_SEVERITY_ERROR = 1,
    FEHLER_SEVERITY_WARN = 2,
    FEHLER_SEVERITY_NOTE = 3,
    FEHLER_SEVERITY_TODO = 4,
    FEHLER_SEVERITY_UNIMPLEMENTED = 5,
} FehlerSeverity;

/**
 * Output format styles for diagnostics.
 */
typedef enum FehlerFormat {
    FEHLER_FORMAT_FEHLER = 0,
    FEHLER_FORMAT_GCC = 1,
    FEHLER_FORMAT_MSVC = 2,
} FehlerFormat;

/**
 * Represents a position in source code.
 */
typedef struct FehlerPosition {
    size_t line;
    size_t column;
} FehlerPosition;

/**
 * Represents a range in source code.
 */
typedef struct FehlerSourceRange {
    const char* file;
    FehlerPosition start;
    FehlerPosition end;
} FehlerSourceRange;

/**
 * Creates a new ErrorReporter instance.
 */
FehlerReporter* fehler_reporter_create(void);

/**
 * Destroys an ErrorReporter instance and frees all associated memory.
 */
void fehler_reporter_destroy(FehlerReporter* reporter);

/**
 * Sets the output format for the reporter.
 */
void fehler_reporter_set_format(FehlerReporter* reporter, FehlerFormat format);

/**
 * Adds a source file to the reporter for reference in diagnostics.
 * The content is copied and owned by the reporter.
 */
int fehler_reporter_add_source(FehlerReporter* reporter, const char* filename, const char* content);

/**
 * Reports a diagnostic to stdout with formatting.
 */
void fehler_reporter_report(FehlerReporter* reporter, FehlerDiagnostic* diagnostic);

/**
 * Creates a new Diagnostic instance.
 * The message string is copied and owned by the diagnostic.
 */
FehlerDiagnostic* fehler_diagnostic_create(FehlerSeverity severity, const char* message);

/**
 * Destroys a Diagnostic instance and frees all associated memory.
 */
void fehler_diagnostic_destroy(FehlerDiagnostic* diagnostic);

/**
 * Sets a single-character location for the diagnostic.
 */
int fehler_diagnostic_set_location(FehlerDiagnostic* diagnostic, const char* file, size_t line, size_t column);

/**
 * Sets a source range for the diagnostic.
 */
int fehler_diagnostic_set_range(FehlerDiagnostic* diagnostic, const char* file, size_t start_line, size_t start_col, size_t end_line, size_t end_col);

/**
 * Sets help text for the diagnostic.
 * The help string is copied and owned by the diagnostic.
 */
int fehler_diagnostic_set_help(FehlerDiagnostic* diagnostic, const char* help);

/**
 * Sets an error code for the diagnostic.
 * The code string is copied and owned by the diagnostic.
 */
int fehler_diagnostic_set_code(FehlerDiagnostic* diagnostic, const char* code);

/**
 * Sets a documentation URL for the diagnostic.
 * The URL string is copied and owned by the diagnostic.
 */
int fehler_diagnostic_set_url(FehlerDiagnostic* diagnostic, const char* url);

/**
 * Quick helper to create and report a simple diagnostic with location.
 * Handles creation, configuration, reporting, and cleanup automatically.
 */
void fehler_report_simple(FehlerReporter* reporter, FehlerSeverity severity, const char* message, const char* file, size_t line, size_t column);

/**
 * Quick helper to create and report a diagnostic with a range.
 * Handles creation, configuration, reporting, and cleanup automatically.
 */
void fehler_report_range(FehlerReporter* reporter, FehlerSeverity severity, const char* message, const char* file, size_t start_line, size_t start_col, size_t end_line, size_t end_col);

// ============================================================================
// Version and Info
// ============================================================================

/**
 * Returns the version string of the Fehler library.
 */
const char* fehler_version(void);

/**
 * Checks if color output is supported.
 */
int fehler_has_color_support(void);

#ifdef __cplusplus
}
#endif

#endif // FEHLER_H
