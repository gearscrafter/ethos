import 'package:ethos/src/models/coverage_report.dart';

/// Sealed class representing every event emitted by
/// [CoverageAnalyzer.analyzeDeep].
///
sealed class AnalysisProgress {
  const AnalysisProgress();
}

final class AnalysisPreparing extends AnalysisProgress {
  const AnalysisPreparing();
}

final class AnalysisLoadingContext extends AnalysisProgress {
  final int totalFiles;
  const AnalysisLoadingContext({required this.totalFiles});
}

final class AnalysisAnalyzingFile extends AnalysisProgress {
  final String path;
  final int current;
  final int total;
  const AnalysisAnalyzingFile({
    required this.path,
    required this.current,
    required this.total,
  });
}

final class AnalysisRunningDetector extends AnalysisProgress {
  final String ruleId;
  final String ruleTitle;
  const AnalysisRunningDetector({
    required this.ruleId,
    required this.ruleTitle,
  });
}

final class AnalysisWarning extends AnalysisProgress {
  final String message;
  const AnalysisWarning({required this.message});
}

final class AnalysisComplete extends AnalysisProgress {
  final CoverageReport report;
  final bool usedDeepMode;
  const AnalysisComplete({required this.report, this.usedDeepMode = true});
}
