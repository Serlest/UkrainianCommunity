package at.uac.android.feature.auth

import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease

class AuthImagePickerAuthorization(private val auth: AuthStore) : ExternalImagePickerAuthorization {
    override fun begin(uid: String, revision: Long): ExternalImagePickerLease? {
        val token = auth.beginExternalPicker(uid, revision) ?: return null
        return object : ExternalImagePickerLease {
            override fun finish() {
                auth.finishExternalPicker(token)
            }

            override fun cancel() {
                auth.cancelExternalPicker(token)
            }
        }
    }
}
