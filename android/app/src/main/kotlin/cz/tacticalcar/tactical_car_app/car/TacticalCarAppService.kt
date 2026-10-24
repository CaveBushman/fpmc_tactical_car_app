package cz.tacticalcar.tactical_car_app.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarLocation
import androidx.car.app.model.ItemList
import androidx.car.app.model.Metadata
import androidx.car.app.model.Place
import androidx.car.app.model.PlaceListMapTemplate
import androidx.car.app.model.PlaceMarker
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.Locale

/**
 * Android Auto POI app: team members and mission points on the car map,
 * nearest/priority first; selecting one starts navigation in the car's
 * navigation app. Data comes from the phone app via [CarBridge].
 */
class TacticalCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(this)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen = TargetsScreen(carContext)
    }
}

class TargetsScreen(carContext: CarContext) : Screen(carContext) {
    private val listener: () -> Unit = { invalidate() }

    init {
        CarDataStore.addListener(listener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarDataStore.removeListener(listener)
            }
        })
    }

    @Suppress("DEPRECATION")
    override fun onGetTemplate(): Template {
        val items = ItemList.Builder()
        val targets = CarDataStore.targets.take(6)
        if (targets.isEmpty()) {
            items.setNoItemsMessage("Žádné cíle. Otevři Tactical Mesh v telefonu.")
        }
        for (target in targets) {
            val place = Place.Builder(CarLocation.create(target.latitude, target.longitude))
                .setMarker(
                    PlaceMarker.Builder()
                        .setColor(if (target.priority) CarColor.RED else CarColor.BLUE)
                        .build(),
                )
                .build()
            items.addItem(
                Row.Builder()
                    .setTitle(target.title)
                    .addText(
                        String.format(
                            Locale.ROOT,
                            "%s · AZ %03.0f° · %.1f km",
                            target.kind,
                            target.bearingDeg,
                            target.distanceKm,
                        ),
                    )
                    .setMetadata(Metadata.Builder().setPlace(place).build())
                    .setOnClickListener { navigateTo(target) }
                    .build(),
            )
        }
        return PlaceListMapTemplate.Builder()
            .setTitle("Taktické cíle")
            .setHeaderAction(Action.APP_ICON)
            .setCurrentLocationEnabled(true)
            .setItemList(items.build())
            .build()
    }

    private fun navigateTo(target: CarTarget) {
        val uri = Uri.parse("geo:${target.latitude},${target.longitude}")
        carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
    }
}
