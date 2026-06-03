import 'package:analyzer/dart/ast/ast.dart';

import '../ast/widget_visitor.dart';

/// Discovers custom widgets and unresolvable color expressions in a project.
class WidgetDiscovery {
  /// Minimum number of usages for a widget or color to appear in output.
  static const int minUsages = 3;

  static const Set<String> _knownWidgets = {
    'Widget',
    'StatelessWidget',
    'StatefulWidget',
    'State',
    'Container',
    'Row',
    'Column',
    'Stack',
    'Positioned',
    'Expanded',
    'Flexible',
    'Spacer',
    'SizedBox',
    'ConstrainedBox',
    'FractionallySizedBox',
    'AspectRatio',
    'FittedBox',
    'Padding',
    'Align',
    'Center',
    'Transform',
    'Wrap',
    'Flow',
    'GridView',
    'ListView',
    'CustomScrollView',
    'SingleChildScrollView',
    'NestedScrollView',
    'PageView',
    'SliverList',
    'SliverGrid',
    'SliverAppBar',
    'SliverToBoxAdapter',
    'Text',
    'RichText',
    'DefaultTextStyle',
    'SelectableText',
    'TextField',
    'TextFormField',
    'Form',
    'FormField',
    'Checkbox',
    'CheckboxListTile',
    'Radio',
    'RadioListTile',
    'Switch',
    'SwitchListTile',
    'Slider',
    'RangeSlider',
    'DropdownButton',
    'DropdownMenuItem',
    'PopupMenuButton',
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'IconButton',
    'FloatingActionButton',
    'BackButton',
    'CloseButton',
    'ToggleButtons',
    'SegmentedButton',
    'GestureDetector',
    'InkWell',
    'InkResponse',
    'Ink',
    'Draggable',
    'DragTarget',
    'InteractiveViewer',
    'Dismissible',
    'Semantics',
    'MergeSemantics',
    'ExcludeSemantics',
    'BlockSemantics',
    'Focus',
    'FocusScope',
    'FocusTraversalGroup',
    'Shortcuts',
    'CallbackShortcuts',
    'Actions',
    'KeyboardListener',
    'RawKeyboardListener',
    'Image',
    'Icon',
    'ImageIcon',
    'DecoratedBox',
    'CircleAvatar',
    'ClipOval',
    'ClipRRect',
    'ClipRect',
    'ClipPath',
    'Navigator',
    'Router',
    'Scaffold',
    'AppBar',
    'BottomNavigationBar',
    'TabBar',
    'TabBarView',
    'NavigationBar',
    'NavigationRail',
    'Drawer',
    'Dialog',
    'AlertDialog',
    'SimpleDialog',
    'BottomSheet',
    'Tooltip',
    'Overlay',
    'SnackBar',
    'MaterialBanner',
    'MaterialApp',
    'Material',
    'Card',
    'Chip',
    'InputChip',
    'FilterChip',
    'ChoiceChip',
    'ActionChip',
    'ListTile',
    'ExpansionTile',
    'Divider',
    'VerticalDivider',
    'Badge',
    'LinearProgressIndicator',
    'CircularProgressIndicator',
    'RefreshIndicator',
    'Stepper',
    'Theme',
    'ThemeData',
    'TextTheme',
    'ColorScheme',
    'TextStyle',
    'ButtonStyle',
    'AnimatedBuilder',
    'AnimatedWidget',
    'AnimatedContainer',
    'AnimatedOpacity',
    'AnimatedSize',
    'AnimatedSwitcher',
    'AnimatedCrossFade',
    'TweenAnimationBuilder',
    'AnimationController',
    'FadeTransition',
    'ScaleTransition',
    'SlideTransition',
    'Builder',
    'LayoutBuilder',
    'OrientationBuilder',
    'MediaQuery',
    'SafeArea',
    'WillPopScope',
    'StreamBuilder',
    'FutureBuilder',
    'ValueListenableBuilder',
    'Offstage',
    'Visibility',
    'Opacity',
    'AbsorbPointer',
    'IgnorePointer',
    'MouseRegion',
    'BackdropFilter',
    'ColorFiltered',
    'ShaderMask',
    'CustomPaint',
    'RepaintBoundary',
    'Hero',
    'HeroMode',
    'ScrollConfiguration',
    'Scrollbar',
    'Scrollable',
    'NotificationListener',
    'SelectionArea',
    'PhysicalModel',
    'OverflowBox',
    'LimitedBox',
    'RotatedBox',
    'Baseline',
  };

  static DiscoveryResult discover(List<ParsedFile> files) {
    final widgetCounts = <String, int>{};
    final colorExpressions = <String, int>{};

    for (final file in files) {
      for (final widget in file.widgets) {
        _processWidget(widget, widgetCounts, colorExpressions);
      }
    }

    final filteredWidgets = Map.fromEntries(
      widgetCounts.entries.where((e) => e.value >= minUsages).toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );

    final filteredColors = Map.fromEntries(
      colorExpressions.entries.where((e) => e.value >= minUsages).toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );

    return DiscoveryResult(
      widgetUsages: filteredWidgets,
      colorExpressions: filteredColors,
    );
  }

  static void _processWidget(
    WidgetUsage widget,
    Map<String, int> widgetCounts,
    Map<String, int> colorExpressions,
  ) {
    final type = widget.type;

    if (!_knownWidgets.contains(type) &&
        type.isNotEmpty &&
        _isPascalCase(type) &&
        !type.endsWith('State') &&
        !type.endsWith('Data') &&
        !type.endsWith('Model') &&
        !type.endsWith('Controller') &&
        !type.endsWith('Notifier') &&
        !type.endsWith('Cubit') &&
        !type.endsWith('Bloc') &&
        !type.endsWith('Event') &&
        !type.endsWith('Exception') &&
        !type.endsWith('Error')) {
      widgetCounts[type] = (widgetCounts[type] ?? 0) + 1;
    }

    if (type == 'TextStyle' || type == 'Text' || type == 'DefaultTextStyle') {
      _extractColorExpr(widget.arg('color'), colorExpressions);
      _extractColorExpr(widget.arg('backgroundColor'), colorExpressions);
    }
  }

  static void _extractColorExpr(
    Expression? expr,
    Map<String, int> colorExpressions,
  ) {
    if (expr == null) {
      return;
    }

    if (expr is IntegerLiteral) {
      return;
    }
    if (expr is PrefixedIdentifier && expr.prefix.name == 'Colors') {
      return;
    }
    if (expr is InstanceCreationExpression) {
      final src = expr.constructorName.type.toSource().trim();
      if (src == 'Color') {
        return;
      }
    }

    final source = expr.toSource().trim();
    if (source.isEmpty || source.length > 80) {
      return;
    }
    if (source.startsWith('Theme.of') || source.startsWith('theme.')) {
      return;
    }

    colorExpressions[source] = (colorExpressions[source] ?? 0) + 1;
  }

  static bool _isPascalCase(String name) {
    if (name.isEmpty) {
      return false;
    }
    final c = name.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }
}

/// Result of a [WidgetDiscovery.discover] call.
class DiscoveryResult {
  final Map<String, int> widgetUsages;

  final Map<String, int> colorExpressions;

  const DiscoveryResult({
    required this.widgetUsages,
    required this.colorExpressions,
  });

  bool get isEmpty => widgetUsages.isEmpty && colorExpressions.isEmpty;
  int get totalWidgets => widgetUsages.length;
  int get totalColors => colorExpressions.length;
}
