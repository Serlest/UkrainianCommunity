package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.bundledReferenceLegal
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Test setup only. No production host or credential can be supplied here. */
internal object AuthEmulatorFixtures {
    /** Complete a synthetic draft from the emulator's current published documents. */
    suspend fun currentLegalDraft(draft: AuthRegistration): AuthRegistration {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val documents = FirestoreAuthProfiles(LocalFirebase.firestore(context))
            .legalDocuments().associateBy { it.type }
        val terms = documents.getValue("terms")
        val privacy = documents.getValue("privacy")
        return draft.copy(
            termsVersion = terms.version,
            privacyVersion = privacy.version,
            termsContentHash = requireNotNull(terms.contentHash),
            privacyContentHash = requireNotNull(privacy.contentHash),
        )
    }

    suspend fun actionCode(email: String, type: String): String =
        withContext(Dispatchers.IO) {
            val json =
                adminRequest(9098, "/emulator/v1/projects/${LocalEnvironment.PROJECT_ID}/oobCodes")
            val list = json.getJSONArray("oobCodes")
            (0 until list.length())
                .map { list.getJSONObject(it) }
                .last { it.optString("email") == email && it.optString("requestType") == type }
                .getString("oobCode")
        }

    suspend fun seedLegalReference() =
        withContext(Dispatchers.IO) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            for (document in bundledReferenceLegal(context).take(2)) {
                val root = documentPath("legalDocuments/${document.type}")
                adminRequest(
                    8088,
                    root,
                    "PATCH",
                    mapOf(
                        "activeVersion" to document.version,
                        "versionNumber" to build80VersionNumber(document.version),
                        "status" to "published",
                        "requiresAcceptance" to document.requiresAcceptance,
                    ),
                )
                adminRequest(
                    8088,
                    "$root/versions/${document.version}",
                    "PATCH",
                    build80LegalFixture(document),
                )
            }
        }

    fun documentPath(path: String) =
        "/v1/projects/${LocalEnvironment.PROJECT_ID}/databases/(default)/documents/$path"

    fun adminRequest(
        port: Int,
        path: String,
        method: String = "GET",
        fields: Map<String, Any>? = null,
    ): JSONObject {
        check(port in setOf(LocalEnvironment.AUTH_PORT, LocalEnvironment.FIRESTORE_PORT))
        check(path.contains("/${LocalEnvironment.PROJECT_ID}/"))
        val connection =
            URL("http://${LocalEnvironment.HOST}:$port$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("Authorization", "Bearer owner")
            if (fields != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                val payload =
                    JSONObject()
                        .put(
                            "fields",
                            JSONObject(fields.mapValues { (_, value) -> firestoreValue(value) }),
                        )
                connection.outputStream.use { it.write(payload.toString().toByteArray()) }
            }
            val status = connection.responseCode
            check(status in 200..299 || (method == "DELETE" && status == 404)) {
                "Local test setup failed: $status"
            }
            if (status == 404) return JSONObject()
            val response = connection.inputStream.bufferedReader().use { it.readText() }
            return if (response.isBlank()) JSONObject() else JSONObject(response)
        } finally {
            connection.disconnect()
        }
    }

    private fun firestoreValue(value: Any): JSONObject =
        when (value) {
            is java.time.Instant -> JSONObject().put("timestampValue", value.toString())
            is Number -> JSONObject().put("integerValue", value.toLong().toString())
            is String -> JSONObject().put("stringValue", value)
            is Boolean -> JSONObject().put("booleanValue", value)
            is Map<*, *> ->
                JSONObject()
                    .put(
                        "mapValue",
                        JSONObject()
                            .put(
                                "fields",
                                JSONObject(
                                    value.entries.associate {
                                        it.key.toString() to firestoreValue(it.value!!)
                                    }
                                ),
                            ),
                    )
            is List<*> ->
                JSONObject()
                    .put(
                        "arrayValue",
                        JSONObject().put("values", JSONArray(value.map { firestoreValue(it!!) })),
                    )
            else -> error("Unsupported synthetic fixture type")
        }
}
