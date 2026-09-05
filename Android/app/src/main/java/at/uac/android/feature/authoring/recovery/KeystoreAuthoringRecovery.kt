package at.uac.android.feature.authoring.recovery

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.CompiledBackend
import java.io.File
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

internal class AndroidRecoveryKeys(private val alias: String) : RecoveryKeyProvider {
    override fun key(mayCreate: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias))
            return (store.getKey(alias, null) as? SecretKey)
                ?: throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED)
        if (!mayCreate) throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                            alias,
                            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                        )
                        .setKeySize(256)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setRandomizedEncryptionRequired(true)
                        .build()
                )
            }
            .generateKey()
    }
}

private object LocalRecoveryInstance {
    private var value: AuthoringRecoveryStore? = null

    @Synchronized
    fun instance(context: Context): AuthoringRecoveryStore {
        LocalEnvironment.requireSafe()
        val app = context.applicationContext
        CompiledBackend.configuration.requireAndroidPackage(app.packageName)
        return value
            ?: FileAuthoringRecoveryStore(
                    File(app.noBackupFilesDir, "authoring-recovery-v1").canonicalFile,
                    AuthoringRecoveryCipher(AndroidRecoveryKeys("uac.authoring.recovery.v1")),
                )
                .also { value = it }
    }
}

/** No backups, plaintext files, cloud synchronization or Firebase initialization. */
fun localAuthoringRecoveryStore(context: Context): AuthoringRecoveryStore =
    LocalRecoveryInstance.instance(context)
