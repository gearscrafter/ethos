import '../../models/ethos_config.dart';
import '../../models/spec.dart';
import '../rule_detector.dart';
import 'resolved_file.dart';

/// Contract for detectors that use the full [ProjectIndex].
///
/// Deep detectors receive the same inputs as [RuleDetector] plus the
/// [ProjectIndex] — the cross-file type map built by [DeepAnalyzer].
///
abstract class DeepDetector {
  String get ruleId;

  DetectionResult analyzeDeep({
    required Rule rule,
    required List<ResolvedFile> files,
    required ProjectIndex index,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
  });
}
