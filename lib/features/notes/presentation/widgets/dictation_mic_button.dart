import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

class DictationMicButton extends ConsumerStatefulWidget {
  const DictationMicButton({
    required this.controller,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  ConsumerState<DictationMicButton> createState() => _DictationMicButtonState();
}

class _DictationMicButtonState extends ConsumerState<DictationMicButton> {
  DictationState _state = DictationState.idle;
  DictationService? _service;
  StreamSubscription<DictationState>? _stateSub;
  StreamSubscription<String>? _textSub;
  int? _trackedSpanStart;
  int _trackedSpanLength = 0;

  @override
  void didUpdateWidget(covariant DictationMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled &&
        !widget.enabled &&
        _state == DictationState.listening) {
      _service?.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(dictationServiceProvider);
    _subscribeIfNeeded(service);

    return IconButton(
      tooltip: _state == DictationState.unavailable
          ? 'editor.dictationUnavailable'.tr()
          : 'editor.dictation'.tr(),
      icon: Icon(
        _state == DictationState.listening
            ? Icons.mic_rounded
            : Icons.mic_none_rounded,
      ),
      onPressed: (!widget.enabled || _state == DictationState.unavailable)
          ? null
          : () => _toggle(service),
    );
  }

  // Subscribing manually (instead of nesting StreamBuilders around the
  // returned widget) is deliberate: this widget's job on a text event is to
  // mutate `widget.controller` — a *side effect* — not just to re-render.
  // Doing that inside a StreamBuilder's builder callback runs it during
  // this widget's own build phase, which can trigger "setState()/
  // markNeedsBuild() called during build" once the sibling TextField
  // listening to the same controller reacts synchronously. Subscribing in
  // (effectively) initState and reacting via setState/side-effect callbacks
  // keeps stream reactions strictly post-build.
  void _subscribeIfNeeded(DictationService service) {
    if (identical(_service, service)) return;
    _stateSub?.cancel();
    _textSub?.cancel();
    _service = service;
    _state = service.currentState;
    _trackedSpanStart = null;
    _trackedSpanLength = 0;
    _stateSub = service.stateStream.listen(_handleState);
    _textSub = service.recognizedTextStream.listen(_insertText);
  }

  void _handleState(DictationState state) {
    final previous = _state;
    if (!mounted) return;
    if (state == DictationState.listening &&
        previous != DictationState.listening) {
      _trackedSpanStart = null;
      _trackedSpanLength = 0;
    }
    setState(() => _state = state);
    if (state == DictationState.error) {
      _showSnackBar('editor.dictationError'.tr());
    } else if (state == DictationState.unavailable) {
      _showSnackBar('editor.dictationUnavailable'.tr());
    } else if (state == DictationState.permissionDenied) {
      _showSnackBar('editor.dictationPermissionDenied'.tr());
    } else if (state == DictationState.permissionPermanentlyDenied) {
      _showPermanentlyDeniedSnackBar();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPermanentlyDeniedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('editor.dictationPermissionPermanentlyDenied'.tr()),
        action: SnackBarAction(
          label: 'editor.openSettings'.tr(),
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  void _insertText(String text) {
    final controller = widget.controller;
    final selection = controller.selection;
    final textLength = controller.text.length;

    final hasActiveSpan =
        _trackedSpanStart != null &&
        _trackedSpanStart! + _trackedSpanLength <= textLength;
    final isAtExpectedEnd =
        hasActiveSpan &&
        selection.isValid &&
        selection.isCollapsed &&
        selection.start == _trackedSpanStart! + _trackedSpanLength;

    if (isAtExpectedEnd) {
      final start = _trackedSpanStart!;
      final end = start + _trackedSpanLength;
      final newText = controller.text.replaceRange(start, end, text);
      _trackedSpanLength = text.length;
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
        composing: TextRange.empty,
      );
    } else {
      final start = selection.isValid ? selection.start : textLength;
      final end = selection.isValid ? selection.end : textLength;
      final newText = controller.text.replaceRange(start, end, text);
      _trackedSpanStart = start;
      _trackedSpanLength = text.length;
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
        composing: TextRange.empty,
      );
    }
  }

  Future<void> _toggle(DictationService service) async {
    if (_state == DictationState.listening) {
      await service.stop();
    } else {
      final locale =
          EasyLocalization.of(context)?.locale ??
          Localizations.maybeLocaleOf(context) ??
          const Locale('en');
      await service.start(localeId: _speechLocaleId(locale));
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _textSub?.cancel();
    super.dispose();
  }
}

/// Maps this app's supported UI locales (`en`, `vi` — see `main.dart`'s
/// `supportedLocales`) to the region-qualified locale ID the OS speech
/// recognizer actually expects (e.g. `vi_VN`, not bare `vi` —
/// `context.locale.toString()` alone only gives the bare language code
/// easy_localization tracks, which speech_to_text does not accept).
/// Extend this map if `main.dart`'s supportedLocales grows.
String _speechLocaleId(Locale locale) {
  switch (locale.languageCode) {
    case 'vi':
      return 'vi_VN';
    case 'en':
    default:
      return 'en_US';
  }
}
