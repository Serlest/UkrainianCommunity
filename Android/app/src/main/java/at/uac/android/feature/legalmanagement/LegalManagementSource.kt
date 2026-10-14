package at.uac.android.feature.legalmanagement

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.LegalDocumentIntegrity
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.moderation.moderationScope
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import kotlinx.coroutines.tasks.await

data class LegalLocale(val title: String, val markdown: String)

data class ManagedLegalVersion(
    val type: String,
    val version: String,
    val versionNumber: Long,
    val contentHash: String,
    val locales: Map<String, LegalLocale>,
    val summary: String?,
    val supersedes: String?,
    val status: String,
)

data class ManagedLegalDocument(val active: ManagedLegalVersion, val draft: ManagedLegalVersion?)

data class LegalDraftInput(
    val type: String,
    val version: String,
    val versionNumber: Long,
    val supersedes: String,
    val sourceHash: String?,
    val locales: Map<String, LegalLocale>,
    val summaryDe: String,
    val summaryUk: String,
)

class LegalManagementStale : Exception("Legal document changed")
class LegalManagementInvalid : Exception("Invalid legal document")

/** The same legalDocuments pointer/version schema and hash algorithm as iOS 107. */
object LegalDraftContract {
    val types = listOf("terms", "privacy", "organizationRules")
    private val versionPattern = Regex("[0-9]{4}\\.[1-9][0-9]?")

    fun next(active: ManagedLegalVersion): Pair<String, Long> {
        val year = active.versionNumber / 100
        val minor = active.versionNumber % 100
        if (year < 1 || minor !in 1..98) throw LegalManagementInvalid()
        return "$year.${minor + 1}" to active.versionNumber + 1
    }

    fun requireSaveable(input: LegalDraftInput) {
        if (input.type !in types || !versionPattern.matches(input.version) ||
            input.versionNumber != input.version.substringBefore('.').toLong() * 100 +
                input.version.substringAfter('.').toLong() ||
            input.supersedes.isBlank() || input.locales.keys != setOf("de", "uk"))
            throw LegalManagementInvalid()
    }

    fun requireValid(input: LegalDraftInput) {
        requireSaveable(input)
        if (
            input.locales.values.any { it.title.trim().isBlank() || it.markdown.trim().isBlank() } ||
            input.summaryDe.trim().isBlank() || input.summaryUk.trim().isBlank())
            throw LegalManagementInvalid()
    }

    fun summary(input: LegalDraftInput): String? {
        val de = input.summaryDe.trim().replace("\n", " ")
        val uk = input.summaryUk.trim().replace("\n", " ")
        return if (de.isEmpty() && uk.isEmpty()) null else "DE:$de\nUK:$uk"
    }

    fun payload(input: LegalDraftInput, status: String): Map<String, Any?> {
        requireSaveable(input)
        val locales = input.locales.mapValues { (_, value) ->
            val markdown = value.markdown.replace("\r\n", "\n").trim()
            mapOf(
                "title" to value.title.trim(), "contentMarkdown" to markdown,
                "contentText" to null, "contentHash" to LegalDocumentIntegrity.sha256(markdown),
            )
        }
        val canonical = locales.keys.sorted().joinToString("\n---\n") { locale ->
            val value = locales.getValue(locale)
            listOf(locale, value.getValue("title"), value.getValue("contentMarkdown"),
                value.getValue("contentHash")).joinToString("\n")
        }
        return mapOf(
            "documentType" to input.type, "version" to input.version,
            "versionNumber" to input.versionNumber, "status" to status,
            "requiresAcceptance" to true, "defaultLocale" to "de", "canonicalLocale" to "de",
            "locales" to locales, "contentHash" to LegalDocumentIntegrity.sha256(canonical),
            "baseContentHash" to input.sourceHash, "changeSummary" to summary(input),
            "supersedesVersion" to input.supersedes,
            "publishedAt" to null, "publishedBy" to null,
        )
    }
}

