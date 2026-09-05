package at.uac.android.core.backend

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage

/**
 * Build-owned SDK factory. It neither restores an account nor selects a backend from user input.
 * Accessors must configure the exact named instances before returning them.
 */
internal interface FirebaseBackendProvider {
    val configuration: BackendConfiguration

    fun app(context: Context): FirebaseApp

    fun auth(context: Context): FirebaseAuth

    fun firestore(context: Context): FirebaseFirestore

    fun storage(context: Context): FirebaseStorage

    fun callables(context: Context): CallableGateway
}
