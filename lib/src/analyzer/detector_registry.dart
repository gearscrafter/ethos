import 'rule_detector.dart';
import 'detectors/semantic_labels_detector.dart';
import 'detectors/contrast_detector.dart';
import 'detectors/touch_target_detector.dart';
import 'detectors/keyboard_detector.dart';
import 'detectors/focus_order_detector.dart';
import 'detectors/non_text_content_detector.dart';
import 'detectors/resize_text_detector.dart';

/// Central registry of [RuleDetector]s, keyed by `ruleId`.
///
/// ## Adding a new detector (open/closed)
///
/// 1. Implement [RuleDetector] in `detectors/your_detector.dart`.
/// 2. Add it to [_builtIn] below.
///
/// No existing code needs to change.
class DetectorRegistry {
  final Map<String, RuleDetector> _detectors = {};

  /// Creates a registry pre-populated with all built-in Ethos detectors.
  DetectorRegistry.withBuiltIns() {
    for (final detector in _builtIn) {
      register(detector);
    }
  }

  /// Creates an empty registry. Useful for tests.
  DetectorRegistry.empty();

  /// Registers [detector]. Throws if [detector.ruleId] is already taken —
  /// use [replace] when overriding a built-in intentionally.
  void register(RuleDetector detector) {
    if (_detectors.containsKey(detector.ruleId)) {
      throw StateError(
        'Detector for rule_id "${detector.ruleId}" is already registered. '
        'Use replace() if this was intentional.',
      );
    }
    _detectors[detector.ruleId] = detector;
  }

  /// Replaces an existing detector — for host projects that want a stricter
  /// or customised version of a built-in rule.
  void replace(RuleDetector detector) {
    _detectors[detector.ruleId] = detector;
  }

  /// Returns the detector for [ruleId], or `null` if none registered.
  RuleDetector? find(String ruleId) => _detectors[ruleId];

  /// All registered rule_ids. Useful for diagnostics and tests.
  Iterable<String> get registeredRuleIds => _detectors.keys;
}

/// Built-in detectors shipped with Ethos.
final List<RuleDetector> _builtIn = [
  SemanticLabelsDetector(),
  ContrastDetector(),
  TouchTargetDetector(),
  KeyboardDetector(),
  FocusOrderDetector(),
  NonTextContentDetector(),
  ResizeTextDetector(),
];
