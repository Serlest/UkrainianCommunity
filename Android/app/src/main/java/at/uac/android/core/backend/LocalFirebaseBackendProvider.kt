package at.uac.android.core.backend

import android.content.Context
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.core.LocalStorage
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage

/** Keeps the existing configure-once bindings and Auth-before-Firestore order unchanged. */
internal object LocalFirebaseBackendProvider : FirebaseBackendProvider {
    override val configuration = CompiledBackend.configuration

    override fun app(context: Context): FirebaseApp = LocalFirebase.app(context)

    override fun auth(context: Context): FirebaseAuth = LocalFirebase.auth(context)

    override fun firestore(context: Context): FirebaseFirestore = LocalFirebase.firestore(context)

    override fun storage(context: Context): FirebaseStorage = LocalStorage.instance(context)

    override fun callables(context: Context): CallableGateway = LocalFunctions.instance(context)
}
