package im.galmax.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var methodChannel: MethodChannel? = null
    private var ringChannel: MethodChannel? = null
    private var isListening = false

    // Call ring player state
    private var incomingRingtone: Ringtone? = null
    private var outgoingRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    // Proximity wake lock (like Element Android's CallProximityManager)
    private var proximityWakeLock: PowerManager.WakeLock? = null

    // Vibration pattern: pause 0ms -> vibrate 400ms -> pause 600ms (repeat)
    private val VIBRATE_PATTERN = longArrayOf(0, 400, 600)

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Proximity channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "galmax/proximity")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startProximity" -> {
                    startProximitySensor()
                    result.success(true)
                }
                "stopProximity" -> {
                    stopProximitySensor()
                    result.success(true)
                }
                "setAudioRoute" -> {
                    val route = call.arguments as? String
                    setAudioRoute(route)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Call ring channel
        ringChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "im.galmax.app/call_ring")
        ringChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startIncomingRing" -> {
                    val started = startIncomingRing()
                    result.success(started)
                }
                "startOutgoingRing" -> {
                    val started = startOutgoingRing()
                    result.success(started)
                }
                "stopRing" -> {
                    stopAllRings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startProximitySensor() {
        if (isListening) return

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        if (proximitySensor != null) {
            sensorManager?.registerListener(
                this,
                proximitySensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            isListening = true
        }
    }

    private fun stopProximitySensor() {
        if (!isListening) return
        sensorManager?.unregisterListener(this)
        isListening = false
    }

    private fun setAudioRoute(route: String?) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        when (route) {
            "earpiece" -> {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = false
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            }
            "speaker" -> {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = true
                audioManager.mode = AudioManager.MODE_NORMAL
            }
            "normal" -> {
                audioManager.mode = AudioManager.MODE_NORMAL
            }
        }
    }

    // ============ Call Ring Player ============

    /**
     * Start incoming call ring using system ringtone (like SchildiChat).
     * Uses RingtoneManager.getDefaultUri(TYPE_RINGTONE) for system sound.
     * Vibration pattern: [0, 400, 600]
     */
    private fun startIncomingRing(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val ringerMode = audioManager.ringerMode

        when (ringerMode) {
            AudioManager.RINGER_MODE_NORMAL -> {
                // Play system ringtone
                val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                incomingRingtone = RingtoneManager.getRingtone(this, ringtoneUri)

                // On Android P+ make it loop
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    incomingRingtone?.isLooping = true
                }
                incomingRingtone?.play()

                // Also start vibration
                startVibration()
            }
            AudioManager.RINGER_MODE_VIBRATE -> {
                // Only vibration, no sound
                startVibration()
            }
            AudioManager.RINGER_MODE_SILENT -> {
                // Do nothing
            }
        }
        return true
    }

    /**
     * Start outgoing call ring using custom ring.ogg file.
     * Uses system Ringtone with the raw resource URI.
     */
    private fun startOutgoingRing(): Boolean {
        val ringtoneUri = Uri.parse("android.resource://$packageName/${R.raw.call}")
        outgoingRingtone = RingtoneManager.getRingtone(this, ringtoneUri)

        // On Android P+ make it loop
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            outgoingRingtone?.isLooping = true
        }
        outgoingRingtone?.play()
        return true
    }

    /**
     * Start vibration with pattern [0, 400, 600]
     */
    private fun startVibration() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibrator = vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(VIBRATE_PATTERN, 0) // 0 = repeat
            vibrator?.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(VIBRATE_PATTERN, 0) // 0 = repeat
        }
    }

    /**
     * Stop all ringing sounds and vibration
     */
    private fun stopAllRings() {
        incomingRingtone?.stop()
        incomingRingtone = null
        outgoingRingtone?.stop()
        outgoingRingtone = null
        vibrator?.cancel()
        vibrator = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_PROXIMITY) {
            val distance = event.values[0]
            val maxDistance = proximitySensor?.maximumRange ?: 5.0f
            val isNear = distance < maxDistance / 2

            // Handle proximity wake lock (like Element Android's CallProximityManager)
            if (isNear) {
                acquireProximityWakeLock()
            } else {
                releaseProximityWakeLock()
            }

            methodChannel?.invokeMethod("proximityChanged", isNear)
        }
    }

    private fun acquireProximityWakeLock() {
        if (proximityWakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        proximityWakeLock = powerManager.newWakeLock(
            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
            "galmax:proximity"
        )
        proximityWakeLock?.acquire(60_000L) // 1 minute timeout
    }

    private fun releaseProximityWakeLock() {
        proximityWakeLock?.takeIf { it.isHeld }?.release()
        proximityWakeLock = null
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        stopProximitySensor()
        releaseProximityWakeLock()
        stopAllRings()
        super.onDestroy()
    }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            return eng
        }
    }
}
