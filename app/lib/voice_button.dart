import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key, required this.onWords, this.enabled = true, this.locale = 'ru_RU',
  });

  final ValueChanged<String> onWords;
  final bool enabled;
  final String locale;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  static final _speech = SpeechToText();
  static _VoiceButtonState? _active;
  bool _listening = false;
  bool _starting = false;

  @override
  void dispose() {
    if (_active == this) {
      _active = null;
      unawaited(_cancel());
    }
    super.dispose();
  }

  Future<void> _cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // No active session to cancel.
    }
  }

  void _error() {
    if (!mounted) return;
    setState(() => _listening = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Распознавание недоступно. Можно ввести текст.')),
    );
  }

  Future<void> _toggle() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      if (_active != null && _active != this) await _cancel();
      if (!mounted) return;
      _active = this;
      final ready = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
        onError: (_) => _active?._error(),
        onStatus: (status) {
          final active = _active;
          if (active != null && active.mounted) {
            active.setState(() => active._listening = status == 'listening');
          }
        },
      );
      if (!mounted || _active != this) return;
      if (!ready) {
        _error();
        return;
      }
      await _speech.listen(
        onResult: (result) {
          if (mounted && _active == this) widget.onWords(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          onDevice: true,
          localeId: widget.locale,
          listenFor: const Duration(seconds: 25),
        ),
      );
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: widget.enabled && !_starting ? _toggle : null,
    icon: Icon(_listening ? Icons.stop : Icons.mic_none),
    label: Text(_listening ? 'Остановить' : 'Диктовать'),
  );
}
