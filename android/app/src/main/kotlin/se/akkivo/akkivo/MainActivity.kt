package se.akkivo.akkivo

import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var speechReady = false
    private var player: MediaPlayer? = null
    private var pendingSpeech: MethodChannel.Result? = null
    private var pendingAudio: MethodChannel.Result? = null
    private var utteranceId: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private var keepOn = false
    private var visible = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this) { status -> speechReady = status == TextToSpeech.SUCCESS }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { finishSpeech(id, null) }
            @Deprecated("Android callback")
            override fun onError(id: String?) { finishSpeech(id, "Uppläsningen misslyckades. Kontrollera Androids talsyntesinställningar.") }
            override fun onError(id: String?, code: Int) { finishSpeech(id, "Uppläsningen misslyckades. Kontrollera Androids talsyntesinställningar.") }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "se.akkivo/device").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "keepScreenOn" -> { keepOn = call.arguments == true; applyScreen(); result.success(null) }
                    "stop" -> { stopMedia(); result.success(null) }
                    "speak" -> speak(call.arguments as String, result)
                    "playAudio" -> {
                        stopMedia()
                        val file = File(call.arguments as String).canonicalFile
                        val mediaRoot = File(filesDir, "media").canonicalFile
                        require(file.parentFile == mediaRoot && file.isFile) { "Ljudfilen saknas." }
                        val nextPlayer = MediaPlayer()
                        player = nextPlayer
                        pendingAudio = result
                        nextPlayer.apply {
                            setDataSource(file.path)
                            setOnCompletionListener {
                                pendingAudio?.success(null); pendingAudio = null
                                it.release(); if (player == it) player = null
                            }
                            setOnErrorListener { _, _, _ ->
                                val pending = pendingAudio; pendingAudio = null
                                stopMedia()
                                pending?.error("AUDIO_FAILED", "Ljudfilen kunde inte spelas upp. Välj ett ljudformat som Android stöder.", null)
                                true
                            }
                            prepare()
                            start()
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (pendingAudio == result) pendingAudio = null
                if (pendingSpeech == result) { pendingSpeech = null; utteranceId = null }
                stopMedia()
                result.error("DEVICE_ERROR", e.message ?: "Ljudet kunde inte spelas upp.", null)
            }
        }
    }

    private fun speak(text: String, result: MethodChannel.Result) {
        if (!speechReady) { result.error("TTS_UNAVAILABLE", "Talsyntesen är inte redo. Försök igen. Kontrollera att en talsyntesmotor är installerad i Androids inställningar.", null); return }
        stopMedia()
        val engine = tts!!
        val status = engine.setLanguage(Locale.forLanguageTag("sv-SE"))
        val voice = engine.voices?.firstOrNull { it.locale.language == "sv" && !it.isNetworkConnectionRequired && !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
        if (status == TextToSpeech.LANG_MISSING_DATA || status == TextToSpeech.LANG_NOT_SUPPORTED || voice == null) {
            result.error("TTS_LANGUAGE", "Svensk offlineröst saknas. Installera svenska röstdata via Androids inställningar för text-till-tal och öppna sedan Akkivo igen.", null)
            return
        }
        engine.voice = voice
        val id = System.nanoTime().toString()
        utteranceId = id
        pendingSpeech = result
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id) == TextToSpeech.ERROR) {
            finishSpeech(id, "Texten kunde inte läsas upp.")
        } else {
            handler.postDelayed({ if (utteranceId == id) { engine.stop(); finishSpeech(id, "Uppläsningen tog för lång tid. Försök med ett kortare meddelande.") } }, 120000)
        }
    }
    private fun finishSpeech(id: String?, error: String?) {
        runOnUiThread {
            if (id != utteranceId) return@runOnUiThread
            val result = pendingSpeech
            pendingSpeech = null; utteranceId = null
            if (error == null) result?.success(null) else result?.error("TTS_FAILED", error, null)
        }
    }
    private fun stopMedia() {
        tts?.stop()
        pendingSpeech?.success(null); pendingSpeech = null; utteranceId = null
        pendingAudio?.success(null); pendingAudio = null
        player?.release(); player = null
    }
    private fun applyScreen() {
        if (keepOn && visible) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onResume() { super.onResume(); visible = true; applyScreen() }
    override fun onPause() { visible = false; applyScreen(); stopMedia(); super.onPause() }
    override fun onDestroy() { stopMedia(); tts?.shutdown(); handler.removeCallbacksAndMessages(null); super.onDestroy() }
}
