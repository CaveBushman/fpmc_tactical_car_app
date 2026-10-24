package cz.tacticalcar.tactical_car_app

import android.view.KeyEvent
import cz.tacticalcar.tactical_car_app.car.CarBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        PttBridge.attach(messenger, this)
        CarBridge.attach(messenger, this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        PttBridge.handleKey(event) || super.dispatchKeyEvent(event)

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        PttBridge.onPermissionsResult(this)
    }
}
