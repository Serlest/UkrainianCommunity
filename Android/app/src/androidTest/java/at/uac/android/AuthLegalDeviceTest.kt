package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthLegalDeviceTest {
    @Test
    fun realCallableReceiptReadBackStaleAndRestrictedCasesOrExplicitDisabledRuntime() =
        runBlocking {
            val arguments = InstrumentationRegistry.getArguments()
            if (
                arguments.getString("expectFunctions") != "true" ||
                    arguments.getString("expectEmulator") != "true"
            ) {
                // Plain Auth/Firestore and offline suites deliberately do not claim
                // callable coverage. The positive run explicitly requires both flags.
                val document = AuthLegalDocument("terms", "synthetic", true, emptyMap(), emptyMap())
                assertEquals(
                    "android",
                    legalAcceptancePayload(document, "uk")["acceptedFromPlatform"],
                )
                return@runBlocking
            }
            AuthEmulatorFixtures.seedLegalReference()
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val auth = LocalFirebase.auth(context)
            val database = LocalFirebase.firestore(context)
            val backend = FirebaseAuthBackend(auth)
            val profiles = FirestoreAuthProfiles(database)
            val callables = LocalFunctions.instance(context)
            val acceptor = LocalAuthLegalAcceptor(auth, database, callables)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val email = "authlegal-${UUID.randomUUID()}@example.invalid"
            val password = "Synthetic-Legal-Only-Password1"
            var uid: String? = null
            val logIds = mutableListOf<String>()
            try {
                backend.signOut()
                val identity = backend.create(email, password, "Synthetic legal account")
                uid = identity.uid
                profiles.create(
                    identity.uid,
                    AuthRegistration(
                        email,
                        "Synthetic legal account",
                        "wien",
                        "",
                        true,
                        true,
                        true,
                        termsVersion = "synthetic-old-terms",
                        privacyVersion = "synthetic-old-privacy",
                    ),
                )
                val documents = profiles.legalDocuments()
                val terms = documents.first { it.type == "terms" }
                assertEquals(
                    AuthProblem.SESSION_CHANGED,
                    (runCatching {
                            acceptor.accept(identity.uid, terms, "uk")
                        }
                            .exceptionOrNull() as AuthException)
                        .problem,
                )
                val unverified =
                    runCatching {
                        callables
                            .getHttpsCallable("acceptLegalDocument")
                            .call(legalAcceptancePayload(terms, "uk"))
                            .await()
                    }
                        .exceptionOrNull()
                        ?: throw AssertionError("Unverified callable must be denied by the server")
                assertEquals(
                    LocalCallableFailure.PERMISSION_DENIED,
                    (unverified as LocalCallableException).code,
                )
                backend.sendVerification("uk")
                backend.verifyEmailCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
                backend.reload()
                backend.refreshToken()
                val store = AuthStore(backend, profiles, scope, acceptor)
                withContext(Dispatchers.Main) { store.restore() }.join()
                assertEquals(AuthGate.LEGAL_REQUIRED, store.state.value.gate)
                val required = store.state.value.requiredLegalDocuments()
                assertTrue(required.isNotEmpty())

                assertEquals(
                    AuthProblem.LEGAL_CHANGED,
                    (runCatching {
                            acceptor.accept(
                                identity.uid,
                                terms.copy(version = "synthetic-not-active"),
                                "uk",
                            )
                        }
                            .exceptionOrNull() as AuthException)
                        .problem,
                )
                assertEquals(
                    "synthetic-old-terms",
                    database
                        .collection("users")
                        .document(identity.uid)
                        .get(Source.SERVER)
                        .await()
                        .getString("acceptedTermsVersion"),
                )

                withContext(Dispatchers.IO) {
                    AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath("users/${identity.uid}") +
                            "?updateMask.fieldPaths=accountStatus",
                        "PATCH",
                        mapOf("accountStatus" to "bannedPermanent"),
                    )
                }
                assertEquals(
                    AuthProblem.PERMISSION_DENIED,
                    (runCatching {
                            acceptor.accept(identity.uid, terms, "uk")
                        }
                            .exceptionOrNull() as AuthException)
                        .problem,
                )
                withContext(Dispatchers.IO) {
                    AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath("users/${identity.uid}") +
                            "?updateMask.fieldPaths=accountStatus",
                        "PATCH",
                        mapOf("accountStatus" to "active"),
                    )
                }
                withContext(Dispatchers.Main) { store.refresh() }.join()
                val acceptedVersions =
                    store.state.value.requiredLegalDocuments().associate { it.type to it.version }
                withContext(Dispatchers.Main) {
                        store.acceptLegalDocuments(acceptedVersions, "uk")!!
                    }
                    .join()
                assertEquals(null, store.state.value.error)
                assertTrue(store.state.value.readyForActions)
                assertEquals(
                    acceptedVersions.keys,
                    store.state.value.legalReceipts.map { it.type }.toSet(),
                )
                assertTrue(
                    store.state.value.legalReceipts.all {
                        it.acceptedAtMillis > 0 && it.profileAcceptedAtMillis > 0
                    }
                )

                val logs =
                    database
                        .collection("legalAcceptanceLogs")
                        .whereEqualTo("userId", identity.uid)
                        .get(Source.SERVER)
                        .await()
                logIds += logs.documents.map { it.id }
                assertEquals(acceptedVersions.size, logs.size())
                for (log in logs.documents) {
                    assertEquals("android", log.getString("acceptedFromPlatform"))
                    assertEquals("uk", log.getString("locale"))
                    assertEquals(BuildConfig.VERSION_NAME, log.getString("appVersion"))
                    assertEquals(
                        acceptedVersions[log.getString("documentType")],
                        log.getString("version"),
                    )
                    assertNotNull(log.getTimestamp("acceptedAt"))
                }
                val forged =
                    runCatching {
                        database
                            .collection("legalAcceptanceLogs")
                            .document("forged-${identity.uid}")
                            .set(
                                mapOf(
                                    "userId" to identity.uid,
                                    "acceptedAt" to FieldValue.serverTimestamp(),
                                )
                            )
                            .await()
                    }
                        .exceptionOrNull()
                        ?: throw AssertionError("Client-created legal receipts must be denied")
                assertEquals(AuthProblem.PERMISSION_DENIED, authProblem(forged))
                val direct =
                    runCatching {
                        database
                            .collection("users")
                            .document(identity.uid)
                            .update("acceptedTermsVersion", "forged-version")
                            .await()
                    }
                        .exceptionOrNull()
                        ?: throw AssertionError("Direct legal profile updates must be denied")
                assertEquals(AuthProblem.PERMISSION_DENIED, authProblem(direct))
                withContext(Dispatchers.Main) { store.signOut() }.join()
                assertEquals(AuthStage.GUEST, store.state.value.stage)
                assertTrue(store.state.value.legalReceipts.isEmpty())
                assertEquals(
                    AuthProblem.SESSION_CHANGED,
                    (runCatching {
                            acceptor.accept(identity.uid, terms, "uk")
                        }
                            .exceptionOrNull() as AuthException)
                        .problem,
                )
                backend.signIn(email, password)
            } finally {
                scope.cancel()
                val ownUid = uid
                if (ownUid != null && backend.current?.uid == ownUid)
                    backend.deleteCreatedUser(ownUid)
                backend.signOut()
                if (ownUid != null)
                    withContext(Dispatchers.IO) {
                        for (path in
                            listOf("users/$ownUid", "publicProfiles/$ownUid") +
                                logIds.map { "legalAcceptanceLogs/$it" }) {
                            AuthEmulatorFixtures.adminRequest(
                                8088,
                                AuthEmulatorFixtures.documentPath(path),
                                "DELETE",
                            )
                        }
                    }
            }
        }
}
