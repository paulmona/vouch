package ai.viewbridge.vouch

import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.UserNotAuthenticatedException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.ProviderException
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * The device keys, in the Android Keystore. Private keys never leave it.
 *
 * Two kinds of key, chosen per alias by `requireUserAuth` at generation:
 *  - a fingerprint-bound key (`setUserAuthenticationParameters(0, BIOMETRIC_STRONG)`):
 *    every signature needs a fresh fingerprint inside a BiometricPrompt
 *    CryptoObject. There is no code path that signs with it otherwise; the
 *    Keystore refuses (UserNotAuthenticatedException).
 *  - a plain key: signs without a prompt, for calls nobody is looking at.
 *
 * StrongBox is used where the device has it, with a fallback to the TEE.
 * Keys carry an attestation chain with the caller's challenge.
 *
 * Methods (all arguments by name):
 *  generate(alias, challenge: bytes, requireUserAuth: bool)
 *      -> {publicKey: bytes(SPKI), attestationChain: [bytes], strongBox: bool, userAuthRequired: bool}
 *  exists(alias) -> bool
 *  delete(alias)
 *  publicKey(alias) -> bytes(SPKI)
 *  attestationChain(alias) -> [bytes]
 *  info(alias) -> {strongBox: bool, userAuthRequired: bool}
 *  biometricStatus() -> "available" | "none_enrolled" | "no_hardware" | "unavailable"
 *  sign(alias, message: bytes, title, subtitle?, negativeButton) -> bytes(DER)
 *
 * Errors (MethodChannel error codes): no_key, cancelled, lockout, none_enrolled,
 * key_invalidated, not_authenticated, keystore.
 */
