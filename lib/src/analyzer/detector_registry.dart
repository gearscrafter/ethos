import 'rule_detector.dart';
import 'detectors/semantic_labels_detector.dart';
import 'detectors/contrast_detector.dart';
import 'detectors/touch_target_detector.dart';
import 'detectors/keyboard_detector.dart';
import 'detectors/focus_order_detector.dart';

/// Central registry of [RuleDetector]s, keyed by `ruleId`.
///
/// The registry decouples the analyzer engine from concrete detector
/// implementations: the engine looks up `registry.find(rule.ruleId)` and
/// dispatches without knowing which class handles each rule.
///
/// ## Adding a new detector
///
/// 1. Implement [RuleDetector] in `detectors/your_detector.dart`.
/// 2. Add it to [_builtIn] below.
///
/// That's it. No existing detector needs to change. Third-party packages
/// can also register additional detectors via [register].
class DetectorRegistry {
  final Map<String, RuleDetector> _detectors = {};

  DetectorRegistry.withBuiltIns() {
    for (final detector in _builtIn) {
      register(detector);
    }
  }

  /// Creates an empty registry. Useful for tests.
  DetectorRegistry.empty();

  void register(RuleDetector detector) {
    if (_detectors.containsKey(detector.ruleId)) {
      throw StateError(
        'Detector for rule_id "${detector.ruleId}" is already registered. '
        'Use replace() if this was intentional.',
      );
    }
    _detectors[detector.ruleId] = detector;
  }

  void replace(RuleDetector detector) {
    _detectors[detector.ruleId] = detector;
  }

  RuleDetector? find(String ruleId) => _detectors[ruleId];

  Iterable<String> get registeredRuleIds => _detectors.keys;
}

/// Built-in detectors shipped with Ethos.
///
/// Order is irrelevant; the registry indexes by [RuleDetector.ruleId].
final List<RuleDetector> _builtIn = [
  SemanticLabelsDetector(),
  ContrastDetector(),
  TouchTargetDetector(),
  KeyboardDetector(),
  FocusOrderDetector(),
];