package ai.viewbridge.vouch

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * No signature without a fingerprint.
 *
 * Runs on a device or emulator with a fingerprint enrolled
 * (`./gradlew connectedDebugAndroidTest` from app/android). CI has no
 * emulator, so this is the local gate; the Dart tests cover the app logic
 * above the Keystore (cancel sends nothing, decisions use the decision key).
 */
@RunWith(AndroidJUnit4::class)
class DeviceKeySecurityTest {
    private val store = "AndroidKeyStore"
    private val bound = "vouch.test.bound"
    private val plain = "vouch.test.plain"

    private fun keyStore() = KeyStore.getInstance(store).apply { load(null) }

    private fun generate(alias: String, requireUserAuth: Boolean) {
        val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setAttestationChallenge(ByteArray(32))
        if (requireUserAuth) {
            b.setUserAuthenticationRequired(true)
            b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            b.setInvalidatedByBiometricEnrollment(true)
        }
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, store).apply {
            initialize(b.build())
            generateKeyPair()
        }
    }

    private fun keyInfo(alias: String): KeyInfo {
        val entry = keyStore().getEntry(alias, null) as KeyStore.PrivateKeyEntry
        return KeyFactory.getInstance(entry.privateKey.algorithm, store)
            .getKeySpec(entry.privateKey, KeyInfo::class.java)
    }

    @After
    fun cleanUp() {
        val ks = keyStore()
        for (a in listOf(bound, plain)) if (ks.containsAlias(a)) ks.deleteEntry(a)
    }

    @Test
    fun boundKeyRefusesToSignWithoutAFingerprint() {
        generate(bound, requireUserAuth = true)
        val info = keyInfo(bound)
        assertTrue("key must require user authentication", info.isUserAuthenticationRequired)
        assertTrue(
            "key must be biometric-strong bound",
            info.userAuthenticationType and KeyProperties.AUTH_BIOMETRIC_STRONG != 0,
        )
        assertEquals("per-use (timeout 0)", 0, info.userAuthenticationValidityDurationSeconds)

        val entry = keyStore().getEntry(bound, null) as KeyStore.PrivateKeyEntry
        val sig = Signature.getInstance("SHA256withECDSA")
        try {
            // No BiometricPrompt, no CryptoObject: the Keystore must refuse at
            // init, update or sign. Any signature here would be a security bug.
            sig.initSign(entry.privateKey)
            sig.update("POST\n/v1/requests/x/decision".toByteArray())
            val bytes = sig.sign()
            fail("signed ${bytes.size} bytes without a fingerprint")
        } catch (e: UserNotAuthenticatedException) {
            // Android 11-13 report it this way.
        } catch (e: java.security.SignatureException) {
            // Android 14+ wrap keystore2's refusal: "Key user not authenticated (-26)".
            assertTrue(
                "unexpected refusal: ${e.message}",
                (e.message ?: "").contains("not authenticated", ignoreCase = true),
            )
        }
    }

    @Test
    fun plainKeySignsWithoutAPrompt() {
        generate(plain, requireUserAuth = false)
        assertFalse(keyInfo(plain).isUserAuthenticationRequired)
        val entry = keyStore().getEntry(plain, null) as KeyStore.PrivateKeyEntry
        val msg = "GET\n/v1/devices/me".toByteArray()
        val der = Signature.getInstance("SHA256withECDSA").run {
            initSign(entry.privateKey); update(msg); sign()
        }
        assertEquals(0x30, der[0].toInt())
        val ok = Signature.getInstance("SHA256withECDSA").run {
            initVerify(keyStore().getCertificate(plain).publicKey); update(msg); verify(der)
        }
        assertTrue("transport-style key must verify", ok)
    }

    @Test
    fun boundKeyAttestsThatItNeedsTheUser() {
        generate(bound, requireUserAuth = true)
        val chain = keyStore().getCertificateChain(bound)
        assertTrue("attestation chain present", chain != null && chain.size >= 2)
        // The server parses the extension; here we only check it exists
        // on the leaf, which the emulator's software attestation still emits.
        val ext = (chain!![0] as java.security.cert.X509Certificate)
            .getExtensionValue("1.3.6.1.4.1.11129.2.1.17")
        assertTrue("leaf carries the Android attestation extension", ext != null)
    }
}
