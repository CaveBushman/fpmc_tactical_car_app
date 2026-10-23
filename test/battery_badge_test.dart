import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_car_app/widgets/node_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, int? percent) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BatteryBadge(percent: percent)),
      ),
    );
  }

  testWidgets('shows unknown, external power and low battery', (tester) async {
    await pump(tester, null);
    expect(find.text('--'), findsOneWidget);

    await pump(tester, 101);
    expect(find.text('EXT'), findsOneWidget);

    await pump(tester, 12);
    expect(find.text('12%'), findsOneWidget);
    expect(find.byIcon(Icons.battery_alert), findsOneWidget);
  });
}
