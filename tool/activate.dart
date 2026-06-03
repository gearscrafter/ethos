import 'dart:io';

void main() async {
  stdout.writeln('🔧 Ethos — local activate');
  stdout.writeln('');

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    stderr.writeln(' Could not find version in pubspec.yaml');
    exit(1);
  }
  final version = match.group(1)!.trim();
  stdout.writeln('📦 Version: $version');

  stdout.writeln('...Regenerating lib/src/version.dart...');
  final embedResult = await Process.run(
    'dart',
    ['run', 'tool/embed_version.dart'],
    runInShell: true,
  );
  if (embedResult.exitCode != 0) {
    stderr.writeln(' embed_version failed:\n${embedResult.stderr}');
    exit(1);
  }
  stdout.writeln(embedResult.stdout.toString().trim());

  stdout.writeln(' Running dart pub global activate --source path .');
  final activateResult = await Process.run(
    'dart',
    ['pub', 'global', 'activate', '--source', 'path', '.'],
    runInShell: true,
  );
  stdout.write(activateResult.stdout);
  if (activateResult.stderr.toString().isNotEmpty) {
    stderr.write(activateResult.stderr);
  }
  if (activateResult.exitCode != 0) {
    stderr.writeln(' Activation failed');
    exit(1);
  }

  stdout.writeln('');
  stdout.writeln(' ethos $version activated. Try:');
  stdout.writeln('   ethos --version');
  stdout.writeln('   ethos --help');
}
