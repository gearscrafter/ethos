import 'dart:convert';
import 'dart:io';

import 'version.dart';

class UpdateChecker {
  static const _timeout = Duration(seconds: 3);
  static const _pubApiUrl = 'https://pub.dev/api/packages/ethos';

  String? _latestVersion;

  Future<void> fetch() async {
    try {
      print('DEBUG: fetching pub.dev...');
      final client = HttpClient()..connectionTimeout = _timeout;
      final request = await client.getUrl(Uri.parse(_pubApiUrl));
      final response = await request.close().timeout(_timeout);
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        _latestVersion =
            (json['latest'] as Map<String, dynamic>)['version'] as String?;
        print('DEBUG: latest=$_latestVersion');
      }
      client.close();
    } catch (_) {}
  }

  void printUpdateHintIfNeeded() {
    final latest = _latestVersion;
    if (latest == null) {
      return;
    }
    if (!_isNewer(latest, kEthosVersion)) {
      return;
    }

    stderr.writeln('');
    stderr.writeln('╔══════════════════════════════════════════════════╗');
    stderr.writeln(
        '${'║  Update available: $kEthosVersion → $latest'.padRight(51)}║');
    stderr.writeln('║  Run: dart pub global activate ethos              ║');
    stderr.writeln('╚══════════════════════════════════════════════════╝');
  }

  static bool _isNewer(String candidate, String current) {
    try {
      final a = _parse(candidate);
      final b = _parse(current);
      for (var i = 0; i < 3; i++) {
        if (a[i] > b[i]) {
          return true;
        }
        if (a[i] < b[i]) {
          return false;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parse(String v) {
    final parts = v.split('.').map(int.parse).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}
