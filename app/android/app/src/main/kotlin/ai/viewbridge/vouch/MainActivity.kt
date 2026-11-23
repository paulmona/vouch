package ai.viewbridge.vouch

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity, not FlutterActivity: androidx BiometricPrompt needs
// a FragmentActivity to host the system fingerprint sheet.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceKeyChannel.register(this, flutterEngine)
        AppSettingsChannel.register(this, flutterEngine)
        PairLinkChannel.register(flutterEngine, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        PairLinkChannel.deliver(intent)
    }
}
