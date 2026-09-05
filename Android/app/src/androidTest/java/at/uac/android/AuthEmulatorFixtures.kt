package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.auth.bundledReferenceLegal
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Test setup only. No production host or credential can be supplied here. */
internal object AuthEmulatorFixtures {
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
                        "status" to "published",
                        "requiresAcceptance" to document.requiresAcceptance,
                    ),
                )
                adminRequest(
                    8088,
                    "$root/versions/${document.version}",
                    "PATCH",
                    mapOf(
                        "version" to document.version,
                        "status" to "published",
                        "requiresAcceptance" to document.requiresAcceptance,
                        "locales" to
                            document.texts.mapValues { (locale, text) ->
                                mapOf(
                                    "title" to document.title(locale),
                                    "contentText" to text,
                                    "contentMarkdown" to text,
                                )
                            },
                    ),
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
