package com.comunikte.comunikte

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.comunikte/audio_bridge"
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { /* Non-intrusive focus management */ }
    private var loudnessEnhancer: LoudnessEnhancer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBluetoothSco" -> {
                    val success = startSco()
                    result.success(success)
                }
                "stopBluetoothSco" -> {
                    stopSco()
                    result.success(true)
                }
                "isBluetoothScoOn" -> {
                    result.success(audioManager?.isBluetoothScoOn ?: false)
                }
                "setCommunicationMode" -> {
                    audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
                    result.success(true)
                }
                "setSpeakerphone" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    audioManager?.isSpeakerphoneOn = enable
                    result.success(true)
                }
                "requestDuckFocus" -> {
                    val focused = requestDuckingAudioFocus()
                    result.success(focused)
                }
                "setKeepScreenOn" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    if (enable) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
                "setSoftwareGain" -> {
                    val gain = call.argument<Double>("gain") ?: 1.0
                    setSoftwareGain(gain)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startSco(): Boolean {
        return try {
            val am = audioManager ?: return false
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            am.startBluetoothSco()
            am.isBluetoothScoOn = true
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun stopSco() {
        try {
            releaseLoudnessEnhancer()
            val am = audioManager ?: return
            am.stopBluetoothSco()
            am.isBluetoothScoOn = false
            am.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setSoftwareGain(gain: Double) {
        try {
            val am = audioManager ?: return
            if (gain <= 0.0) {
                loudnessEnhancer?.enabled = false
                loudnessEnhancer?.setTargetGain(0)
                return
            }

            // Aplicar volumen a la llamada de voz (STREAM_VOICE_CALL)
            val maxCallVol = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val targetCallVol = (maxCallVol * gain.coerceAtMost(1.0)).toInt().coerceIn(1, maxCallVol)
            am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, targetCallVol, 0)

            // Si gain > 1.0 (150% RUTA, 200% MAX), activar LoudnessEnhancer con ganancia intensa
            if (gain > 1.0) {
                if (loudnessEnhancer == null) {
                    try {
                        loudnessEnhancer = LoudnessEnhancer(0)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                // 1.5x -> 1500 mB (+15 dB)
                // 2.0x -> 3000 mB (+30 dB boost masivo)
                val targetMb = when {
                    gain <= 1.5 -> ((gain - 1.0) / 0.5 * 1500.0).toInt()
                    else -> (1500.0 + ((gain - 1.5) / 0.5 * 1500.0)).toInt()
                }.coerceIn(0, 3500)

                loudnessEnhancer?.enabled = true
                loudnessEnhancer?.setTargetGain(targetMb)
            } else {
                loudnessEnhancer?.setTargetGain(0)
                loudnessEnhancer?.enabled = false
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseLoudnessEnhancer() {
        try {
            loudnessEnhancer?.enabled = false
            loudnessEnhancer?.release()
            loudnessEnhancer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun requestDuckingAudioFocus(): Boolean {
        val am = audioManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(playbackAttributes)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .setAcceptsDelayedFocusGain(true)
                .setWillPauseWhenDucked(false)
                .build()
            focusRequest = req
            val res = am.requestAudioFocus(req)
            res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val res = am.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
            res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    override fun onDestroy() {
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        releaseLoudnessEnhancer()
        stopSco()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        }
        super.onDestroy()
    }
}
