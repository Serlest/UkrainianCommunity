package at.uac.android.feature.push

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** App-private, non-backed-up storage (the application disables Android backup). */
@SuppressLint("UseKtx") // Synchronous commit outcome is part of the fail-closed contract.
class PrivatePushOwnershipStore(context: Context) : PushOwnershipStore {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    override suspend fun load(): OwnedPushRegistration? = withContext(Dispatchers.IO) { decode() }

    override suspend fun save(value: OwnedPushRegistration) =
        withContext(Dispatchers.IO) {
            val registration = value.registration
            val saved =
                preferences
                    .edit()
                    .clear()
                    .putInt(VERSION, 1)
                    .putString(UID, value.uid)
                    .putString(DOCUMENT, registration.documentId)
                    .putString(INSTALLATION, registration.installationId)
                    .putString(TOKEN, registration.token.value())
                    .putString(DEVICE, registration.deviceName)
                    .putString(APP_VERSION, registration.appVersion)
                    .putString(REGISTRATION_TYPE, registration.registrationType)
                    .commit()
            if (!saved) throw PushException(PushFailure.NOT_READY)
        }

    override suspend fun clear(expected: OwnedPushRegistration) =
        withContext(Dispatchers.IO) {
            val stored = decode()
            if (stored != expected) throw PushException(PushFailure.CROSS_ACCOUNT)
            if (!preferences.edit().clear().commit()) throw PushException(PushFailure.NOT_READY)
        }

    private fun decode(): OwnedPushRegistration? {
        if (!preferences.contains(VERSION)) return null
        if (preferences.getInt(VERSION, -1) != 1) throw PushException(PushFailure.NOT_READY)
        val uid =
            preferences.getString(UID, null)?.takeIf(::validUid)
                ?: throw PushException(PushFailure.NOT_READY)
        val registration =
            PushRegistrationContract.create(
                preferences.getString(INSTALLATION, null).orEmpty(),
                preferences.getString(TOKEN, null).orEmpty(),
                preferences.getString(DEVICE, null).orEmpty(),
                preferences.getString(APP_VERSION, null).orEmpty(),
                preferences.getString(REGISTRATION_TYPE, null).orEmpty(),
            )
        if (preferences.getString(DOCUMENT, null) != registration.documentId)
            throw PushException(PushFailure.NOT_READY)
        return OwnedPushRegistration(uid, registration)
    }

    private fun validUid(value: String): Boolean =
        value.isNotBlank() && value.length <= 256 && '/' !in value && !value.any(Char::isISOControl)

    private companion object {
        const val FILE = "uac-push-ownership-v1"
        const val VERSION = "version"
        const val UID = "uid"
        const val DOCUMENT = "document"
        const val INSTALLATION = "installation"
        const val TOKEN = "token"
        const val DEVICE = "device"
        const val APP_VERSION = "app-version"
        const val REGISTRATION_TYPE = "registration-type"
    }
}