interface LegalManagementSource {
    suspend fun load(session: ModerationSession): List<ManagedLegalDocument>
    suspend fun save(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument
    suspend fun publish(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument
}

class FirebaseLegalManagementSource(context: Context, private val store: AuthStore) : LegalManagementSource {
    private val db: FirebaseFirestore = AppBackend.firestore(context)
    private val auth: FirebaseAuth = AppBackend.auth(context)
    private val access = ModerationAccess(db, auth)

    init { FirebaseBackendGuard.requireSameApp(auth, db) }

    private suspend fun <T> owner(session: ModerationSession, block: suspend () -> T): T {
        if (!session.ready || session.role != "owner") throw IllegalAccessException("Owner required")
        return store.withReadySession(session.uid, session.revision) {
            access.privileged(session)
            if (store.state.value.moderationScope() != session) throw IllegalAccessException("Session changed")
            block().also {
                if (store.state.value.moderationScope() != session) throw IllegalAccessException("Session changed")
            }
        }
    }

    private fun pointer(type: String) = db.collection("legalDocuments").document(type)
    private fun version(reference: DocumentReference, id: String) = reference.collection("versions").document(id)

    private fun decode(type: String, id: String, data: Map<String, Any?>): ManagedLegalVersion {
        val locales = data["locales"] as? Map<*, *> ?: throw LegalManagementInvalid()
        val decoded = listOf("de", "uk").associateWith { key ->
            val item = locales[key] as? Map<*, *> ?: throw LegalManagementInvalid()
            LegalLocale(item["title"] as? String ?: throw LegalManagementInvalid(),
                item["contentMarkdown"] as? String ?: throw LegalManagementInvalid())
        }
        val hash = data["contentHash"] as? String ?: throw LegalManagementInvalid()
        val status = data["status"] as? String ?: throw LegalManagementInvalid()
        val number = (data["versionNumber"] as? Number)?.toLong() ?: throw LegalManagementInvalid()
        if (data["documentType"] != type || data["version"] != id ||
            data["requiresAcceptance"] != true || data["defaultLocale"] !in setOf("de", "uk") ||
            data["canonicalLocale"] !in setOf("de", "uk") || status !in setOf("draft", "published") ||
            !Regex("[0-9]{4}\\.[1-9][0-9]?").matches(id) ||
            number != id.substringBefore('.').toLong() * 100 + id.substringAfter('.').toLong())
            throw LegalManagementInvalid()
        val hashes = listOf("de", "uk").associateWith { locale ->
            LegalDocumentIntegrity.sha256(decoded.getValue(locale).markdown.replace("\r\n", "\n").trim())
        }
        if (listOf("de", "uk").any { locale ->
                (locales[locale] as? Map<*, *>)?.get("contentHash") != hashes[locale] ||
                    (status == "published" && (decoded.getValue(locale).title.trim().isBlank() ||
                        decoded.getValue(locale).markdown.trim().isBlank()))
            }) throw LegalManagementInvalid()
        val canonical = listOf("de", "uk").joinToString("\n---\n") { locale ->
            val item = decoded.getValue(locale)
            listOf(locale, item.title.trim(), item.markdown.replace("\r\n", "\n").trim(),
                hashes.getValue(locale)).joinToString("\n")
        }
        if (hash != LegalDocumentIntegrity.sha256(canonical)) throw LegalManagementInvalid()
        return ManagedLegalVersion(type, id, number, hash, decoded,
            data["changeSummary"] as? String, data["supersedesVersion"] as? String, status)
    }

    private suspend fun activeRead(type: String): ManagedLegalVersion {
        val reference = pointer(type)
        val head = reference.get(Source.SERVER).await()
        if (!head.exists() || head.metadata.isFromCache || head.metadata.hasPendingWrites())
            throw LegalManagementStale()
        val activeId = head.getString("activeVersion") ?: throw LegalManagementInvalid()
        val activeSnap = version(reference, activeId).get(Source.SERVER).await()
        val active = decode(type, activeId, activeSnap.data ?: throw LegalManagementInvalid())
        LegalDocumentIntegrity.validate(type, activeId, head.data.orEmpty(), activeSnap.data.orEmpty())
        return active
    }

    private suspend fun read(type: String): ManagedLegalDocument {
        val reference = pointer(type)
        val active = activeRead(type)
        val drafts = reference.collection("versions").whereEqualTo("status", "draft")
            .limit(2).get(Source.SERVER).await()
        if (drafts.metadata.isFromCache || drafts.metadata.hasPendingWrites() || drafts.size() > 1)
            throw LegalManagementStale()
        val draft = drafts.documents.singleOrNull()?.let { decode(type, it.id, it.data ?: throw LegalManagementInvalid()) }
        if (draft != null && (draft.supersedes != active.version ||
            draft.versionNumber != active.versionNumber + 1 || draft.version != LegalDraftContract.next(active).first))
            throw LegalManagementStale()
        return ManagedLegalDocument(active, draft)
    }

    override suspend fun load(session: ModerationSession) = owner(session) {
        LegalDraftContract.types.map { read(it) }
    }

    override suspend fun save(session: ModerationSession, input: LegalDraftInput) = owner(session) {
        val payload = LegalDraftContract.payload(input, "draft")
        val reference = pointer(input.type)
        val draftRef = version(reference, input.version)
        db.runTransaction { tx ->
            val head = tx.get(reference)
            val existing = tx.get(draftRef)
            val activeId = head.getString("activeVersion")
            val activeNumber = head.getLong("versionNumber")
            if (activeId != input.supersedes || activeNumber != input.versionNumber - 1 ||
                LegalDraftContract.next(ManagedLegalVersion(input.type, activeId, activeNumber,
                    "", emptyMap(), null, null, "published")).first != input.version ||
                existing.exists() != (input.sourceHash != null) ||
                (existing.exists() && (existing.getString("status") != "draft" ||
                    existing.getString("contentHash") != input.sourceHash))) throw LegalManagementStale()
            val values = payload + mapOf("updatedAt" to FieldValue.serverTimestamp(), "updatedBy" to session.uid)
            if (existing.exists()) tx.update(draftRef, values)
            else tx.set(draftRef, values + mapOf("createdAt" to FieldValue.serverTimestamp(),
                "createdBy" to session.uid))
        }.await()
        read(input.type).also {
            if (it.draft?.contentHash != payload["contentHash"]) throw LegalManagementStale()
        }
    }

    override suspend fun publish(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument {
        LegalDraftContract.requireValid(input)
        val payload = LegalDraftContract.payload(input, "published")
        if (input.sourceHash != payload["contentHash"]) throw LegalManagementStale()
        val reference = pointer(input.type)
        val draftRef = version(reference, input.version)
        val timestamp = FieldValue.serverTimestamp()
        try {
            owner(session) {
                db.runTransaction { tx ->
                    val head = tx.get(reference)
                    val existing = tx.get(draftRef)
                    if (head.getString("activeVersion") != input.supersedes ||
                        head.getLong("versionNumber") != input.versionNumber - 1 ||
                        existing.getString("status") != "draft" ||
                        existing.getString("contentHash") != input.sourceHash ||
                        existing.getString("supersedesVersion") != input.supersedes)
                        throw LegalManagementStale()
                    tx.update(draftRef, payload + mapOf("updatedAt" to timestamp, "updatedBy" to session.uid,
                        "publishedAt" to timestamp, "publishedBy" to session.uid))
                    tx.set(reference, mapOf("documentType" to input.type, "activeVersion" to input.version,
                        "versionNumber" to input.versionNumber, "status" to "published",
                        "requiresAcceptance" to true, "defaultLocale" to "de", "updatedAt" to timestamp,
                        "updatedBy" to session.uid, "publishedAt" to timestamp, "publishedBy" to session.uid,
                        "changeSummary" to LegalDraftContract.summary(input)))
                }.await()
            }
        } catch (error: Exception) {
            // A lost response may follow a committed write. Never issue a second publish.
            val observed = runCatching { activeRead(input.type) }.getOrNull()
            if (observed?.version != input.version ||
                observed.contentHash != payload["contentHash"]) throw error
        }
        return ManagedLegalDocument(activeRead(input.type).also {
            if (it.version != input.version || it.contentHash != payload["contentHash"])
                throw LegalManagementStale()
        }, null)
    }
}
