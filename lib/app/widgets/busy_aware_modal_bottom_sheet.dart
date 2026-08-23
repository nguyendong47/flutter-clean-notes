import 'package:flutter/material.dart';

class BusyAwareModalController extends ChangeNotifier {
  final Set<Object> _busySources = <Object>{};
  bool _disposed = false;

  bool get busy => _busySources.isNotEmpty;

  void setBusy(Object source, {required bool busy}) {
    if (_disposed) return;
    final wasBusy = this.busy;
    if (busy) {
      _busySources.add(source);
    } else {
      _busySources.remove(source);
    }
    if (wasBusy != this.busy) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _busySources.clear();
    super.dispose();
  }
}

Future<T?> showBusyAwareModalBottomSheet<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    BusyAwareModalController controller,
  )
  builder,
  bool isScrollControlled = true,
  bool enableDrag = false,
  Color? backgroundColor,
  Color? barrierColor,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final controller = BusyAwareModalController();
  return navigator.push<T>(
    _BusyAwareModalBottomSheetRoute<T>(
      busyController: controller,
      builder: (context) => builder(context, controller),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: backgroundColor,
      modalBarrierColor:
          barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor,
      enableDrag: enableDrag,
    ),
  );
}

class _BusyAwareModalBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BusyAwareModalBottomSheetRoute({
    required this.busyController,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.modalBarrierColor,
    super.enableDrag,
  }) : super(isDismissible: true);

  final BusyAwareModalController busyController;

  @override
  bool get barrierDismissible => !busyController.busy;

  @override
  void install() {
    super.install();
    busyController.addListener(_handleBusyChanged);
  }

  void _handleBusyChanged() => changedInternalState();

  void _dismiss() {
    if (!busyController.busy && isCurrent) navigator?.maybePop();
  }

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    if (!barrierDismissible || !isCurrent) {
      return ExcludeSemantics(child: barrier);
    }
    return Semantics(
      label: barrierLabel,
      onTap: _dismiss,
      onDismiss: _dismiss,
      excludeSemantics: true,
      child: barrier,
    );
  }

  @override
  void dispose() {
    busyController
      ..removeListener(_handleBusyChanged)
      ..dispose();
    super.dispose();
  }
}
