package at.uac.android.feature.reminders

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.gateFor
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.decodeContent
import at.uac.android.feature.browse.string
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.inbox.decodeInboxPreferences
import at.uac.android.feature.safety.SafetyContract
import at.uac.android.feature.safety.safetyAuthor
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await

/** Read-only, named demo backend. A cold receiver never constructs/restores an AuthStore. */
class LocalReminderSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
    private val clock: () -> Instant = Instant::now,
) : ReminderSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    override fun currentOwner(): String? =
        auth.currentUser?.takeUnless { it.isAnonymous }?.uid?.let(::reminderOwner)

    private fun requireUid(owner: String, current: () -> Boolean): String {
        val user = auth.currentUser ?: throw ReminderException(ReminderFailure.NOT_READY)
        if (!current() || reminderOwner(user.uid) != owner)
            throw ReminderException(ReminderFailure.STALE)
        if (user.isAnonymous || !user.isEmailVerified)
            throw ReminderException(ReminderFailure.NOT_READY)
        return user.uid
    }

    private suspend fun authorize(owner: String, current: () -> Boolean): String {
        val expected = requireUid(owner, current)
        val user = auth.currentUser ?: throw ReminderException(ReminderFailure.NOT_READY)
        user.reload().await()
        if (requireUid(owner, current) != expected) throw ReminderException(ReminderFailure.STALE)
        val token = user.getIdToken(true).await()
        val profiles = FirestoreAuthProfiles(db)
        val (profile, legal) =
            coroutineScope {
                val profile = async { profiles.fetch(expected) }
                val legal = async { profiles.legalDocuments() }
                profile.await() to legal.await()
            }
        val totp = (token.claims["firebase"] as? Map<*, *>)?.get("sign_in_second_factor") == "totp"
        if (
            requireUid(owner, current) != expected ||
                gateFor(profile, totp, legal) != AuthGate.READY
        )
            throw ReminderException(ReminderFailure.NOT_READY)
        // This authorizes only a generic reminder. No public profile recovery, writes, or persisted
        // READY.
        return expected
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun fields(doc: DocumentSnapshot): Fields? {
        if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites())
            throw ReminderException(ReminderFailure.OFFLINE)
        return doc.data?.let { convert(it) as Fields }
    }

    private suspend fun preferences(uid: String): InboxPreferences =
        decodeInboxPreferences(
            fields(
                db.document("users/$uid/notificationPreferences/settings")
                    .get(Source.SERVER)
                    .await()
            )
        )

    private suspend fun blockedOrganizations(uid: String, current: () -> Boolean): Set<String> {
        if (requireUid(reminderOwner(uid), current) != uid)
            throw ReminderException(ReminderFailure.STALE)
        val result =
            functions
                .getHttpsCallable("getBlockedOrganizations")
                .withTimeout(6, TimeUnit.SECONDS)
                .call(emptyMap<String, Any>())
                .await()
                .data
        if (requireUid(reminderOwner(uid), current) != uid)
            throw ReminderException(ReminderFailure.STALE)
        return SafetyContract.organizations(result).map { it.id }.toSet()
    }

    private suspend fun visible(content: Content, uid: String, blocked: Set<String>): Boolean {
        val organization = content.fields.string("organizationId")
        if (!reminderId(organization) || organization in blocked) return false
        val author = safetyAuthor(content) ?: return true
        if (!reminderId(author)) throw ReminderException(ReminderFailure.INVALID)
        val block = db.document("users/$uid/blockedUsers/$author").get(Source.SERVER).await()
        val fields = fields(block) ?: return true
        SafetyContract.user(
            RawDocument(block.id, fields)
        ) // A malformed block is not an empty policy.
        return false
    }

    override suspend fun snapshot(
        session: ReminderSession,
        current: () -> Boolean,
    ): ReminderSnapshot = request {
        if (!session.ready || !reminderId(session.uid))
            throw ReminderException(ReminderFailure.NOT_READY)
        val owner = reminderOwner(session.uid)
        if (authorize(owner, current) != session.uid) throw ReminderException(ReminderFailure.STALE)
        val prefs = preferences(session.uid)
        if (!prefs.notificationsEnabled || !prefs.eventRemindersEnabled) {
            requireUid(owner, current)
            return@request ReminderSnapshot(session, prefs, emptyList(), true, clock())
        }
        val blocked = blockedOrganizations(session.uid, current)
        val eventIds = mutableListOf<String>()
        var after: String? = null
        while (true) {
            requireUid(owner, current)
            var query =
                db.collection("registrations")
                    .whereEqualTo("userId", session.uid)
                    .orderBy(FieldPath.documentId())
                    .limit(51)
            after?.let { query = query.startAfter(it) }
            val page = query.get(Source.SERVER).await()
            val selected = page.documents.take(50)
            selected.forEach { doc ->
                val f = fields(doc) ?: throw ReminderException(ReminderFailure.INVALID)
                val event = f.string("eventId")
                if (
                    !reminderId(event) ||
                        doc.id != CommunityContract.registrationId(event, session.uid) ||
                        f["id"] != doc.id ||
                        f["userId"] != session.uid ||
                        f["registeredAt"] !is Instant ||
                        after?.let { doc.id <= it } == true
                )
                    throw ReminderException(ReminderFailure.INVALID)
                eventIds += event
            }
            if (eventIds.size > REMINDER_MAX_EVENTS || eventIds.distinct().size != eventIds.size)
                throw ReminderException(ReminderFailure.LIMIT)
            if (page.size() <= 50) break
            if (selected.isEmpty() || selected.last().id == after)
                throw ReminderException(ReminderFailure.INVALID)
            after = selected.last().id
        }
        val contents = mutableListOf<Content>()
        for (ids in eventIds.chunked(10)) {
            requireUid(owner, current)
            val docs =
                db.collection("events")
                    .whereIn(FieldPath.documentId(), ids)
                    .whereEqualTo("moderationStatus", "approved")
                    .whereEqualTo("sourceType", "organization")
                    .get(Source.SERVER)
                    .await()
                    .documents
            for (doc in docs) {
                if (doc.id !in ids) throw ReminderException(ReminderFailure.INVALID)
                val content =
                    decodeContent(
                        ContentKind.EVENTS,
                        RawDocument(
                            doc.id,
                            fields(doc) ?: throw ReminderException(ReminderFailure.INVALID),
                        ),
                    )
                if (visible(content, session.uid, blocked)) contents += content
            }
        }
        val now = clock()
        val candidates = contents.mapNotNull { ReminderPlanner.candidate(it, prefs, now) }
        requireUid(owner, current)
        ReminderSnapshot(session, prefs, candidates, true, now)
    }

    override suspend fun verify(ticket: ReminderTicket, current: () -> Boolean): ConfirmedReminder =
        request {
            if (!ticket.due(clock())) throw ReminderException(ReminderFailure.EXPIRED)
            val uid = authorize(ticket.owner, current)
            val prefs = preferences(uid)
            if (!prefs.notificationsEnabled || !prefs.eventRemindersEnabled)
                throw ReminderException(ReminderFailure.SUPPRESSED)
            if (ticket.localTest) {
                // Explicit local test has no event target and never pretends to be a remote push.
                requireUid(ticket.owner, current)
                return@request ConfirmedReminder(ticket, null, clock())
            }
            if (!reminderId(ticket.eventId)) throw ReminderException(ReminderFailure.INVALID)
            val registration =
                db.collection("registrations")
                    .document(CommunityContract.registrationId(ticket.eventId, uid))
                    .get(Source.SERVER)
                    .await()
            val marker = fields(registration) ?: throw ReminderException(ReminderFailure.SUPPRESSED)
            if (
                marker["id"] != registration.id ||
                    marker["userId"] != uid ||
                    marker["eventId"] != ticket.eventId ||
                    marker["registeredAt"] !is Instant
            )
                throw ReminderException(ReminderFailure.INVALID)
            val event = db.collection("events").document(ticket.eventId).get(Source.SERVER).await()
            val content =
                decodeContent(
                    ContentKind.EVENTS,
                    RawDocument(
                        event.id,
                        fields(event) ?: throw ReminderException(ReminderFailure.SUPPRESSED),
                    ),
                )
            val blocked = blockedOrganizations(uid, current)
            if (
                !visible(content, uid, blocked) ||
                    !ReminderPlanner.matches(ticket, content, prefs, clock())
            )
                throw ReminderException(ReminderFailure.SUPPRESSED)
            requireUid(ticket.owner, current)
            ConfirmedReminder(ticket, content, clock())
        }

    private suspend fun <T> request(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: ReminderException) {
            throw error
        } catch (_: Exception) {
            throw ReminderException(ReminderFailure.OFFLINE)
        }
}

fun localReminderSource(context: Context): ReminderSource =
    LocalReminderSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )
