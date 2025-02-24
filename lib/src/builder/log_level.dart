// Copyright (c) 2025, rainyl. All rights reserved. Use of this source code is governed by a
// Apache-2.0 license that can be found in the LICENSE file.

// ERROR|WARNING|NOTICE|STATUS|VERBOSE|DEBUG|TRACE
enum LogLevel {
  ERROR("ERROR"),
  WARNING("WARNING"),
  NOTICE("NOTICE"),
  STATUS("STATUS"),
  VERBOSE("VERBOSE"),
  DEBUG("DEBUG"),
  TRACE("TRACE");

  final String value;
  const LogLevel(this.value);

  static LogLevel fromValue(String value) => switch (value) {
        "ERROR" => ERROR,
        "WARNING" => WARNING,
        "NOTICE" => NOTICE,
        "STATUS" => STATUS,
        "VERBOSE" => VERBOSE,
        "DEBUG" => DEBUG,
        "TRACE" => TRACE,
        _ => throw ArgumentError("Unknown value for LogLevel: $value"),
      };
}
