package at.uac.android

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.auth.bundledReferenceLegal
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Synthetic setup only: never included in the application APK, never accepts a cloud host/project.
 */
internal class LocalEmulatorFixtures(private val context: Context) {
    suspend fun seedLegal() {
        for (document in bundledReferenceLegal(context).take(2)) {
            seed(
                "legalDocuments/${document.type}",
                mapOf(
                    "activeVersion" to document.version,
                    "status" to "published",
                    "requiresAcceptance" to document.requiresAcceptance,
                ),
            )
            seed(
                "legalDocuments/${document.type}/versions/${document.version}",
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

    suspend fun seed(path: String, fields: Map<String, Any?>) =
        withContext(Dispatchers.IO) {
            require(path.split('/').none { it.isBlank() || it in setOf(".", "..") })
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents/$path",
                fields,
            )
        }

    suspend fun verificationCode(email: String): String =
        withContext(Dispatchers.IO) {
            require(email.endsWith(".invalid"))
            val codes =
                request(9098, "/emulator/v1/projects/demo-uac-android/oobCodes")
                    .getJSONArray("oobCodes")
            (0 until codes.length())
                .map { codes.getJSONObject(it) }
                .last {
                    it.optString("email") == email && it.optString("requestType") == "VERIFY_EMAIL"
                }
                .getString("oobCode")
        }

    private fun request(port: Int, path: String, fields: Map<String, Any?>? = null): JSONObject {
        LocalEnvironment.requireSafe()
        check(context.packageName == "at.uac.android.local")
        check(port in setOf(8088, 9098) && path.contains("/demo-uac-android/"))
        val connection = URL("http://10.0.2.2:$port$path").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 5_000
            connection.readTimeout = 5_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer owner")
            if (fields != null) {
                connection.requestMethod = "PATCH"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                val body =
                    JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) }))
                connection.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            check(connection.responseCode in 200..299) {
                "Synthetic fixture setup failed: ${connection.responseCode}"
            }
            return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    private fun value(field: Any?): JSONObject =
        when (field) {
            null -> JSONObject().put("nullValue", JSONObject.NULL)
            is String -> JSONObject().put("stringValue", field)
            is Boolean -> JSONObject().put("booleanValue", field)
            is Int,
            is Long -> JSONObject().put("integerValue", field.toString())
            is Instant -> JSONObject().put("timestampValue", field.toString())
            is Map<*, *> ->
                JSONObject()
                    .put(
                        "mapValue",
                        JSONObject()
                            .put(
                                "fields",
                                JSONObject(
                                    field.entries.associate { it.key.toString() to value(it.value) }
                                ),
                            ),
                    )
            else -> error("Unsupported fixture field")
        }
}
