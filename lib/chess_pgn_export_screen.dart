import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'chess_models.dart';
import 'chess_pgn_service.dart';

class ChessPgnExportScreen extends StatefulWidget {
  const ChessPgnExportScreen({super.key});

  @override
  State<ChessPgnExportScreen> createState() => _ChessPgnExportScreenState();
}

class _ChessPgnExportScreenState extends State<ChessPgnExportScreen> {
  ChessExtraction? _extraction;
  String? _report;
  bool _includeComments = true;
  bool _fixInvalidMoves = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess PGN Exporter'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.grey[900],
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
            'Load extraction JSON',
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
          _buildOptionsCard(),
          _buildGamesList(),
          if (_report != null) _buildReportCard(),
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
                  '${_extraction!.totalGames} games',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_extraction!.totalMoves} moves',
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
                  '✓ Extraction v${_extraction!.version}',
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

  Widget _buildOptionsCard() {
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
              'Export options',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('Include comments'),
              value: _includeComments,
              onChanged: (v) => setState(() => _includeComments = v ?? true),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('Fix invalid moves'),
              value: _fixInvalidMoves,
              onChanged: (v) => setState(() => _fixInvalidMoves = v ?? true),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _generateReport,
                    icon: const Icon(Icons.assessment),
                    label: const Text('Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportMultipleGames,
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export all'),
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

  Widget _buildGamesList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Extracted games',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _extraction!.games.length,
            itemBuilder: (context, index) {
              final game = _extraction!.games[index];
              return _buildGameCard(game, index + 1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(ChessGame game, int number) {
    final issues = ChessPgnService.validateGame(game);
    final hasErrors = issues.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasErrors ? Colors.red[300]! : Colors.green[300]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2),
        ],
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                number.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${game.white} - ${game.black}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${game.moves.length} moves | Page ${game.page}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasErrors ? Colors.red[100] : Colors.green[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hasErrors ? '⚠ ${issues.length}' : '✓',
                style: TextStyle(
                  color: hasErrors ? Colors.red[700] : Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (game.date != null) _buildMetaRow('Date', game.date!),
                if (game.event != null) _buildMetaRow('Event', game.event!),
                if (game.site != null) _buildMetaRow('Site', game.site!),
                const SizedBox(height: 12),
                if (hasErrors) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Issues detected:',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...issues.map(
                          (issue) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $issue',
                              style: TextStyle(
                                color: Colors.red[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton.icon(
                  onPressed: () => _exportSingleGame(game, number),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('Export this game'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildReportCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Extraction report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _report!,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SharePlus.instance.share(ShareParams(text: _report!));
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _report = null);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
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

      if (result != null) {
        final filePath = result.files.single.path!;
        await _loadJsonFile(filePath);
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
      _extraction = await ChessPgnService.loadFromFile(filePath);
      setState(() {});
      _showSuccess('${_extraction!.totalGames} games loaded');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadJsonString(String jsonString) async {
    setState(() => _isLoading = true);
    try {
      _extraction = await ChessPgnService.loadFromJson(jsonString);
      setState(() {});
      _showSuccess('${_extraction!.totalGames} games loaded');
    } catch (e) {
      _showError('JSON error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _report = ChessPgnService.generateReport(_extraction!);
    });
  }

  Future<void> _exportMultipleGames() async {
    setState(() => _isLoading = true);
    try {
      // Use directory_picker or create in app directory
      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${appDir.path}/Chess_PGN_Export');

      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final files = await ChessPgnService.exportIndividualGames(
        _extraction!,
        outputDir.path,
        includeComments: _includeComments,
        fixInvalidMoves: _fixInvalidMoves,
      );

      _showSuccess('${files.length} PGN files created in:\n${outputDir.path}');

      // Optional: Share the directory
      if (files.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(files[0].path)],
            subject: 'Chess Games - PGN Files',
          ),
        );
      }
    } catch (e) {
      _showError('Export error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportSingleGame(ChessGame game, int number) async {
    try {
      final pgn = game.toPgn(includeComments: _includeComments);
      SharePlus.instance.share(
        ShareParams(text: pgn, subject: 'Chess Game #$number'),
      );
    } catch (e) {
      _showError('Error: $e');
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
