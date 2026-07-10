import 'package:flutter/widgets.dart';

final class ReproResult extends StatelessWidget {
  const ReproResult(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xfffafafa),
        child: Center(
          child: Text(message, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}
