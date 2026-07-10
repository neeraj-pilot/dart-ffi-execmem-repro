import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:dart_ffi_execmem_repro/execmem_filter.dart';
import 'package:dart_ffi_execmem_repro/repro_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  const denyExecMemory = bool.fromEnvironment('DENY_EXECMEM');
  if (denyExecMemory) {
    if (!kReleaseMode) {
      throw UnsupportedError('DENY_EXECMEM requires a release build.');
    }
    installExecMemoryDenial();
  }

  WidgetsFlutterBinding.ensureInitialized();

  HttpServer? server;
  CronetClient? client;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });

    client = CronetClient.defaultCronetEngine();
    final response = await client.get(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    if (response.statusCode != HttpStatus.noContent) {
      throw StateError('Expected HTTP 204, received ${response.statusCode}.');
    }

    runApp(const ReproResult('Cronet loopback result: HTTP 204'));
  } finally {
    client?.close();
    await server?.close(force: true);
  }
}
