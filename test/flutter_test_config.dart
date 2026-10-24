import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs around every test file: fresh in-memory storage plugins before each
/// test, so code reading preferences or secure storage completes and no
/// saved setting (group, font size, …) leaks from one test into the next.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  await testMain();
}
