package at.uac.android.feature.authoring.recovery

import at.uac.android.feature.authoring.AuthoringDraft
import at.uac.android.feature.authoring.AuthoringEventDraft
import at.uac.android.feature.authoring.AuthoringOccurrence
import at.uac.android.feature.authoring.AuthoringPublicationMode
import at.uac.android.feature.authoring.AuthoringSubmission
import at.uac.android.feature.browse.ContentKind
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant

/** Bounded typed wire format, not JSONObject's lossy Instant/Long/Double conversion. */
internal object AuthoringRecoveryCodec {
    const val MAX_BYTES = 1_048_576
    private const val MAGIC = 0x55414352
    private const val LEGACY_VERSION = 1
    private const val DRAFT_VERSION = 2
    private const val MAX_STRING_BYTES = 262_144
    private const val MAX_NODES = 4_096

    fun draft(scope: AuthoringRecoveryScope, value: RecoveryDraft): ByteArray {
        RecoveryValidation.draft(scope, value.draft, value.zoneId)
        return encode(
            mapOf(
                "scope" to scopeFields(scope),
                "purpose" to "draft",
                "zone" to value.zoneId,
                "draft" to draftFields(value.draft),
            ),
            DRAFT_VERSION,
        )
    }

    fun readDraft(scope: AuthoringRecoveryScope, bytes: ByteArray): RecoveryDraft {
        val (version, decoded) = decodeRecord(bytes)
        val root = fields(decoded)
        exact(root, setOf("scope", "purpose", "zone", "draft"))
        requireScope(scope, root, "draft")
        return RecoveryDraft(readDraft(fields(root["draft"]), version), string(root, "zone")).also {
            RecoveryValidation.draft(scope, it.draft, it.zoneId)
        }
    }

    fun pending(scope: AuthoringRecoveryScope, value: AuthoringSubmission): ByteArray {
        RecoveryValidation.intent(scope, value)
        return encode(
            mapOf(
                "scope" to scopeFields(scope),
                "purpose" to "pending",
                "id" to value.id,
                "fields" to value.fields,
            )
        )
    }

    fun readPending(scope: AuthoringRecoveryScope, bytes: ByteArray): AuthoringSubmission {
        val (version, decoded) = decodeRecord(bytes)
        if (version != LEGACY_VERSION) RecoveryValidation.invalid()
        val root = fields(decoded)
        exact(root, setOf("scope", "purpose", "id", "fields"))
        requireScope(scope, root, "pending")
        return AuthoringSubmission(
                scope.kind,
                string(root, "id"),
                scope.organizationId,
                fields(root["fields"]),
                null,
            )
            .also { RecoveryValidation.intent(scope, it) }
    }

    private fun scopeFields(scope: AuthoringRecoveryScope) =
        mapOf("uid" to scope.uid, "org" to scope.organizationId, "kind" to scope.kind.collection)

    private fun requireScope(
        scope: AuthoringRecoveryScope,
        value: Map<String, Any?>,
        purpose: String,
    ) {
        if (value["scope"] != scopeFields(scope) || value["purpose"] != purpose)
            RecoveryValidation.invalid()
    }

    private fun draftFields(value: AuthoringDraft): Map<String, Any?> =
        mapOf(
            "id" to value.id,
            "kind" to value.kind.collection,
            "title" to value.title,
            "summary" to value.summary,
            "body" to value.body,
            "germanTitle" to value.germanTitle,
            "germanSummary" to value.germanSummary,
            "germanBody" to value.germanBody,
            "category" to value.category,
            "additionalCategories" to value.additionalCategories.sorted(),
            "tags" to value.tags,
            "regionScope" to value.regionScope,
            "source" to value.source,
            "actionTitle" to value.actionTitle,
            "actionUrl" to value.actionUrl,
            "event" to eventFields(value.event),
            "publicationMode" to value.publicationMode.name,
            "scheduledAt" to value.scheduledAt,
        )

    private val draftKeys =
        setOf(
            "id",
            "kind",
            "title",
            "summary",
            "body",
            "germanTitle",
            "germanSummary",
            "germanBody",
            "category",
            "additionalCategories",
            "tags",
            "regionScope",
            "source",
            "actionTitle",
            "actionUrl",
            "event",
        )

