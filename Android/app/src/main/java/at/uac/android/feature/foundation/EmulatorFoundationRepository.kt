package at.uac.android.feature.foundation

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import kotlinx.coroutines.tasks.await

/** Reads one synthetic document through unchanged repository Rules, never cloud. */
class EmulatorFoundationRepository(private val database: FirebaseFirestore) : FoundationRepository {
    override suspend fun load(): FoundationContent {
        val document =
            try {
                database
                    .collection("news")
                    .document("synthetic-android-welcome")
                    .get(Source.SERVER)
                    .await()
            } catch (error: FirebaseFirestoreException) {
                if (
                    error.code == FirebaseFirestoreException.Code.PERMISSION_DENIED ||
                        error.code == FirebaseFirestoreException.Code.UNAUTHENTICATED
                ) {
                    throw FixtureAccessDeniedException()
                }
                throw error
            }
        return decodeFoundationFixture(document.data ?: throw InvalidFixtureException())
    }
}
