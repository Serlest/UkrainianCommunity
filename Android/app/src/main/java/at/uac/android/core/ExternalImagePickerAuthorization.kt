package at.uac.android.core

interface ExternalImagePickerLease {
    fun finish()

    fun cancel()
}

fun interface ExternalImagePickerAuthorization {
    fun begin(uid: String, revision: Long): ExternalImagePickerLease?
}

/** Each production-facing host must explicitly connect its authoritative foreground policy. */
object DeniedExternalImagePickerAuthorization : ExternalImagePickerAuthorization {
    override fun begin(uid: String, revision: Long): ExternalImagePickerLease? = null
}