    private fun readDraft(value: Map<String, Any?>, version: Int): AuthoringDraft {
        exact(
            value,
            if (version == LEGACY_VERSION) draftKeys
            else draftKeys + setOf("publicationMode", "scheduledAt"),
        )
        val mode =
            if (version == LEGACY_VERSION) AuthoringPublicationMode.NOW
            else
                AuthoringPublicationMode.entries.firstOrNull {
                    it.name == string(value, "publicationMode")
                } ?: RecoveryValidation.invalid()
        val scheduled = value["scheduledAt"]
        if (scheduled != null && scheduled !is Instant) RecoveryValidation.invalid()
        val kind =
            ContentKind.entries.firstOrNull { it.collection == string(value, "kind") }
                ?: RecoveryValidation.invalid()
        val categories =
            list(value["additionalCategories"]).map {
                it as? String ?: RecoveryValidation.invalid()
            }
        if (categories.size > 2 || categories.distinct().size != categories.size)
            RecoveryValidation.invalid()
        return AuthoringDraft(
            string(value, "id"),
            kind,
            string(value, "title"),
            string(value, "summary"),
            string(value, "body"),
            string(value, "germanTitle"),
            string(value, "germanSummary"),
            string(value, "germanBody"),
            string(value, "category"),
            categories.toSet(),
            string(value, "tags"),
            string(value, "regionScope"),
            string(value, "source"),
            string(value, "actionTitle"),
            string(value, "actionUrl"),
            readEvent(fields(value["event"])),
            mode,
            scheduled,
        )
    }

    private fun eventFields(value: AuthoringEventDraft): Map<String, Any?> =
        mapOf(
            "city" to value.city,
            "venue" to value.venue,
            "address" to value.address,
            "locationNote" to value.locationNote,
            "organizer" to value.organizer,
            "organizerUrl" to value.organizerUrl,
            "contactPhone" to value.contactPhone,
            "contactEmail" to value.contactEmail,
            "contactUrl" to value.contactUrl,
            "participation" to value.participation,
            "capacity" to value.capacity,
            "priceKind" to value.priceKind,
            "amount" to value.amount,
            "maximumAmount" to value.maximumAmount,
            "priceNote" to value.priceNote,
            "currency" to value.currency,
            "audience" to value.audience,
            "minimumAge" to value.minimumAge,
            "maximumAge" to value.maximumAge,
            "occurrences" to
                value.occurrences.map {
                    mapOf(
                        "id" to it.id,
                        "start" to it.start,
                        "end" to it.end,
                        "allDay" to it.allDay,
                        "endKnown" to it.endKnown,
                        "status" to it.status,
                    )
                },
        )

    private val eventKeys =
        setOf(
            "city",
            "venue",
            "address",
            "locationNote",
            "organizer",
            "organizerUrl",
            "contactPhone",
            "contactEmail",
            "contactUrl",
            "participation",
            "capacity",
            "priceKind",
            "amount",
            "maximumAmount",
            "priceNote",
            "currency",
            "audience",
            "minimumAge",
            "maximumAge",
            "occurrences",
        )

    private fun readEvent(value: Map<String, Any?>): AuthoringEventDraft {
        exact(value, eventKeys)
        val occurrences =
            list(value["occurrences"]).map { raw ->
                val item = fields(raw)
                exact(item, setOf("id", "start", "end", "allDay", "endKnown", "status"))
                AuthoringOccurrence(
                    string(item, "id"),
                    item["start"] as? Instant ?: RecoveryValidation.invalid(),
                    item["end"] as? Instant ?: RecoveryValidation.invalid(),
                    item["allDay"] as? Boolean ?: RecoveryValidation.invalid(),
                    item["endKnown"] as? Boolean ?: RecoveryValidation.invalid(),
                    string(item, "status"),
                )
            }
        if (occurrences.size > 30 || occurrences.map { it.id }.distinct().size != occurrences.size)
            RecoveryValidation.invalid()
        return AuthoringEventDraft(
            string(value, "city"),
            string(value, "venue"),
            string(value, "address"),
            string(value, "locationNote"),
            string(value, "organizer"),
            string(value, "organizerUrl"),
            string(value, "contactPhone"),
            string(value, "contactEmail"),
            string(value, "contactUrl"),
            occurrences,
            string(value, "participation"),
            string(value, "capacity"),
            string(value, "priceKind"),
            string(value, "amount"),
            string(value, "maximumAmount"),
            string(value, "priceNote"),
            string(value, "currency"),
            string(value, "audience"),
            string(value, "minimumAge"),
            string(value, "maximumAge"),
        )
    }

    private fun fields(value: Any?): Map<String, Any?> {
        val map = value as? Map<*, *> ?: RecoveryValidation.invalid()
        return map.entries.associate {
            (it.key as? String ?: RecoveryValidation.invalid()) to it.value
        }
    }

    private fun string(value: Map<String, Any?>, key: String) =
        value[key] as? String ?: RecoveryValidation.invalid()

    private fun list(value: Any?) = value as? List<*> ?: RecoveryValidation.invalid()

    private fun exact(value: Map<String, Any?>, keys: Set<String>) {
        if (value.keys != keys) RecoveryValidation.invalid()
    }

