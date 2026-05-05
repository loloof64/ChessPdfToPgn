import 'package:flutter/material.dart';
import '../../core/models/game_extraction_config.dart';

/// Screen displayed before any extraction, and accessible via Settings button.
/// Lets the user configure notation locale, figurine mode, and comment style.
class ConfigScreen extends StatefulWidget {
  final void Function(GameExtractionConfig config) onConfirmed;
  final GameExtractionConfig? initialConfig;

  const ConfigScreen({
    required this.onConfirmed,
    this.initialConfig,
    super.key,
  });

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late NotationLocale _locale;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _locale = initial?.locale ?? NotationLocale.english;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extraction settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------------------------
            // Notation locale
            // ----------------------------------------------------------------
            const _SectionLabel('Piece notation language'),
            const SizedBox(height: 8),
            DropdownButtonFormField<NotationLocale>(
              initialValue: _locale,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: NotationLocale.values.map((locale) {
                return DropdownMenuItem(
                  value: locale,
                  child: Text(_localeLabel(locale)),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _locale = value);
              },
            ),

            const SizedBox(height: 24),
            const Spacer(),

            // ----------------------------------------------------------------
            // Confirm button
            // ----------------------------------------------------------------
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirm,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    widget.onConfirmed(GameExtractionConfig(locale: _locale));
  }

  String _localeLabel(NotationLocale locale) => switch (locale) {
    NotationLocale.english => 'English  (K Q R B N)',
    NotationLocale.french => 'French   (R D T F C)',
    NotationLocale.spanish => 'Spanish  (R D T A C)',
    NotationLocale.german => 'German   (K D T L S)',
    NotationLocale.russian => 'Russian  (Кр Ф Л С К)',
    NotationLocale.dutch => 'Dutch    (K D T L P)',
  };
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
