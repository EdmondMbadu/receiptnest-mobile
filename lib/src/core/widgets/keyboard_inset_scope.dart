import 'package:flutter/widgets.dart';

/// Keeps keyboard visibility available after the shell consumes its layout inset.
class KeyboardInsetScope extends InheritedWidget {
  const KeyboardInsetScope({
    super.key,
    required this.bottom,
    required super.child,
  });
  final double bottom;

  static bool isVisibleOf(BuildContext context) =>
      (context
              .dependOnInheritedWidgetOfExactType<KeyboardInsetScope>()
              ?.bottom ??
          MediaQuery.viewInsetsOf(context).bottom) >
      0;

  @override
  bool updateShouldNotify(KeyboardInsetScope oldWidget) =>
      bottom != oldWidget.bottom;
}
