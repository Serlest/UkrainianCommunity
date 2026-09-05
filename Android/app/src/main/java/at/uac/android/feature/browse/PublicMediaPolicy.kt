package at.uac.android.feature.browse

import at.uac.android.core.LocalStorage
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.URI
import java.net.URLDecoder

/** Canonical demo URLs are aliases, never permission to contact cloud storage. */
object PublicMediaPolicy {
    const val MAX_BYTES = 3_000_000
    private const val LOCAL = "http://10.0.2.2:9198"
    private const val PREFIX = "/v0/b/${LocalStorage.BUCKET}/o/"

    fun address(value: String): String? = runCatching {
        if (value.length !in 1..5_000 || value.any(Char::isISOControl)) return null
        val uri = URI(value)
        val local = uri.scheme == "http" && uri.host == "10.0.2.2" && uri.port == 9198
        val demoAlias =
            uri.scheme == "https" && uri.host == "firebasestorage.googleapis.com" && uri.port == -1
        if ((!local && !demoAlias) || uri.rawUserInfo != null || uri.rawFragment != null)
            return null
        if (!uri.rawPath.startsWith(PREFIX)) return null
        val path = URLDecoder.decode(uri.rawPath.removePrefix(PREFIX), "UTF-8")
        if (
            path.isBlank() ||
                path.length > 2_048 ||
                path.any(Char::isISOControl) ||
                path.split('/').any { it.isBlank() || it in setOf(".", "..") } ||
                '\\' in path ||
                '%' in path
        )
            return null
        val query = uri.rawQuery ?: return null
        val fields =
            query.split('&').map { field ->
                val pair = field.split('=', limit = 2)
                if (pair.size != 2) return null
                URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair[1], "UTF-8")
            }
        if (
            fields.map { it.first }.distinct().size != fields.size ||
                fields.any { it.first !in setOf("alt", "token") }
        )
            return null
        if (fields.toMap()["alt"] != "media") return null
        fields.toMap()["token"]?.let { if (!it.matches(Regex("[A-Za-z0-9_-]{1,512}"))) return null }
        "$LOCAL${uri.rawPath}?$query"
    }
        .getOrNull()

    /** Stop before allocating/copying an over-budget chunk, including unknown-length responses. */
    fun bytes(input: InputStream, ensureActive: () -> Unit = {}): ByteArray {
        val output = ByteArrayOutputStream(32_768)
        val buffer = ByteArray(8_192)
        while (true) {
            ensureActive()
            val count = input.read(buffer)
            if (count < 0) break
            check(count <= MAX_BYTES - output.size()) { "Public media exceeds local budget" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    fun sampleSize(width: Int, height: Int): Int {
        require(width in 1..8_192 && height in 1..8_192)
        var sample = 1
        while ((maxOf(width, height) + sample - 1) / sample > 1_600) sample *= 2
        return sample
    }
}

fun localMediaUrl(value: String): Boolean =
    value.startsWith("http://10.0.2.2:9198/") && PublicMediaPolicy.address(value) != null
