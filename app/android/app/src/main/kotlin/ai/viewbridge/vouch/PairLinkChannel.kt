package ai.viewbridge.vouch

import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands `vouch://pair?...` links to Dart: the one the activity was started
 * with (`initialLink`, read once) and any that arrive while it is running
 * (`link` calls). Only the link text crosses; the Dart side parses it and
 * asks before pairing, so a tapped link never pairs on its own.
 */
object PairLinkChannel {
    private const val NAME = "ai.viewbridge.vouch/pair_link"
    private var channel: MethodChannel? = null
    private var pending: String? = null

    fun register(engine: FlutterEngine, launchIntent: Intent?) {
        pending = linkFrom(launchIntent)
        Log.d("VouchPairLink", "register: initial=" + (pending != null))
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, NAME).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialLink" -> {
                        result.success(pending)
                        pending = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun deliver(intent: Intent?) {
        val link = linkFrom(intent)
        Log.d("VouchPairLink", "deliver: action=" + intent?.action + " matched=" + (link != null) + " channel=" + (channel != null))
        if (link == null) return
        val ch = channel
        if (ch == null) pending = link else ch.invokeMethod("link", link)
    }

    private fun linkFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return if (uri.scheme == "vouch" && uri.host == "pair") uri.toString() else null
    }
}
