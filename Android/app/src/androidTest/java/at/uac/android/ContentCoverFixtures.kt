package at.uac.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.contentmedia.ContentCoverTarget
import at.uac.android.feature.contentmedia.PreparedContentCover
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.FieldValue
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.util.Random
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

/**
 * Authoring fixture's exact-path/account scope plus only individually registered canonical cover
 * objects.
 */
internal class ContentCoverFixtures(private val prefix: String) {
    val data = AuthoringFixtures(prefix)
    val organizationId
        get() = data.organizationId

    val foreignOrganizationId
        get() = data.foreignOrganizationId

    val password = "Synthetic-cover-local-only!"
    private val targets = linkedSetOf<ContentCoverTarget>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    data class Account(val uid: String, val email: String)

    fun register(kind: ContentKind, foreign: Boolean = false): ContentCoverTarget {
        val target =
            ContentCoverTarget(
                if (foreign) foreignOrganizationId else organizationId,
                kind,
                UUID.randomUUID().toString(),
            )
        data.ownContent(kind, target.contentId)
        targets += target
        return target
    }

    suspend fun account(label: String, verified: Boolean = true): Account {
        require(label.matches(Regex("[a-z]{1,20}")))
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        auth.signOut()
        val email = "$prefix-$label@example.invalid"
        val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
        data.uids += user.uid
        db.document("users/${user.uid}")
            .set(
                registeredProfileFields(
                    user.uid,
                    AuthRegistration(
                        email,
                        "Synthetic $label",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                    FieldValue.serverTimestamp(),
                )
            )
            .await()
        if (verified) {
            user.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            user.reload().await()
            user.getIdToken(true).await()
            check(user.isEmailVerified)
        }
        data.seed(
            "publicProfiles/${user.uid}",
            mapOf(
                "id" to user.uid,
                "displayName" to "Public $label",
                "city" to "Wien",
                "updatedAt" to Instant.now(),
            ),
        )
        return Account(user.uid, email)
    }

    suspend fun organization(
        owner: Account,
        admins: List<Account> = emptyList(),
        moderators: List<Account> = emptyList(),
        foreign: Boolean = false,
    ) {
        val id = if (foreign) foreignOrganizationId else organizationId
        val basics =
            OrganizationDraft(
                id,
                "Synthetic Cover Organization",
                "A complete synthetic cover organization",
                region = "wien",
                city = "Wien",
            )
        data.seed(
            "organizations/$id",
            OrganizationContract.create(
                basics,
                OrganizationSession(owner.uid, 1, true, "Synthetic owner", "user"),
                Instant.now(),
            ) +
                mapOf(
                    "ownerId" to owner.uid,
                    "moderationStatus" to "approved",
                    "adminIds" to admins.map { it.uid },
                    "moderatorIds" to moderators.map { it.uid },
                ),
        )
    }

    suspend fun storageStatus(target: ContentCoverTarget, method: String): Int =
        withContext(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            check(target in targets && method in setOf("GET", "DELETE"))
            val encoded = URLEncoder.encode(target.path, "UTF-8")
            val connection =
                URL("http://10.0.2.2:9198/v0/b/${LocalStorage.BUCKET}/o/$encoded").openConnection()
                    as HttpURLConnection
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                connection.responseCode
            } finally {
                connection.disconnect()
            }
        }

    suspend fun cleanup(previous: Throwable?) {
        var failure = previous
        for (target in targets) {
            try {
                check(storageStatus(target, "DELETE") in setOf(200, 204, 404)) {
                    "Scoped cover cleanup failed"
                }
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
        }
        try {
            data.cleanup(failure)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        if (previous == null && failure != null) throw failure
    }

    companion object {
        suspend fun noisyPhoto(seed: Long): PreparedContentCover =
            withContext(Dispatchers.Default) {
                val image = Bitmap.createBitmap(1600, 900, Bitmap.Config.ARGB_8888)
                val original =
                    try {
                        val random = Random(seed)
                        val paint = Paint()
                        Canvas(image).apply {
                            for (y in 0 until 900 step 4) for (x in 0 until 1600 step 4) {
                                paint.color = random.nextInt() or (0xff shl 24)
                                drawRect(
                                    x.toFloat(),
                                    y.toFloat(),
                                    (x + 4).toFloat(),
                                    (y + 4).toFloat(),
                                    paint,
                                )
                            }
                        }
                        ByteArrayOutputStream().use {
                            image.compress(Bitmap.CompressFormat.PNG, 100, it)
                            it.toByteArray()
                        }
                    } finally {
                        image.recycle()
                    }
                val bytes =
                    LocalImagePreparation.prepareBytes(
                        original,
                        LocalImagePolicy.CONTENT_COVER_16_9,
                    )
                PreparedContentCover(bytes, 1600, 900)
            }
    }
}
