# Analysis fixtures

The `.dart` files in this folder are **input data** for the Ethos analyzer,
not executable code.

When you run `dart run example/main.dart`, Ethos opens these files as
text, parses them with `package:analyzer` to build an AST, and counts
widget patterns. Nothing here is ever compiled or run.

That's why:

- There's no `pubspec.yaml`, no `main()`, no `runApp()`.
- The files import `package:flutter/material.dart` but Flutter is **not**
  a dependency of Ethos — the import is just a string that the analyzer
  reads. It would parse fine even with Flutter uninstalled.
- The widgets here are intentionally a mix of compliant, non-compliant,
  and indeterminate cases so the example output is informative.

## Files

- `lib/home_screen.dart` — exercises GestureDetector / InkWell with
  varying Semantics ancestry (PASS, FAIL, INDETERMINATE).
- `lib/settings_screen.dart` — adds empty-label FAIL and a PASS via
  InkResponse, across a second file so the report aggregates correctly.

## Adding more cases

To extend the example with new fixtures, just drop another `.dart` file
under `lib/`. The analyzer walks the folder recursively.