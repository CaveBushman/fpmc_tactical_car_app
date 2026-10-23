
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: 512 * 1024 * 1024,
    overrideFreshAge: const Duration(days: 30),
  );
  runApp(const TacticalCarApp());
}