class DeviceKeyChannel(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "ai.viewbridge.vouch/device_key"
        private const val STORE = "AndroidKeyStore"

        fun register(activity: FragmentActivity, engine: FlutterEngine) {
            MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
                .setMethodCallHandler(DeviceKeyChannel(activity))
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(STORE).apply { load(null) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "generate" -> generate(call, result)
                "exists" -> result.success(keyStore().containsAlias(alias(call)))
                "delete" -> {
                    keyStore().deleteEntry(alias(call))
                    result.success(null)
                }
                "publicKey" -> result.success(publicKey(alias(call)))
                "attestationChain" -> result.success(attestationChain(alias(call)))
                "info" -> result.success(info(alias(call)))
                "biometricStatus" -> result.success(biometricStatus())
                "sign" -> sign(call, result)
                else -> result.notImplemented()
            }
        } catch (e: NoKeyException) {
            result.error("no_key", e.message, null)
        } catch (e: Exception) {
            result.error("keystore", e.message ?: e.javaClass.simpleName, e.javaClass.simpleName)
        }
    }

    private class NoKeyException(alias: String) : Exception("No key with alias $alias")

    private fun alias(call: MethodCall): String =
        call.argument<String>("alias") ?: throw IllegalArgumentException("alias is required")

    // ---- generation --------------------------------------------------------

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val alias = alias(call)
        val challenge = call.argument<ByteArray>("challenge")
            ?: throw IllegalArgumentException("challenge is required")
        val requireUserAuth = call.argument<Boolean>("requireUserAuth")
            ?: throw IllegalArgumentException("requireUserAuth is required")

        // Key generation can take a moment (longer in StrongBox); keep the UI thread free.
        Thread {
            try {
                val map = generateBlocking(alias, challenge, requireUserAuth)
                activity.runOnUiThread { result.success(map) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("keystore", e.message ?: e.javaClass.simpleName, e.javaClass.simpleName)
                }
            }
        }.start()
    }

    private fun generateBlocking(alias: String, challenge: ByteArray, requireUserAuth: Boolean): Map<String, Any> {
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)

        val hasStrongBox = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        var strongBox = hasStrongBox

        fun spec(useStrongBox: Boolean): KeyGenParameterSpec {
            val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setAttestationChallenge(challenge)
            if (requireUserAuth) {
                b.setUserAuthenticationRequired(true)
                // timeout 0 = authenticate for every single use, biometric only (class 3).
                b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                // A newly enrolled fingerprint kills the key: re-pairing is the only way back.
                b.setInvalidatedByBiometricEnrollment(true)
            }
            if (useStrongBox) b.setIsStrongBoxBacked(true)
            return b.build()
        }

        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, STORE)
        try {
            kpg.initialize(spec(strongBox))
            kpg.generateKeyPair()
        } catch (e: Exception) {
            // StrongBoxUnavailableException, or a ProviderException wrapping it on some devices.
            if (strongBox && (e is StrongBoxUnavailableException || e is ProviderException)) {
                strongBox = false
                kpg.initialize(spec(false))
                kpg.generateKeyPair()
            } else {
                throw e
            }
        }

        return mapOf(
            "publicKey" to publicKey(alias),
            "attestationChain" to attestationChain(alias),
            "strongBox" to strongBox,
            "userAuthRequired" to requireUserAuth,
        )
    }

    // ---- inspection --------------------------------------------------------

    private fun publicKey(alias: String): ByteArray {
        val cert = keyStore().getCertificate(alias) ?: throw NoKeyException(alias)
        return cert.publicKey.encoded // X.509 SubjectPublicKeyInfo, DER
    }

    private fun attestationChain(alias: String): List<ByteArray> {
        val chain = keyStore().getCertificateChain(alias) ?: throw NoKeyException(alias)
        return chain.map { it.encoded } // leaf first
    }

    private fun keyInfo(alias: String): KeyInfo {
        val entry = keyStore().getEntry(alias, null) as? KeyStore.PrivateKeyEntry ?: throw NoKeyException(alias)
        val factory = KeyFactory.getInstance(entry.privateKey.algorithm, STORE)
        return factory.getKeySpec(entry.privateKey, KeyInfo::class.java)
    }

    private fun info(alias: String): Map<String, Any> {
        val ki = keyInfo(alias)
        val strongBox = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ki.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            @Suppress("DEPRECATION")
            ki.isInsideSecureHardware
        }
        return mapOf("strongBox" to strongBox, "userAuthRequired" to ki.isUserAuthenticationRequired)
    }

    private fun biometricStatus(): String =
        when (BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none_enrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE,
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "no_hardware"
            else -> "unavailable"
        }

    // ---- signing -----------------------------------------------------------

    private fun sign(call: MethodCall, result: MethodChannel.Result) {
        val alias = alias(call)
        val message = call.argument<ByteArray>("message") ?: throw IllegalArgumentException("message is required")
        val title = call.argument<String>("title") ?: "Confirm"
        val subtitle = call.argument<String>("subtitle")
        val negative = call.argument<String>("negativeButton") ?: "Cancel"

        val entry = keyStore().getEntry(alias, null) as? KeyStore.PrivateKeyEntry ?: throw NoKeyException(alias)
        val signature = Signature.getInstance("SHA256withECDSA")
        try {
            signature.initSign(entry.privateKey)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometric enrolment changed since pairing. The key is gone for good.
            keyStore().deleteEntry(alias)
            result.error("key_invalidated", "The fingerprint set on this phone changed; pair again.", null)
            return
        }

        if (!keyInfo(alias).isUserAuthenticationRequired) {
            signature.update(message)
            result.success(signature.sign())
            return
        }

        // Fingerprint-bound: the operation only completes inside an authenticated CryptoObject.
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                try {
                    val sig = auth.cryptoObject?.signature
                        ?: throw IllegalStateException("No CryptoObject on the authentication result")
                    sig.update(message)
                    result.success(sig.sign())
                } catch (e: UserNotAuthenticatedException) {
                    result.error("not_authenticated", e.message, null)
                } catch (e: Exception) {
                    result.error("keystore", e.message ?: e.javaClass.simpleName, e.javaClass.simpleName)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val code = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    BiometricPrompt.ERROR_NO_BIOMETRICS -> "none_enrolled"
                    else -> "biometric"
                }
                result.error(code, errString.toString(), errorCode)
            }

            // onAuthenticationFailed: a finger that did not match. The sheet stays up; nothing to do.
        }

        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply { if (subtitle != null) setSubtitle(subtitle) }
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(signature))
    }
}
