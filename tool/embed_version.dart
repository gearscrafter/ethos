import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('Could not find version in pubspec.yaml');
    exit(1);
  }
  final version = match.group(1)!.trim();

  final output = '''// GENERATED FILE — do not edit by hand.
// Run: dart run tool/embed_version.dart
//
// ignore_for_file: constant_identifier_names
const String kEthosVersion = '$version';
''';

  File('lib/src/version.dart').writeAsStringSync(output);
  stdout.writeln(' lib/src/version.dart updated -> $version');
}
