import 'package:flutter/material.dart';

class RestartWidget extends StatefulWidget {
  final Widget child;
  const RestartWidget({required this.child, super.key});

  static void restartApp(BuildContext context) {
    final _RestartWidgetState? state =
    context.findAncestorStateOfType<_RestartWidgetState>();
    state?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey(); // forces rebuild of entire tree
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: key, child: widget.child);
  }
}
