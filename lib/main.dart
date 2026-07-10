import 'dart:ffi';

import 'package:dart_ffi_execmem_repro/repro_result.dart';
import 'package:flutter/widgets.dart';

typedef NativeCallback = Int32 Function(Int32);
typedef DartCallback = int Function(int);

int addOne(int value) => value + 1;

void main() {
  final pointer = Pointer.fromFunction<NativeCallback>(addOne, -1);
  final result = pointer.asFunction<DartCallback>()(41);

  runApp(ReproResult('Callback result: $result'));
}
