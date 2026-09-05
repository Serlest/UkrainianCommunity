package at.uac.android

import android.os.Build
import android.os.Process
import android.util.AtomicFile
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryScope
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationDraft
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.firestore.FieldValue
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

/**
 * A single explicit recoverable fixture. The bounded marker contains only synthetic IDs and the
 * preparing PID.
 */
internal object AuthoringRecoveryFixtures {
    val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    const val PASSWORD = "Synthetic-authoring-recovery-only1!"
    private val marker
        get() = AtomicFile(File(context.noBackupFilesDir, "authoring-recovery-fixture-v1.bin"))

    data class Marker(
        val suffix: String,
        val uid: String,
        val contentId: String,
        val preparingPid: Int,
        val kind: ContentKind = ContentKind.NEWS,
    ) {
        val prefix
            get() = "author4c-$suffix"

        val organizationId
            get() = "$prefix-org"

        val email
            get() = "$prefix@example.invalid"

        val scope
            get() = AuthoringRecoveryScope(uid, organizationId, kind)

        fun valid() =
            canonical(suffix) &&
                uid.matches(Regex("[A-Za-z0-9_-]{1,128}")) &&
                (contentId.isEmpty() || canonical(contentId)) &&
                preparingPid > 0 &&
                kind in setOf(ContentKind.NEWS, ContentKind.EVENTS)
    }

    private fun canonical(value: String) = runCatching {
        UUID.fromString(value).toString() == value
    }
        .getOrDefault(false)

    fun requireAvd() {
        LocalEnvironment.requireSafe()
        check(context.packageName == "at.uac.android.local")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        )
    }

    fun exists(): Boolean {
        requireAvd()
        return listOf(
                marker.baseFile,
                File(marker.baseFile.path + ".bak"),
                File(marker.baseFile.path + ".new"),
            )
            .any { it.exists() }
    }

    fun read(): Marker {
        requireAvd()
        val bytes =
            marker.openRead().use { input ->
                check(input.channel.size() in 1..2_048)
                input.readBytes()
            }
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            check(input.readInt() == 0x55414331)
            val suffix = input.readUTF()
            val uid = input.readUTF()
            val id = input.readUTF()
            val pid = input.readInt()
            val collection = input.readUTF()
            Marker(suffix, uid, id, pid, ContentKind.entries.first { it.collection == collection })
                .also { check(it.valid() && input.read() == -1) }
        }
    }

    fun write(value: Marker) {
        requireAvd()
        check(value.valid())
        val bytes =
            ByteArrayOutputStream()
                .also { output ->
                    DataOutputStream(output).use {
                        it.writeInt(0x55414331)
                        it.writeUTF(value.suffix)
                        it.writeUTF(value.uid)
                        it.writeUTF(value.contentId)
                        it.writeInt(value.preparingPid)
                        it.writeUTF(value.kind.collection)
                    }
                }
                .toByteArray()
        check(bytes.size <= 2_048)
        val stream = marker.startWrite()
        try {
            stream.write(bytes)
            stream.fd.sync()
            marker.finishWrite(stream)
        } catch (error: Exception) {
            marker.failWrite(stream)
            throw error
        }
        check(read() == value)
    }

    fun fixture(value: Marker): AuthoringFixtures {
        check(value.valid())
        return AuthoringFixtures(value.prefix).apply {
            uids += value.uid
            rememberExisting("organizations/${value.organizationId}")
            if (value.contentId.isNotEmpty()) ownContent(value.kind, value.contentId)
        }
    }

    suspend fun create(kind: ContentKind = ContentKind.NEWS): Marker {
        requireAvd()
        check(!exists()) { "Previous authoring recovery fixture must be reconciled first" }
        AuthEmulatorFixtures.seedLegalReference()
        val suffix = UUID.randomUUID().toString()
        val email = "author4c-$suffix@example.invalid"
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        auth.signOut()
        val user =
            auth.createUserWithEmailAndPassword(email, PASSWORD).await().user
                ?: error("Synthetic identity missing")
        val owned = Marker(suffix, user.uid, "", Process.myPid(), kind)
        // Record the identity before verification/organization work can fail. Cleanup never loses
        // its exact target.
        withContext(Dispatchers.IO) { write(owned) }
        db.document("users/${user.uid}")
            .set(
                registeredProfileFields(
                    user.uid,
                    AuthRegistration(
                        email,
                        "Synthetic recovery owner",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                    FieldValue.serverTimestamp(),
                )
            )
            .await()
        user.sendEmailVerification().await()
        auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
        user.reload().await()
        user.getIdToken(true).await()
        check(user.isEmailVerified)
        val session = OrganizationSession(user.uid, 1, true, "Synthetic recovery owner", "user")
        val organization =
            OrganizationDraft(
                owned.organizationId,
                "Synthetic Recovery Organization",
                "An approved local recovery fixture",
                region = "wien",
                city = "Wien",
            )
        fixture(owned)
            .seed(
                "organizations/${owned.organizationId}",
                OrganizationContract.create(organization, session, Instant.now()) +
                    mapOf("ownerId" to user.uid, "moderationStatus" to "approved"),
            )
        return owned
    }

    /**
     * Pending must have a real matching receipt before caller invokes cleanup. Unknown cleanup
     * preserves marker.
     */
    suspend fun cleanup(): Unit =
        withContext(Dispatchers.IO) {
            requireAvd()
            val owned = read()
            val recovery = localAuthoringRecoveryStore(context)
            val local = recovery.load(owned.scope)
            check(local?.pending == null) {
                "Unconfirmed authoring intent retained with its synthetic account and marker"
            }
            local?.draft?.let {
                check(it.id == owned.contentId)
                recovery.discardUnsent(owned.scope, it.id)
            }
            check(recovery.load(owned.scope) == null)
            fixture(owned).cleanup()
            val paths =
                listOf(
                    "organizations/${owned.organizationId}",
                    "users/${owned.uid}",
                    "publicProfiles/${owned.uid}",
                ) +
                    listOfNotNull(
                        owned.contentId.takeIf(String::isNotEmpty)?.let {
                            "${owned.kind.collection}/$it"
                        }
                    )
            for (path in paths) check(AccountDeletionFixtures.document(path) == null) {
                "Exact synthetic cleanup not confirmed"
            }
            val auth = LocalFirebase.auth(context)
            if (auth.currentUser?.uid == owned.uid) auth.signOut()
            marker.delete()
            check(!exists())
        }
}
