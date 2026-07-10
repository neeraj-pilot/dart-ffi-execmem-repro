import 'dart:ffi';

import 'package:dart_ffi_execmem_repro/execmem_filter.dart';
import 'package:dart_ffi_execmem_repro/repro_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef NativeCallback = Int32 Function(Int32);
typedef DartCallback = int Function(int);

int addOne(int value) => value + 1;

void main() {
  const denyExecMemory = bool.fromEnvironment('DENY_EXECMEM');
  const callbackApi = String.fromEnvironment(
    'CALLBACK_API',
    defaultValue: 'pointer',
  );

  if (denyExecMemory) {
    if (!kReleaseMode) {
      throw UnsupportedError('DENY_EXECMEM requires a release build.');
    }
    installExecMemoryDenial();
  }

  WidgetsFlutterBinding.ensureInitialized();

  final message = switch (callbackApi) {
    'none' => 'No callback: app is running',
    'pointer' => 'Pointer.fromFunction result: ${_pointerResult()}',
    'native' => 'NativeCallable result: ${_nativeCallableResult()}',
    _ => throw ArgumentError.value(
      callbackApi,
      'CALLBACK_API',
      'Expected none, pointer, or native.',
    ),
  };

  runApp(ReproResult(message));
}

int _pointerResult() {
  final pointer = Pointer.fromFunction<NativeCallback>(addOne, -1);
  return pointer.asFunction<DartCallback>()(41);
}

int _nativeCallableResult() {
  final callback = NativeCallable<NativeCallback>.isolateLocal(
    addOne,
    exceptionalReturn: -1,
  );
  try {
    return callback.nativeFunction.asFunction<DartCallback>()(41);
  } finally {
    callback.close();
  }
}
