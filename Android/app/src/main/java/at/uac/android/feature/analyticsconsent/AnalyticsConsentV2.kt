package at.uac.android.feature.analyticsconsent

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await

fun analyticsConsentV2Source(context: Context): AnalyticsConsentV2Source =
    AnalyticsConsentV2Source(AppBackend.callables(context))

data class AnalyticsConsentV2(
    val principalId: String,
    val enabled: Boolean,
    val consentId: String,
    val locale: String,
    val appVersion: String,
    val privacyVersion: String? = null,
    val disclosureVersion: String? = null,
    val existingReceiptOnly: Boolean = false,
)

object AnalyticsConsentV2Contract {
  const val PRIVACY_VERSION = "2026.22"
  const val DISCLOSURE_VERSION = "2026-08-25.1"

  fun request(value: AnalyticsConsentV2): Map<String, Any?> {
    require(value.principalId.length in 1..128 && '/' !in value.principalId)
    require(
        runCatching { UUID.fromString(value.consentId).toString() }.getOrNull() ==
            value.consentId.lowercase()
    )
    require(
        value.locale in setOf("de", "uk") &&
            Regex("[0-9A-Za-z][0-9A-Za-z._+-]{0,63}").matches(value.appVersion)
    )
    require((value.privacyVersion == null) == (value.disclosureVersion == null))
    if (value.privacyVersion != null)
        require(
            value.privacyVersion == PRIVACY_VERSION && value.disclosureVersion == DISCLOSURE_VERSION
        )
    require(!value.enabled || !value.existingReceiptOnly || value.privacyVersion == null)
    return buildMap {
      put("principalId", value.principalId)
      put("enabled", value.enabled)
      put("consentID", value.consentId)
      put("locale", value.locale)
      put("appVersion", value.appVersion)
      value.privacyVersion?.let {
        put("privacyVersion", it)
        put("disclosureVersion", value.disclosureVersion)
      }
      if (value.existingReceiptOnly) put("existingReceiptOnly", true)
    }
  }

  fun receipt(raw: Any?, expected: AnalyticsConsentV2): Boolean {
    val value =
        raw as? Map<*, *> ?: throw IllegalArgumentException("Invalid analytics consent receipt")
    require(
        value.keys == setOf("enabled", "consentID") &&
            value["enabled"] == expected.enabled &&
            value["consentID"] == expected.consentId
    )
    return expected.enabled
  }
}

fun interface AnalyticsConsentSynchronizer {
  suspend fun synchronize(value: AnalyticsConsentV2): Boolean
}

class AnalyticsConsentV2Source(private val callables: CallableGateway) :
    AnalyticsConsentSynchronizer {
  override suspend fun synchronize(value: AnalyticsConsentV2): Boolean {
    val payload = AnalyticsConsentV2Contract.request(value)
    val raw =
        try {
          callables
              .getHttpsCallable("updateAnalyticsConsentV2")
              .withTimeout(20, TimeUnit.SECONDS)
              .call(payload)
              .await()
              .data
        } catch (error: LocalCallableException) {
          if (!analyticsConsentV2MayUseLegacy(error)) throw error
          val legacy = payload.filterKeys {
            it in setOf("enabled", "consentID", "locale", "appVersion")
          }
          callables
              .getHttpsCallable("updateAnalyticsConsent")
              .withTimeout(20, TimeUnit.SECONDS)
              .call(legacy)
              .await()
              .data
        }
    return AnalyticsConsentV2Contract.receipt(raw, value)
  }
}

internal fun analyticsConsentV2MayUseLegacy(error: Throwable): Boolean =
    error is LocalCallableException && error.code == LocalCallableFailure.NOT_FOUND
