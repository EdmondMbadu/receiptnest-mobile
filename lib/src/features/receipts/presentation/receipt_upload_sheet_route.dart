import 'package:flutter/material.dart';

import '../data/receipt_repository.dart';
import '../models/receipt.dart';
import 'upload_receipt_sheet.dart';

/// Use the native sheet gestures once it is safe to leave. Both barrier taps
/// and drags must be disabled during transfer; PopScope alone cannot stop a
/// BottomSheet drag, which closes through Navigator.pop rather than maybePop.
Future<void> showReceiptUploadSheet({
  required BuildContext context,
  required String userId,
  required ReceiptRepository repository,
  required ValueChanged<Receipt> onUploaded,
  ReceiptSource? initialSource,
  bool guided = false,
  ValueChanged<UploadFileData>? onFileSelected,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  final transferring = ValueNotifier(false);
  // BottomSheet changes its gesture wrapper when dragging is enabled/disabled.
  // Reparent the same upload state so files, retries, and in-flight work survive.
  final sheetKey = GlobalKey();
  return navigator.push<void>(
    _ReceiptUploadRoute(
      transferring: transferring,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      constraints: BoxConstraints(
        maxWidth: guided ? 520 : 540,
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      builder: (_) => UploadReceiptSheet(
        key: sheetKey,
        userId: userId,
        repository: repository,
        onUploaded: onUploaded,
        initialSource: initialSource,
        guided: guided,
        onFileSelected: onFileSelected,
        onTransferStateChanged: (value) => transferring.value = value,
      ),
    ),
  );
}

class _ReceiptUploadRoute extends ModalBottomSheetRoute<void> {
  _ReceiptUploadRoute({
    required this.transferring,
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.modalBarrierColor,
    required super.constraints,
  }) : super(isScrollControlled: true);

  final ValueNotifier<bool> transferring;
  @override
  bool get isDismissible => !transferring.value;
  @override
  bool get enableDrag => !transferring.value;
  @override
  bool get showDragHandle => !transferring.value;
  @override
  RoutePopDisposition get popDisposition =>
      transferring.value ? RoutePopDisposition.doNotPop : super.popDisposition;

  @override
  void install() {
    super.install();
    transferring.addListener(_transferChanged);
  }

  void _transferChanged() {
    if (isActive) changedInternalState(); // Rebuild the modal barrier.
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ValueListenableBuilder<bool>(
    valueListenable: transferring,
    builder: (context, value, child) =>
        super.buildPage(context, animation, secondaryAnimation),
  );

  @override
  void dispose() {
    transferring.removeListener(_transferChanged);
    transferring.dispose();
    super.dispose();
  }
}
