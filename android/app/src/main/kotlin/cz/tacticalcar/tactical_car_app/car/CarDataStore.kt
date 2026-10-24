package cz.tacticalcar.tactical_car_app.car

import android.os.Handler
import android.os.Looper

data class CarTarget(
    val title: String,
    val kind: String,
    val latitude: Double,
    val longitude: Double,
    val distanceKm: Double,
    val bearingDeg: Double,
    val priority: Boolean,
)

/** Latest navigation targets pushed from Flutter for the car screen. */
object CarDataStore {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<() -> Unit>()

    @Volatile
    var targets: List<CarTarget> = emptyList()
        private set

    fun update(newTargets: List<CarTarget>) {
        targets = newTargets
        mainHandler.post { listeners.toList().forEach { it() } }
    }

    fun addListener(listener: () -> Unit) {
        listeners += listener
    }

    fun removeListener(listener: () -> Unit) {
        listeners -= listener
    }
}
