import 'dart:math';

extension SplitByLineWidth on String {
  /// Divide el texto en varias 'lineas' cuyo tamaño se define con [lineWidth]
  List<String> splitByLineWidth(int lineWidth) {
    final numChunks = (this.length / lineWidth).ceil();
    List<String> chunks = [];
    for (int i = 0, o = 0; i < numChunks; i++, o += lineWidth) {
      chunks.add(this.substring(o, min(o + lineWidth, this.length)));
    }
    return chunks;
  }
}

extension Wrap on String {
  /// Ajusta las palabras del texto para que el mismo entre en varias lineas sin
  /// superar la longitud [lineWidth]
  List<String> wrap(int lineWidth) {
    assert(lineWidth >= 0);

    final List<String> splitText = this.split('\n');
    final List<String> result = <String>[];
    for (String line in splitText) {
      String trimmedText = line.trimLeft();
      final String leadingWhitespace =
          line.substring(0, line.length - trimmedText.length);
      List<String> notIndented;
      notIndented = _wrapTextAsLines(
        trimmedText,
        lineWidth - leadingWhitespace.length,
      );
      result.addAll(notIndented.map(
        (String line) {
          // Don't return any lines with just whitespace on them.
          if (line.isEmpty) {
            return '';
          }
          final String result = '$leadingWhitespace$line';
          return result;
        },
      ));
    }
    return result;
  }
}

// Used to represent a run of ANSI control sequences next to a visible
// character.
class _AnsiRun {
  _AnsiRun(this.original, this.character);

  String original;
  String character;
}

/// Wraps a block of text into lines no longer than [columnWidth], starting at the
/// [start] column, and returning the result as a list of strings.
///
/// Tries to split at whitespace, but if that's not good enough to keep it
/// under the limit, then splits in the middle of a word. Preserves embedded
/// newlines, but not indentation (it trims whitespace from each line).
///
/// If [columnWidth] is not specified, then the column width will be the width of the
/// terminal window by default. If the stdout is not a terminal window, then the
/// default will be [outputPreferences.wrapColumn].
///
/// If [outputPreferences.wrapText] is false, then the text will be returned
/// simply split at the newlines, but not wrapped. If [shouldWrap] is specified,
/// then it overrides the [outputPreferences.wrapText] setting.
List<String> _wrapTextAsLines(String text, int columnWidth, {int start = 0}) {
  assert(columnWidth >= 0);
  assert(start >= 0);

  /// Returns true if the code unit at [index] in [text] is a whitespace
  /// character.
  ///
  /// Based on: https://en.wikipedia.org/wiki/Whitespace_character#Unicode
  bool isWhitespace(_AnsiRun run) {
    final int rune =
        run.character.isNotEmpty ? run.character.codeUnitAt(0) : 0x0;
    return rune >= 0x0009 && rune <= 0x000D ||
        rune == 0x0020 ||
        rune == 0x0085 ||
        rune == 0x1680 ||
        rune == 0x180E ||
        rune >= 0x2000 && rune <= 0x200A ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202F ||
        rune == 0x205F ||
        rune == 0x3000 ||
        rune == 0xFEFF;
  }

  // Splits a string so that the resulting list has the same number of elements
  // as there are visible characters in the string, but elements may include one
  // or more adjacent ANSI sequences. Joining the list elements again will
  // reconstitute the original string. This is useful for manipulating "visible"
  // characters in the presence of ANSI control codes.
  List<_AnsiRun> splitWithCodes(String input) {
    final RegExp characterOrCode =
        RegExp('(\u001b\[[0-9;]*m|.)', multiLine: true);
    List<_AnsiRun> result = <_AnsiRun>[];
    final StringBuffer current = StringBuffer();
    for (Match match in characterOrCode.allMatches(input)) {
      current.write(match[0]);
      final char = match[0];
      if (char != null) {
        if (char.length < 4) {
          // This is a regular character, write it out.
          result.add(_AnsiRun(current.toString(), char));
          current.clear();
        }
      }
    }
    // If there's something accumulated, then it must be an ANSI sequence, so
    // add it to the end of the last entry so that we don't lose it.
    if (current.isNotEmpty) {
      if (result.isNotEmpty) {
        result.last.original += current.toString();
      } else {
        // If there is nothing in the string besides control codes, then just
        // return them as the only entry.
        result = <_AnsiRun>[_AnsiRun(current.toString(), '')];
      }
    }
    return result;
  }

  String joinRun(List<_AnsiRun> list, int start, [int? end]) {
    return list
        .sublist(start, end)
        .map<String>((_AnsiRun run) => run.original)
        .join()
        .trim();
  }

  final List<String> result = <String>[];
  final int effectiveLength = columnWidth - start;
  for (String line in text.split('\n')) {
    // If the line is short enough, even with ANSI codes, then we can just add
    // add it and move on.
    if (line.length <= effectiveLength) {
      result.add(line);
      continue;
    }
    final List<_AnsiRun> splitLine = splitWithCodes(line);
    if (splitLine.length <= effectiveLength) {
      result.add(line);
      continue;
    }

    int currentLineStart = 0;
    int? lastWhitespace;
    // Find the start of the current line.
    for (int index = 0; index < splitLine.length; ++index) {
      if (splitLine[index].character.isNotEmpty &&
          isWhitespace(splitLine[index])) {
        lastWhitespace = index;
      }

      if (index - currentLineStart >= effectiveLength) {
        // Back up to the last whitespace, unless there wasn't any, in which
        // case we just split where we are.
        if (lastWhitespace != null) {
          index = lastWhitespace;
        }

        result.add(joinRun(splitLine, currentLineStart, index));

        // Skip any intervening whitespace.
        while (index < splitLine.length && isWhitespace(splitLine[index])) {
          index++;
        }

        currentLineStart = index;
        lastWhitespace = null;
      }
    }
    result.add(joinRun(splitLine, currentLineStart));
  }
  return result;
}
