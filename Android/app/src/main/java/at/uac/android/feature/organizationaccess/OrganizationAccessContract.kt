package at.uac.android.feature.organizationaccess

import at.uac.android.feature.organization.OrganizationManagementContract
import java.time.Instant

enum class OrganizationCommand {
  UPDATE_INFO,
  SAVE_PHOTO,
}

data class OrganizationAccessRecord(val organizationId: String, val actions: Set<String>)

data class OrganizationAccessSnapshot(
    val principalId: String,
    val policyVersion: String,
    val enforced: Boolean,
    val actionModes: Map<String, String>,
    val commands: Map<OrganizationCommand, Boolean>,
    val records: Map<String, OrganizationAccessRecord>,
    val expiresAt: Instant,
) {
  fun isEnforced(action: String): Boolean = actionModes[action]?.let { it == "enforced" } ?: enforced

  fun allows(organizationId: String, action: String): Boolean =
      isEnforced(action) &&
          records[organizationId]?.actions?.contains(action) == true
}

data class OrganizationVersion(
    val organizationId: String,
    val revision: String?,
    val fields: Map<String, Any?>,
)

data class OrganizationUpdateAttempt(
    val principalId: String,
    val organizationId: String,
    val operationId: String,
    val expectedRevision: String?,
    val targetStatus: String,
    val fields: Map<String, Any?>,
)

data class OrganizationUpdateReceipt(
    val organizationId: String,
    val revision: String,
    val didChange: Boolean,
)

object OrganizationAccessContract {
  private val id = Regex("[^/]{1,200}")
  private val action = Regex("[A-Za-z][A-Za-z0-9]{0,63}")
  private val revision = Regex("[0-9]+:[0-9]{1,9}")

  fun accessRequest(
      ids: List<String>,
      legacy: Map<String, Map<String, Boolean>>,
      version: String,
  ): Map<String, Any?> {
    require(ids.size <= 50 && ids.all { id.matches(it) } && ids.distinct().size == ids.size)
    require(legacy.keys.all(ids::contains) && version.length in 1..64)
    return mapOf("organizationIds" to ids, "legacyDecisions" to legacy, "clientVersion" to version)
  }

  fun accessResponse(
      value: Any?,
      expectedPrincipal: String,
      requested: Set<String>,
      now: Instant,
  ): OrganizationAccessSnapshot {
    val map = value.record()
    require(map.string("principalId") == expectedPrincipal && map.integer("schemaVersion") == 1)
    require(map.string("policyVersion") == "organization-actions-v1")
    val records =
        map.list("records").map { raw ->
          val row = raw.record()
          val organizationId = row.string("organizationId").also { require(it in requested) }
          val actionList =
              row.list("actions")
                  .map { it as? String ?: invalid() }
                  .onEach { require(action.matches(it)) }
          require(actionList.distinct().size == actionList.size)
          val actions = actionList.toSet()
          OrganizationAccessRecord(organizationId, actions)
        }
    require(records.map { it.organizationId }.toSet() == requested)
    val modes =
        map.optionalRecord("actionModes").orEmpty().mapValues { it.value as? String ?: invalid() }
    require(modes.values.all { it == "shadow" || it == "enforced" })
    val rawCommands = map.optionalRecord("commands").orEmpty()
    val commands =
        mapOf(
            OrganizationCommand.UPDATE_INFO to
                (rawCommands["updateOrganizationInfo"] as? Boolean ?: false),
            OrganizationCommand.SAVE_PHOTO to
                (rawCommands["saveOrganizationPhoto"] as? Boolean ?: false),
        )
    return OrganizationAccessSnapshot(
        expectedPrincipal,
        "organization-actions-v1",
        map["mode"] == "enforced",
        modes,
        commands,
        records.associateBy { it.organizationId },
        now.plusSeconds(30),
    )
  }

  fun updateRequest(value: OrganizationUpdateAttempt, clientVersion: String): Map<String, Any?> {
    require(value.principalId.length in 1..128 && '/' !in value.principalId)
    require(id.matches(value.organizationId) && id.matches(value.operationId))
    require(value.expectedRevision == null || validRevision(value.expectedRevision))
    require(value.targetStatus in setOf("approved", "pendingReview", "needsRevision", "rejected"))
    require(
        value.fields.isNotEmpty() &&
            value.fields.keys.all {
              it in OrganizationManagementContract.safeFields && it != "updatedAt"
            } &&
            clientVersion.length in 1..64
    )
    return mapOf(
        "principalId" to value.principalId,
        "organizationId" to value.organizationId,
        "operationId" to value.operationId,
        "expectedRevision" to value.expectedRevision,
        "targetStatus" to value.targetStatus,
        "fields" to value.fields,
        "clientVersion" to clientVersion,
    )
  }

  fun updateReceipt(value: Any?, expectedOrganization: String): OrganizationUpdateReceipt {
    val map = value.record()
    require(map.keys == setOf("organizationId", "revision", "didChange"))
    val organizationId = map.string("organizationId").also { require(it == expectedOrganization) }
    val revision = map.string("revision").also { require(validRevision(it)) }
    return OrganizationUpdateReceipt(
        organizationId,
        revision,
        map["didChange"] as? Boolean ?: invalid(),
    )
  }

  fun confirms(attempt: OrganizationUpdateAttempt, actual: OrganizationVersion): Boolean =
      actual.organizationId == attempt.organizationId &&
          attempt.fields.all { actual.fields[it.key] == it.value }

  private fun validRevision(value: String): Boolean {
    if (!revision.matches(value)) return false
    val parts = value.split(':')
    val nanos = parts[1].toIntOrNull() ?: return false
    return parts[0].toLongOrNull() != null && nanos in 0..999_999_999
  }
}

internal fun Any?.record(): Map<String, Any?> =
    (this as? Map<*, *>)?.entries?.associate { (key, value) ->
      (key as? String ?: invalid()) to value
    } ?: invalid()

internal fun Map<String, Any?>.string(key: String): String = this[key] as? String ?: invalid()

internal fun Map<String, Any?>.integer(key: String): Int =
    (this[key] as? Number)?.toInt()?.also {
      require((this[key] as Number).toDouble() == it.toDouble())
    } ?: invalid()

internal fun Map<String, Any?>.list(key: String): List<Any?> = this[key] as? List<Any?> ?: invalid()

internal fun Map<String, Any?>.optionalRecord(key: String): Map<String, Any?>? = this[key]?.record()

internal fun invalid(): Nothing = throw IllegalArgumentException("Invalid build 68 contract")
