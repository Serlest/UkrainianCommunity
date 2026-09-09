package at.uac.android.feature.legalevidence

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await

fun legalEvidencePageSource(context: Context): LegalEvidencePageSource =
    LegalEvidencePageSource(AppBackend.callables(context))

data class LegalEvidenceAccount(
    val userId: String,
    val displayName: String?,
    val email: String?,
    val createdAt: Instant?,
)

data class LegalEvidenceEvent(
    val id: String,
    val userId: String,
    val eventType: String,
    val occurredAt: Instant,
    val source: String,
    val values: Map<String, Any?>,
)

data class LegalEvidencePage(
    val account: LegalEvidenceAccount,
    val events: List<LegalEvidenceEvent>,
    val nextCursor: String?,
    val generatedAt: Instant,
)

object LegalEvidencePageContract {
  private val id = Regex("[^/]{1,200}")
  private val types =
      setOf(
          "termsAccepted",
          "privacyAcknowledged",
          "minimumAgeConfirmed",
          "organizationRulesAccepted",
          "analyticsGranted",
          "analyticsWithdrawn",
      )
  private val sources = setOf("registration", "legalDocument", "analyticsConsent")

  fun request(userId: String, cursor: String?, limit: Int = 200): Map<String, Any?> {
    require(id.matches(userId) && limit in 1..200 && (cursor == null || cursor.length in 1..2048))
    return mapOf("userId" to userId, "cursor" to cursor, "limit" to limit)
  }

  fun page(raw: Any?, expectedUser: String): LegalEvidencePage {
    val map = raw.record()
    val accountMap = map.record("account")
    val account =
        LegalEvidenceAccount(
            accountMap.string("userId").also { require(it == expectedUser) },
            accountMap.optionalString("displayName"),
            accountMap.optionalString("email"),
            accountMap.optionalInstant("createdAt"),
        )
    val events =
        map.list("events").map { item ->
          val value = item.record()
          val type = value.string("eventType").also { require(it in types) }
          val source = value.string("source").also { require(it in sources) }
          LegalEvidenceEvent(
              value.string("id"),
              value.string("userId").also { require(it == expectedUser) },
              type,
              value.instant("occurredAt"),
              source,
              value,
          )
        }
    require(events.map { it.id }.distinct().size == events.size)
    val cursor =
        map.optionalString("nextCursor").also { require(it == null || it.length in 1..2048) }
    return LegalEvidencePage(account, events, cursor, map.instant("generatedAt"))
  }

  private fun Any?.record(): Map<String, Any?> =
      (this as? Map<*, *>)?.entries?.associate { (k, v) -> (k as? String ?: invalid()) to v }
          ?: invalid()

  private fun Map<String, Any?>.record(key: String) = this[key].record()

  private fun Map<String, Any?>.string(key: String) = this[key] as? String ?: invalid()

  private fun Map<String, Any?>.optionalString(key: String) =
      this[key]?.let { it as? String ?: invalid() }

  private fun Map<String, Any?>.instant(key: String) = runCatching {
    Instant.parse(string(key))
  }.getOrElse { invalid() }

  private fun Map<String, Any?>.optionalInstant(key: String) =
      optionalString(key)?.let { runCatching { Instant.parse(it) }.getOrElse { invalid() } }

  private fun Map<String, Any?>.list(key: String) = this[key] as? List<Any?> ?: invalid()

  private fun invalid(): Nothing = throw IllegalArgumentException("Invalid legal evidence page")
}

fun interface LegalEvidenceLoader {
  suspend fun all(userId: String): List<LegalEvidenceEvent>
}

class LegalEvidencePageSource(private val callables: CallableGateway) : LegalEvidenceLoader {
  override suspend fun all(userId: String): List<LegalEvidenceEvent> = all(userId, 200)

  suspend fun all(userId: String, limit: Int): List<LegalEvidenceEvent> {
    var cursor: String? = null
    val seenCursors = mutableSetOf<String>()
    val events = linkedMapOf<String, LegalEvidenceEvent>()
    do {
      val payload = LegalEvidencePageContract.request(userId, cursor, limit)
      val page =
          LegalEvidencePageContract.page(
              callables
                  .getHttpsCallable("getLegalEvidencePage")
                  .withTimeout(20, TimeUnit.SECONDS)
                  .call(payload)
                  .await()
                  .data,
              userId,
          )
      page.events.forEach { event -> require(events.putIfAbsent(event.id, event) == null) }
      cursor = page.nextCursor
      require(cursor == null || seenCursors.add(cursor))
    } while (cursor != null)
    return events.values.sortedWith(
        compareByDescending<LegalEvidenceEvent> { it.occurredAt }.thenBy { it.id }
    )
  }
}
