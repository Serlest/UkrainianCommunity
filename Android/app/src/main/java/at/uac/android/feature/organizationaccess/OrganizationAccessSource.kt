package at.uac.android.feature.organizationaccess

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

fun organizationAccessSource(
    context: Context,
    reader: OrganizationAccessReader,
): OrganizationAccessSource = OrganizationAccessSource(AppBackend.callables(context), reader)

interface OrganizationAccessReader {
  suspend fun read(organizationId: String): OrganizationVersion?

  suspend fun readPhoto(organizationId: String, photoId: String): OrganizationPhotoVersion?
}

class OrganizationAccessSource(
    private val callables: CallableGateway,
    private val reader: OrganizationAccessReader,
) {
  suspend fun access(
      principalId: String,
      ids: List<String>,
      legacy: Map<String, Map<String, Boolean>>,
      clientVersion: String,
      now: Instant = Instant.now(),
  ): OrganizationAccessSnapshot =
      OrganizationAccessContract.accessResponse(
          call(
              "getOrganizationAccess",
              OrganizationAccessContract.accessRequest(ids, legacy, clientVersion),
              20,
          ),
          principalId,
          ids.toSet(),
          now,
      )

  suspend fun update(
      attempt: OrganizationUpdateAttempt,
      clientVersion: String,
  ): OrganizationUpdateReceipt {
    val payload = OrganizationAccessContract.updateRequest(attempt, clientVersion)
    return recoverUnknownMutation(
        dispatch = {
          OrganizationAccessContract.updateReceipt(
              call("updateOrganizationInfo", payload, 20),
              attempt.organizationId,
          )
        },
        read = { reader.read(attempt.organizationId) },
        confirms = { actual ->
          if (actual.revision != null && OrganizationAccessContract.confirms(attempt, actual))
              OrganizationUpdateReceipt(attempt.organizationId, actual.revision, false)
          else null
        },
    )
  }

  suspend fun savePhoto(
      attempt: OrganizationPhotoAttempt,
      clientVersion: String,
  ): OrganizationPhotoReceipt {
    val payload = OrganizationPhotoContract.request(attempt, clientVersion)
    reader
        .readPhoto(attempt.organizationId, attempt.photoId)
        ?.takeIf { OrganizationPhotoContract.confirms(attempt, it) }
        ?.let {
          return OrganizationPhotoReceipt(attempt.organizationId, attempt.photoId, false)
        }
    try {
      return OrganizationPhotoContract.receipt(
          call("saveOrganizationPhoto", payload, 120),
          attempt,
      )
    } catch (error: at.uac.android.core.LocalCallableException) {
      if (error.code != at.uac.android.core.LocalCallableFailure.UNCONFIRMED) throw error
      val actual = reader.readPhoto(attempt.organizationId, attempt.photoId)
      if (actual != null && OrganizationPhotoContract.confirms(attempt, actual))
          return OrganizationPhotoReceipt(attempt.organizationId, attempt.photoId, false)
      // The UI/journal owns any later read-back. A photo command is never replayed here.
      throw error
    }
  }

  private suspend fun call(name: String, payload: Map<String, Any?>, seconds: Long): Any? =
      try {
        callables
            .getHttpsCallable(name)
            .withTimeout(seconds, TimeUnit.SECONDS)
            .call(payload)
            .await()
            .data
      } catch (error: CancellationException) {
        throw error
      }
}
