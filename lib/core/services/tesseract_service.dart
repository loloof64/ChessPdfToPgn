import 'dart:io';

enum PageSegMode {
  singleColumn(4), // single column, variable sizes
  singleBlock(6), // uniform text block — default for a book
  sparseText(11); // sparse text

  final int value;
  const PageSegMode(this.value);
}

class TesseractService {
  final PageSegMode psm;
  final String tessLang;

  const TesseractService({
    required this.tessLang,
    this.psm = PageSegMode.singleBlock,
  });

  /// Checks that Tesseract is installed and returns its version.
  /// Returns null if not found in PATH.
  static Future<String?> detectVersion() async {
    try {
      final result = await Process.run('tesseract', ['--version']);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).split('\n').first.trim();
    } on ProcessException {
      return null;
    }
  }

  /// Checks which tessdata languages are missing from [needed].
  static Future<List<String>> missingLangs(List<String> needed) async {
    final result = await Process.run('tesseract', ['--list-langs']);
    final available = (result.stdout as String)
        .split('\n')
        .skip(1)
        .map((l) => l.trim())
        .toSet();
    return needed.where((l) => !available.contains(l)).toList();
  }

  /// Extracts raw text from a preprocessed image.
  Future<String> extractText(String imagePath) async {
    final args = [
      imagePath,
      'stdout',
      '-l',
      tessLang,
      '--psm',
      psm.value.toString(),
      '--oem',
      '1',
      'txt',
      '-c',
      'preserve_interword_spaces=1',
    ];

    final result = await Process.run('tesseract', args);
    if (result.exitCode != 0) {
      throw TesseractException(
        exitCode: result.exitCode,
        stderr: result.stderr as String,
        args: args,
      );
    }
    return (result.stdout as String).trim();
  }

  /// Extracts words with their confidence score (useful for correction).
  Future<List<TesseractWord>> extractWords(String imagePath) async {
    final args = [
      imagePath,
      'stdout',
      '-l',
      tessLang,
      '--psm',
      psm.value.toString(),
      '--oem',
      '1',
      'tsv',
    ];

    final result = await Process.run('tesseract', args);
    if (result.exitCode != 0) {
      throw TesseractException(
        exitCode: result.exitCode,
        stderr: result.stderr as String,
        args: args,
      );
    }
    return _parseTsv(result.stdout as String);
  }

  List<TesseractWord> _parseTsv(String tsv) {
    final lines = tsv.trim().split('\n');
    if (lines.length < 2) return [];
    // header: level page_num block_num par_num line_num word_num
    //         left top width height conf text
    return lines
        .skip(1)
        .where((l) => l.isNotEmpty)
        .map((line) {
          final cols = line.split('\t');
          if (cols.length < 12) return null;
          final conf = double.tryParse(cols[10]) ?? -1;
          if (conf < 0) return null; // non-word line (block, paragraph…)
          return TesseractWord(
            text: cols[11],
            confidence: conf,
            left: int.tryParse(cols[6]) ?? 0,
            top: int.tryParse(cols[7]) ?? 0,
            width: int.tryParse(cols[8]) ?? 0,
            height: int.tryParse(cols[9]) ?? 0,
          );
        })
        .whereType<TesseractWord>()
        .toList();
  }
}

class TesseractWord {
  final String text;
  final double confidence;
  final int left, top, width, height;

  const TesseractWord({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  bool get isLowConfidence => confidence < 70;
}

class TesseractException implements Exception {
  final int exitCode;
  final String stderr;
  final List<String> args;

  const TesseractException({
    required this.exitCode,
    required this.stderr,
    required this.args,
  });

  @override
  String toString() =>
      'TesseractException (exit $exitCode)\n'
      'args: ${args.join(' ')}\n'
      'stderr: $stderr';
}
