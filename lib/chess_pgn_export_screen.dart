import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'chess_models.dart';
import 'chess_pgn_service.dart';
import 'pgn_parser.dart';

class OcrToPgnScreen extends StatefulWidget {
  const OcrToPgnScreen({super.key});

  @override
  State<OcrToPgnScreen> createState() => _OcrToPgnScreenState();
}

class _OcrToPgnScreenState extends State<OcrToPgnScreen> {
  OcrExtraction? _extraction;
  String? _report;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess OCR to PGN'),
        centerTitle: true,
        elevation: 2,
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        leading: _extraction != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _extraction = null;
                    _report = null;
                  });
                },
              )
            : null,
      ),
      body: _extraction == null ? _buildLoadingScreen() : _buildMainScreen(),
      backgroundColor: Colors.grey[100],
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.games, color: Colors.white, size: 50),
          ),
          const SizedBox(height: 24),
          const Text(
            'Load OCR JSON data',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _pickJsonFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select JSON file'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[900],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pasteLiveJson,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste JSON'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainScreen() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(),
          _buildAnalysisCard(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFragmentsPreview()),
              Expanded(child: _buildReportPanel()),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_extraction!.totalPages} pages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_extraction!.totalFragments} fragments',
                  style: TextStyle(color: Colors.grey[400], fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(
                  '✓ OCR v${_extraction!.version}',
                  Colors.green[700]!,
                ),
                _buildChip(
                  'Valid',
                  _extraction!.isValid()
                      ? Colors.green[700]!
                      : Colors.red[700]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildAnalysisCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis tools',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _generatePgn,
                    icon: const Icon(Icons.games),
                    label: const Text('Generate PGN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFragmentsPreview() {
    if (_extraction!.pages.isEmpty) return const SizedBox.shrink();

    final firstPage = _extraction!.pages[0];
    final sampleFragments = firstPage.fragments.take(5).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sample fragments (Page 1)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...sampleFragments.map((frag) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"${frag.text}"',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Pos: (${frag.x}, ${frag.y}) | Size: ${frag.width}x${frag.height} | Confidence: ${frag.confidence}%',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (firstPage.fragments.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... and ${firstPage.fragments.length - 5} more fragments on this page',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PGN Analysis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_report != null)
              SizedBox(
                height: 200,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _report!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Center(
                    child: Text(
                      'Click "Generate Report" to see analysis',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _generateReport();
                        },
                  icon: const Icon(Icons.receipt),
                  label: const Text('Generate Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 8),
                if (_report != null)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveReport,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Actions
  Future<void> _pickJsonFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.single.path;
        if (filePath != null) {
          await _loadJsonFile(filePath);
        }
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Future<void> _pasteLiveJson() async {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste JSON'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Paste JSON here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _loadJsonString(controller.text);
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadJsonFile(String filePath) async {
    setState(() => _isLoading = true);
    try {
      _extraction = await OcrToPgnService.loadFromFile(filePath);
      setState(() {});
      _showSuccess('${_extraction!.totalPages} pages loaded');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadJsonString(String jsonString) async {
    setState(() => _isLoading = true);
    try {
      _extraction = await OcrToPgnService.loadFromJson(jsonString);
      setState(() {});
      _showSuccess('${_extraction!.totalPages} pages loaded');
    } catch (e) {
      _showError('JSON error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateReport() async {
    if (_extraction == null) return;

    setState(() => _isLoading = true);
    try {
      setState(() {
        _report = AdvancedPgnParser.generateAnalysisReport(_extraction!);
      });
    } catch (e) {
      _showError('Report error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveReport() async {
    if (_report == null) return;

    try {
      final fileName =
          'extraction_report_${DateTime.now().millisecondsSinceEpoch}.txt';

      final result = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(_report!);
        _showSuccess('Report saved: ${file.path}');
      }
    } catch (e) {
      _showError('Save error: $e');
    }
  }

  Future<void> _generatePgn() async {
    if (_extraction == null) return;

    setState(() => _isLoading = true);
    try {
      // Use async parser to avoid blocking UI
      final pgn = await AdvancedPgnParser.generatePgnAsync(_extraction!);
      final analysis = AdvancedPgnParser.generateAnalysisReport(_extraction!);

      // Show PGN dialog with save option
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Generated PGN'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Analysis:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  analysis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
                ),
                const SizedBox(height: 16),
                const Text(
                  'PGN:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  pgn,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                SharePlus.instance.share(ShareParams(text: pgn));
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _savePgnFile(pgn);
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('PGN generation error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePgnFile(String pgnContent) async {
    try {
      // Let user choose save location
      final fileName =
          'chess_game_${DateTime.now().millisecondsSinceEpoch}.pgn';

      final result = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pgn'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(pgnContent);

        _showSuccess('PGN saved: ${file.path}');
      } else {
        _showSuccess('Save cancelled');
      }
    } catch (e) {
      _showError('Save error: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green[700]),
    );
  }
}
