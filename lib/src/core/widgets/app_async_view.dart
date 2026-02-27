import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppAsyncView<T> extends StatelessWidget {
  const AppAsyncView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final Widget Function(Object err, StackTrace stack)? error;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => loading ?? const Center(child: CircularProgressIndicator()),
      error: (err, stack) => error?.call(err, stack) ?? Center(child: Text('Error: $err')),
    );
  }
}
