package at.uac.android.feature.authoring.recovery

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal fun interface RecoveryKeyProvider {
    /** A missing decryption key is never silently regenerated. */
    fun key(mayCreate: Boolean): SecretKey
}

/** Only ciphertext and a non-secret UUID appear outside the authenticated body. */
internal class AuthoringRecoveryCipher(private val keys: RecoveryKeyProvider) {
    companion object {
        const val MAX_ENVELOPE_BYTES = AuthoringRecoveryCodec.MAX_BYTES + 128
    }

    private fun aad(
        scope: AuthoringRecoveryScope,
        purpose: RecoveryPurpose,
        id: String,
    ): ByteArray =
        ByteArrayOutputStream()
            .also { bytes ->
                DataOutputStream(bytes).use { output ->
                    listOf(
                            "uac-authoring-recovery-v1",
                            purpose.wire,
                            scope.uid,
                            scope.organizationId,
                            scope.kind.collection,
                            id,
                        )
                        .forEach {
                            val text = it.toByteArray(Charsets.UTF_8)
                            output.writeInt(text.size)
                            output.write(text)
                        }
                }
            }
            .toByteArray()

    fun encrypt(
        scope: AuthoringRecoveryScope,
        purpose: RecoveryPurpose,
        id: String,
        plain: ByteArray,
        mayCreateKey: Boolean,
    ): ByteArray = guarded {
        if (
            !RecoveryValidation.creationId(id) || plain.size !in 1..AuthoringRecoveryCodec.MAX_BYTES
        )
            RecoveryValidation.invalid()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keys.key(mayCreateKey))
        cipher.updateAAD(aad(scope, purpose, id))
        val encrypted = cipher.doFinal(plain)
        if (cipher.iv.size != 12) RecoveryValidation.invalid()
        ByteArrayOutputStream()
            .also { bytes ->
                DataOutputStream(bytes).use { output ->
                    output.writeInt(0x55414345)
                    output.writeByte(1)
                    output.write(id.toByteArray(Charsets.US_ASCII))
                    output.write(cipher.iv)
                    output.writeInt(encrypted.size)
                    output.write(encrypted)
                }
            }
            .toByteArray()
            .also { if (it.size > MAX_ENVELOPE_BYTES) RecoveryValidation.invalid() }
    }

    fun decrypt(
        scope: AuthoringRecoveryScope,
        purpose: RecoveryPurpose,
        envelope: ByteArray,
    ): Pair<String, ByteArray> = guarded {
        if (envelope.size !in 74..MAX_ENVELOPE_BYTES) RecoveryValidation.invalid()
        val input = DataInputStream(ByteArrayInputStream(envelope))
        if (input.readInt() != 0x55414345 || input.readUnsignedByte() != 1)
            RecoveryValidation.invalid()
        val id = ByteArray(36).also(input::readFully).toString(Charsets.US_ASCII)
        if (!RecoveryValidation.creationId(id)) RecoveryValidation.invalid()
        val nonce = ByteArray(12).also(input::readFully)
        val count = input.readInt()
        if (count !in 17..(AuthoringRecoveryCodec.MAX_BYTES + 16) || count != input.available())
            RecoveryValidation.invalid()
        val encrypted = ByteArray(count).also(input::readFully)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keys.key(false), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad(scope, purpose, id))
        id to cipher.doFinal(encrypted)
    }

    private inline fun <T> guarded(block: () -> T): T =
        try {
            block()
        } catch (error: AuthoringRecoveryException) {
            throw error
        } catch (error: Exception) {
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED, error)
        }
}
