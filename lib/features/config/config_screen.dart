import 'package:flutter/material.dart';
import '../../core/models/game_extraction_config.dart';

/// Screen displayed before any extraction.
/// Lets the user configure notation locale, figurine mode, and comment style.
class ConfigScreen extends StatefulWidget {
  /// Called when the user confirms the configuration.
  final void Function(GameExtractionConfig config) onConfirmed;

  const ConfigScreen({required this.onConfirmed, super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  NotationLocale _locale = NotationLocale.english;
  bool _usesFigurine = false;
  CommentStyle _commentStyle = CommentStyle.braces;

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

            // ----------------------------------------------------------------
            // Figurine mode
            // ----------------------------------------------------------------
            const _SectionLabel('Piece symbol style'),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _usesFigurine,
              onChanged: (v) {
                if (v != null) setState(() => _usesFigurine = v);
              },
              child: Column(
                children: [
                  _RadioTile<bool>(
                    value: false,
                    label: 'Letters  (e.g. Nf3, Cf3, Sf3)',
                  ),
                  _RadioTile<bool>(value: true, label: 'Figurines  (e.g. ♘f3)'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ----------------------------------------------------------------
            // Comment style
            // ----------------------------------------------------------------
            const _SectionLabel('Comment delimiter style'),
            const SizedBox(height: 8),
            RadioGroup<CommentStyle>(
              groupValue: _commentStyle,
              onChanged: (v) {
                if (v != null) setState(() => _commentStyle = v);
              },
              child: Column(
                children: [
                  _RadioTile<CommentStyle>(
                    value: CommentStyle.braces,
                    label: 'Braces  { comment }',
                  ),
                  _RadioTile<CommentStyle>(
                    value: CommentStyle.parentheses,
                    label: 'Parentheses  ( comment )',
                  ),
                  _RadioTile<CommentStyle>(
                    value: CommentStyle.mixed,
                    label: 'Mixed  — auto-detect',
                  ),
                ],
              ),
            ),

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
    widget.onConfirmed(
      GameExtractionConfig(
        locale: _locale,
        usesFigurine: _usesFigurine,
        commentStyle: _commentStyle,
      ),
    );
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

class _RadioTile<T> extends StatelessWidget {
  final T value;
  final String label;

  const _RadioTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => RadioGroup.maybeOf<T>(context)?.onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Radio<T>(value: value),
          Text(label),
        ],
      ),
    );
  }
}
