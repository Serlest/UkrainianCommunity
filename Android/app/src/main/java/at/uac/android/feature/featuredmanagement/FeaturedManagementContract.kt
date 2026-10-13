package at.uac.android.feature.featuredmanagement

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationSession
import java.net.URI
import java.security.MessageDigest
import java.time.Instant

object FeaturedManagementContract {
    val states = setOf("burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien")

    fun requireOwner(session: ModerationSession?) {
        if (session == null || !session.ready || session.role != "owner" || !id(session.uid)) fail(FeaturedFailure.ACCESS)
    }

    fun id(value: String): Boolean =
        value.length in 1..128 && !value.contains('/') && value.trim() == value && value.none(Char::isISOControl)

    fun validate(draft: FeaturedDraft) {
        if (!id(draft.id) || draft.internalName.trim().length > 120 || draft.title.trim().length > 120 || draft.subtitle.trim().length > 240) fail(FeaturedFailure.INVALID)
        if (draft.localizations.keys.any { it !in setOf("uk", "de") } || draft.localizations.values.any { it.title.trim().length > 120 || it.subtitle.trim().length > 240 }) fail(FeaturedFailure.INVALID)
        if (!http(draft.imageUrl) || draft.sections.isEmpty() || draft.displayDurationSeconds !in 3..12 || draft.priority !in 0..1000) fail(FeaturedFailure.INVALID)
        if (draft.action.needsTarget && draft.actionTargetId.trim().isEmpty()) fail(FeaturedFailure.INVALID)
        if (draft.action == FeaturedAction.EXTERNAL_URL && !http(draft.externalUrl)) fail(FeaturedFailure.INVALID)
        if (draft.region == FeaturedRegion.FEDERAL_STATE && draft.federalState !in states) fail(FeaturedFailure.INVALID)
        if (draft.startsAt != null && draft.endsAt != null && draft.startsAt >= draft.endsAt) fail(FeaturedFailure.INVALID)
    }

    fun payload(draft: FeaturedDraft): Map<String, Any> {
        validate(draft)
        val result = linkedMapOf<String, Any>(
            "id" to draft.id,
            "localizations" to draft.localizations.mapValues { mapOf("title" to it.value.title.trim(), "subtitle" to it.value.subtitle.trim()) },
            "imageURL" to draft.imageUrl.trim(), "actionType" to draft.action.wire,
            "regionScope" to draft.region.wire, "visibleSections" to draft.sections.map { it.wire }.sorted(),
            "displayDurationSeconds" to draft.displayDurationSeconds, "priority" to draft.priority, "isActive" to draft.active,
        )
        draft.internalName.trim().takeIf(String::isNotEmpty)?.let { result["internalName"] = it }
        draft.title.trim().takeIf(String::isNotEmpty)?.let { result["title"] = it }
        draft.subtitle.trim().takeIf(String::isNotEmpty)?.let { result["subtitle"] = it }
        if (draft.action.needsTarget) result["actionTargetID"] = draft.actionTargetId.trim()
        if (draft.action == FeaturedAction.EXTERNAL_URL) result["externalURL"] = URI(draft.externalUrl.trim()).normalize().toString()
        if (draft.region == FeaturedRegion.FEDERAL_STATE) result["federalState"] = draft.federalState
        draft.startsAt?.let { result["startsAt"] = it.toString() }
        draft.endsAt?.let { result["endsAt"] = it.toString() }
        LocalCallableProtocol.request(result)
        return result
    }

    fun saveRequest(draft: FeaturedDraft, create: Boolean): Map<String, Any> =
        mapOf("mode" to if (create) "create" else "update", "banner" to payload(draft)).also(LocalCallableProtocol::request)

    fun receipt(expectedId: String, data: Any?): FeaturedReceipt {
        val map = data as? Map<*, *> ?: fail(FeaturedFailure.UNCONFIRMED)
        if (map.keys != setOf("id", "updatedAt") || map["id"] != expectedId) fail(FeaturedFailure.UNCONFIRMED)
        val time = (map["updatedAt"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: fail(FeaturedFailure.UNCONFIRMED)
        return FeaturedReceipt(expectedId, time)
    }

    fun fingerprint(draft: FeaturedDraft): String =
        MessageDigest.getInstance("SHA-256").digest(canonical(payload(draft)).toByteArray()).joinToString("") { "%02x".format(it) }

    private fun canonical(value: Any?): String = when (value) {
        is Map<*, *> -> value.entries.sortedBy { it.key.toString() }.joinToString(prefix = "{", postfix = "}") { canonical(it.key.toString()) + ":" + canonical(it.value) }
        is Iterable<*> -> value.joinToString(prefix = "[", postfix = "]") { canonical(it) }
        is String -> "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
        else -> value.toString()
    }

    private fun http(value: String): Boolean = runCatching {
        val uri = URI(value.trim())
        uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrBlank() && value.length <= 2048
    }.getOrDefault(false)

    fun fail(failure: FeaturedFailure): Nothing = throw FeaturedException(failure)
}
