package at.uac.android.feature.organizationaccess

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure

/** Replays only the same server-idempotent operation after an exact authoritative read-back. */
internal suspend fun <Receipt, Actual> recoverUnknownMutation(
    dispatch: suspend () -> Receipt,
    read: suspend () -> Actual?,
    confirms: (Actual) -> Receipt?,
): Receipt {
  try {
    return dispatch()
  } catch (first: LocalCallableException) {
    if (first.code != LocalCallableFailure.UNCONFIRMED) throw first
    read()?.let(confirms)?.let {
      return it
    }
    try {
      return dispatch()
    } catch (second: LocalCallableException) {
      if (
          second.code != LocalCallableFailure.UNCONFIRMED &&
              second.code != LocalCallableFailure.ABORTED
      )
          throw second
      read()?.let(confirms)?.let {
        return it
      }
      throw first
    }
  }
}
