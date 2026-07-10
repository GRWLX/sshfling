import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  // This Dart command runs on the server and launches the explicit Node bridge.
  final node = Platform.environment['NODE'] ?? 'node';
  final bridge = Platform.script.resolve('../bridge.cjs').toFilePath();
  final process = await Process.run(node, [bridge]);

  if (process.exitCode != 0) {
    throw ProcessException(node, [bridge], process.stderr.toString(), process.exitCode);
  }

  final result = jsonDecode(process.stdout.toString());
  if (result is! Map<String, dynamic> ||
      result['runtime'] != 'node' ||
      result['status'] != 0 ||
      result['templatesAvailable'] != true) {
    throw StateError('SSHFling Node bridge returned an invalid result.');
  }

  stdout.writeln('Dart server consumer verified the SSHFling Node API.');
}
