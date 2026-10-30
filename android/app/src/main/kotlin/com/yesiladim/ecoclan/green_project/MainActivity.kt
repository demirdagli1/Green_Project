package com.yesiladim.ecoclan.green_project

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Gerçek cihaz donanım köprüsü: adım sayacı, ivmeölçer, GPS, NFC, izinler, sistem bildirimi.
 * Hiçbir değer uydurulmaz; donanım/izin yoksa kanal bunu açıkça bildirir.
 */
class MainActivity : FlutterActivity(), SensorEventListener, LocationListener,
    NfcAdapter.ReaderCallback {

    private val methodName = "com.yesiladim.ecoclan/hardware"
    private val eventName = "com.yesiladim.ecoclan/events"
    private val notifChannelId = "yesil_adim_bildirim_v2"
    private val permRequestCode = 4711
    private val photoPickerRequestCode = 4712

    private var sink: EventChannel.EventSink? = null
    private var pendingPermResult: MethodChannel.Result? = null
    private var pendingPhotoResult: MethodChannel.Result? = null
    private var sensorsOn = false
    private var nfcOn = false

    private lateinit var sensorManager: SensorManager
    private val accelWindow = ArrayList<Pair<Long, Double>>()

    private val prefs by lazy { getSharedPreferences("hw_perm", Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodName)
            .setMethodCallHandler { call, result -> onMethod(call, result) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
                override fun onCancel(args: Any?) { sink = null }
            })
    }

    private fun onMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermissions" -> {
                @Suppress("UNCHECKED_CAST")
                val wanted = (call.argument<List<String>>("permissions") ?: emptyList())
                requestPerms(wanted, result)
            }
            "startSensors" -> result.success(startSensors())
            "stopSensors" -> { stopSensors(); result.success(true) }
            "startNfc" -> result.success(startNfc())
            "stopNfc" -> { stopNfc(); result.success(true) }
            "showNotification" -> {
                val ok = showNotification(
                    call.argument<String>("title") ?: "Yeşil Adım",
                    call.argument<String>("body") ?: "",
                    call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                )
                result.success(ok)
            }
            "openAppSettings" -> {
                try {
                    val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                        flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "pickImage" -> pickImage(result)
            else -> result.notImplemented()
        }
    }

    // ---- Yetenekler & izinler ----
    private fun capabilities(): Map<String, Any> {
        val nfc = NfcAdapter.getDefaultAdapter(this)
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val gpsPresent = packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS)
        return mapOf(
            "stepCounter" to (sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null),
            "accelerometer" to (sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null),
            "gps" to gpsPresent,
            "locationEnabled" to (gpsPresent && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)),
            "nfc" to (nfc != null),
            "nfcEnabled" to (nfc?.isEnabled == true),
            "sdk" to Build.VERSION.SDK_INT
        )
    }

    private fun permNames(key: String): List<String> = when (key) {
        "activity" -> if (Build.VERSION.SDK_INT >= 29) listOf(Manifest.permission.ACTIVITY_RECOGNITION) else emptyList()
        "location" -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        "notifications" -> if (Build.VERSION.SDK_INT >= 33) listOf(Manifest.permission.POST_NOTIFICATIONS) else emptyList()
        else -> emptyList()
    }

    private fun granted(key: String): Boolean = permNames(key).all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun permissionStatus(): Map<String, String> {
        val out = HashMap<String, String>()
        for (k in listOf("activity", "location", "notifications")) {
            out[k] = when {
                granted(k) -> "granted"
                prefs.getBoolean("asked_$k", false) &&
                    permNames(k).none { ActivityCompat.shouldShowRequestPermissionRationale(this, it) } -> "permanentlyDenied"
                else -> "denied"
            }
        }
        return out
    }

    private fun requestPerms(keys: List<String>, result: MethodChannel.Result) {
        val names = keys.flatMap { permNames(it) }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        keys.forEach { prefs.edit().putBoolean("asked_$it", true).apply() }
        if (names.isEmpty() || pendingPermResult != null) { result.success(permissionStatus()); return }
        pendingPermResult = result
        ActivityCompat.requestPermissions(this, names.toTypedArray(), permRequestCode)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code == permRequestCode) {
            pendingPermResult?.success(permissionStatus())
            pendingPermResult = null
        }
    }

    // ---- Fotoğraf Seçici (Photo Picker / Open Document) ----
    private fun pickImage(result: MethodChannel.Result) {
        if (pendingPhotoResult != null) {
            result.error("BUSY", "Önceki görsel seçimi henüz tamamlanmadı.", null)
            return
        }
        pendingPhotoResult = result
        try {
            val intent = if (Build.VERSION.SDK_INT >= 33) {
                Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    type = "image/*"
                }
            } else {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                }
            }
            startActivityForResult(intent, photoPickerRequestCode)
        } catch (_: Exception) {
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                }
                startActivityForResult(fallback, photoPickerRequestCode)
            } catch (e: Exception) {
                pendingPhotoResult?.error("PICKER_UNAVAILABLE", e.message, null)
                pendingPhotoResult = null
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == photoPickerRequestCode) {
            val currentResult = pendingPhotoResult
            pendingPhotoResult = null
            if (currentResult == null) return

            if (resultCode != Activity.RESULT_OK || data == null || data.data == null) {
                currentResult.success(null)
                return
            }

            val uri = data.data!!
            Thread {
                try {
                    val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream, null, boundsOptions)
                    }

                    if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) {
                        runOnUiThread { currentResult.error("INVALID_IMAGE", "Görsel formatı okunamadı.", null) }
                        return@Thread
                    }

                    val maxDim = 1024
                    var sampleSize = 1
                    var w = boundsOptions.outWidth
                    var h = boundsOptions.outHeight
                    while (w > maxDim * 2 || h > maxDim * 2) {
                        sampleSize *= 2
                        w /= 2
                        h /= 2
                    }

                    val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
                    val bitmap = contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream, null, decodeOptions)
                    }

                    if (bitmap == null) {
                        runOnUiThread { currentResult.error("DECODE_ERROR", "Görsel çözülemedi.", null) }
                        return@Thread
                    }

                    val destFile = File(filesDir, "profile_photo.jpg")
                    FileOutputStream(destFile).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    }
                    bitmap.recycle()

                    runOnUiThread { currentResult.success(destFile.absolutePath) }
                } catch (e: Exception) {
                    runOnUiThread { currentResult.error("IO_ERROR", e.message, null) }
                }
            }.start()
        }
    }

    // ---- Sensörler ----
    private fun emit(m: Map<String, Any?>) { runOnUiThread { sink?.success(m) } }

    private fun startSensors(): Map<String, Any> {
        val started = HashMap<String, Any>()
        if (sensorsOn) stopSensors()

        val step = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        val stepOk = if (step != null && granted("activity")) {
            sensorManager.registerListener(this, step, SensorManager.SENSOR_DELAY_NORMAL)
        } else false
        started["stepCounter"] = stepOk

        val acc = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val accOk = if (acc != null) {
            sensorManager.registerListener(this, acc, SensorManager.SENSOR_DELAY_UI)
        } else false
        started["accelerometer"] = accOk

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var gpsOk = false
        var gpsMode = "none"
        if (granted("location")) {
            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this, Looper.getMainLooper())
                    gpsOk = true
                    gpsMode = "gps"
                }
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000L, 0f, this, Looper.getMainLooper())
                    gpsOk = true
                    gpsMode = if (gpsMode == "gps") "gps+network" else "network"
                }
            } catch (_: SecurityException) {
                gpsOk = false
            }
        }
        started["gps"] = gpsOk
        started["gpsMode"] = gpsMode
        sensorsOn = true

        emit(mapOf(
            "type" to "sensor_started",
            "stepCounter" to stepOk,
            "accelerometer" to accOk,
            "gps" to gpsOk,
            "gpsMode" to gpsMode,
            "ts" to System.currentTimeMillis()
        ))
        return started
    }

    private fun stopSensors() {
        sensorManager.unregisterListener(this)
        try { (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(this) } catch (_: Exception) {}
        accelWindow.clear()
        sensorsOn = false
    }

    override fun onSensorChanged(e: SensorEvent) {
        when (e.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> {
                val total = e.values[0].toLong()
                emit(mapOf(
                    "type" to "steps",
                    "total" to total,
                    "ts" to System.currentTimeMillis()
                ))
            }
            Sensor.TYPE_ACCELEROMETER -> {
                val mag = sqrt((e.values[0] * e.values[0] + e.values[1] * e.values[1] + e.values[2] * e.values[2]).toDouble())
                val nowMs = System.currentTimeMillis()
                accelWindow.add(Pair(nowMs, mag))
                while (accelWindow.isNotEmpty() && nowMs - accelWindow.first().first > 2000) {
                    accelWindow.removeAt(0)
                }
                val span = if (accelWindow.isNotEmpty()) (accelWindow.last().first - accelWindow.first().first) else 0L
                if (accelWindow.size >= 15 && span >= 1000L) {
                    val vals = accelWindow.map { it.second }
                    val mean = vals.average()
                    val variance = vals.map { (it - mean) * (it - mean) }.average()
                    var crossings = 0
                    for (i in 1 until vals.size) {
                        if ((vals[i - 1] - mean) * (vals[i] - mean) < 0) crossings++
                    }
                    val spanSec = span / 1000.0
                    val freq = if (spanSec > 0) crossings / 2.0 / spanSec else 0.0
                    emit(mapOf(
                        "type" to "accel",
                        "variance" to variance,
                        "freqHz" to freq,
                        "sampleCount" to accelWindow.size,
                        "ts" to System.currentTimeMillis()
                    ))
                    accelWindow.clear()
                }
            }
        }
    }

    override fun onAccuracyChanged(s: Sensor?, a: Int) {}

    override fun onLocationChanged(l: Location) {
        emit(mapOf(
            "type" to "location",
            "lat" to l.latitude,
            "lon" to l.longitude,
            "speedMps" to (if (l.hasSpeed()) l.speed.toDouble() else null),
            "accuracy" to (if (l.hasAccuracy()) l.accuracy.toDouble() else null),
            "provider" to l.provider,
            "ts" to l.time
        ))
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(p: String?, s: Int, b: Bundle?) {}
    override fun onProviderEnabled(p: String) {
        emit(mapOf("type" to "gpsEnabled", "provider" to p, "ts" to System.currentTimeMillis()))
    }
    override fun onProviderDisabled(p: String) {
        emit(mapOf("type" to "gpsDisabled", "provider" to p, "ts" to System.currentTimeMillis()))
    }

    // ---- NFC ----
    private fun startNfc(): Boolean {
        val a = NfcAdapter.getDefaultAdapter(this) ?: return false
        if (!a.isEnabled) return false
        a.enableReaderMode(this, this,
            NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V, null)
        nfcOn = true
        return true
    }

    private fun stopNfc() {
        if (nfcOn) { NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this); nfcOn = false }
    }

    override fun onTagDiscovered(tag: Tag) {
        val uid = tag.id.joinToString("") { "%02X".format(it) }
        var text: String? = null
        try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                val rec = ndef.cachedNdefMessage?.records?.firstOrNull()
                if (rec != null) text = String(rec.payload, Charsets.UTF_8).trim { it.code < 32 }
                ndef.close()
            }
        } catch (_: Exception) {}
        emit(mapOf("type" to "nfc", "uid" to uid, "text" to text, "ts" to System.currentTimeMillis()))
    }

    // ---- Bildirim ----
    private fun showNotification(title: String, body: String, id: Int): Boolean {
        if (!granted("notifications")) return false
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(notifChannelId, "Yeşil Adım Bildirimleri", NotificationManager.IMPORTANCE_HIGH))
        }
        val n = NotificationCompat.Builder(this, notifChannelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title).setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true).build()
        nm.notify(id, n)
        return true
    }

    override fun onPause() { super.onPause(); stopSensors(); stopNfc() }

    override fun onDestroy() { stopSensors(); stopNfc(); super.onDestroy() }
}
