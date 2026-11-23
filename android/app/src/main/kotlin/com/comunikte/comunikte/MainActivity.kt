package com.comunikte.comunikte

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.comunikte/audio_bridge"
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { /* Non-intrusive focus management */ }

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
            val am = audioManager ?: return
            am.stopBluetoothSco()
            am.isBluetoothScoOn = false
            am.mode = AudioManager.MODE_NORMAL
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
        stopSco()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        }
        super.onDestroy()
    }
}