    internal fun encode(value: Any?, version: Int = LEGACY_VERSION): ByteArray {
        if (version !in setOf(LEGACY_VERSION, DRAFT_VERSION)) RecoveryValidation.invalid()
        val bytes = ByteArrayOutputStream()
        val bounded =
            object : OutputStream() {
                override fun write(value: Int) {
                    if (bytes.size() >= MAX_BYTES) RecoveryValidation.invalid()
                    bytes.write(value)
                }

                override fun write(buffer: ByteArray, offset: Int, length: Int) {
                    if (length < 0 || bytes.size() > MAX_BYTES - length)
                        RecoveryValidation.invalid()
                    bytes.write(buffer, offset, length)
                }
            }
        val output = DataOutputStream(bounded)
        var nodes = 0
        fun text(value: String) {
            if (value.length > MAX_STRING_BYTES) RecoveryValidation.invalid()
            val encoded = value.toByteArray(Charsets.UTF_8)
            if (encoded.size > MAX_STRING_BYTES) RecoveryValidation.invalid()
            output.writeInt(encoded.size)
            output.write(encoded)
        }
        fun write(value: Any?, depth: Int) {
            if (++nodes > MAX_NODES || depth > 12) RecoveryValidation.invalid()
            when (value) {
                null -> output.writeByte(0)
                is String -> {
                    output.writeByte(1)
                    text(value)
                }
                is Boolean -> {
                    output.writeByte(2)
                    output.writeBoolean(value)
                }
                is Long -> {
                    output.writeByte(3)
                    output.writeLong(value)
                }
                is Double -> {
                    if (!value.isFinite()) RecoveryValidation.invalid()
                    output.writeByte(4)
                    output.writeDouble(value)
                }
                is Instant -> {
                    output.writeByte(5)
                    output.writeLong(value.epochSecond)
                    output.writeInt(value.nano)
                }
                is List<*> -> {
                    if (value.size > 128) RecoveryValidation.invalid()
                    output.writeByte(6)
                    output.writeInt(value.size)
                    value.forEach { write(it, depth + 1) }
                }
                is Map<*, *> -> {
                    if (
                        value.size > 128 ||
                            value.keys.any {
                                it !is String ||
                                    it.length > 128 ||
                                    it.toByteArray(Charsets.UTF_8).size > 128 ||
                                    it.any(Char::isISOControl)
                            }
                    )
                        RecoveryValidation.invalid()
                    output.writeByte(7)
                    output.writeInt(value.size)
                    value.entries
                        .sortedBy { it.key as String }
                        .forEach {
                            text(it.key as String)
                            write(it.value, depth + 1)
                        }
                }
                is Int -> {
                    output.writeByte(8)
                    output.writeInt(value)
                }
                else -> RecoveryValidation.invalid()
            }
        }
        output.writeInt(MAGIC)
        output.writeByte(version)
        write(value, 0)
        output.flush()
        return bytes.toByteArray()
    }

    internal fun decode(bytes: ByteArray): Any? = decodeRecord(bytes).second

    private fun decodeRecord(bytes: ByteArray): Pair<Int, Any?> {
        if (bytes.size !in 1..MAX_BYTES) RecoveryValidation.invalid()
        try {
            val input = DataInputStream(ByteArrayInputStream(bytes))
            var nodes = 0
            fun text(maximum: Int = MAX_STRING_BYTES): String {
                val size = input.readInt()
                if (size !in 0..maximum || size > input.available()) RecoveryValidation.invalid()
                val encoded = ByteArray(size)
                input.readFully(encoded)
                return Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(encoded))
                    .toString()
            }
            fun read(depth: Int): Any? {
                if (++nodes > MAX_NODES || depth > 12) RecoveryValidation.invalid()
                return when (input.readUnsignedByte()) {
                    0 -> null
                    1 -> text()
                    2 ->
                        when (input.readUnsignedByte()) {
                            0 -> false
                            1 -> true
                            else -> RecoveryValidation.invalid()
                        }
                    3 -> input.readLong()
                    4 ->
                        input.readDouble().also { if (!it.isFinite()) RecoveryValidation.invalid() }
                    5 ->
                        Instant.ofEpochSecond(
                            input.readLong(),
                            input
                                .readInt()
                                .also { if (it !in 0..999_999_999) RecoveryValidation.invalid() }
                                .toLong(),
                        )
                    6 ->
                        List(
                            input.readInt().also { if (it !in 0..128) RecoveryValidation.invalid() }
                        ) {
                            read(depth + 1)
                        }
                    7 -> {
                        val size = input.readInt()
                        if (size !in 0..128) RecoveryValidation.invalid()
                        linkedMapOf<String, Any?>().also { result ->
                            repeat(size) {
                                val key = text(128)
                                if (key.any(Char::isISOControl) || result.containsKey(key))
                                    RecoveryValidation.invalid()
                                result[key] = read(depth + 1)
                            }
                        }
                    }
                    8 -> input.readInt()
                    else -> RecoveryValidation.invalid()
                }
            }
            if (input.readInt() != MAGIC) RecoveryValidation.invalid()
            val version = input.readUnsignedByte()
            if (version !in setOf(LEGACY_VERSION, DRAFT_VERSION)) RecoveryValidation.invalid()
            return (version to read(0)).also {
                if (input.read() != -1) RecoveryValidation.invalid()
            }
        } catch (error: AuthoringRecoveryException) {
            throw error
        } catch (error: Exception) {
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.INVALID, error)
        }
    }
}
