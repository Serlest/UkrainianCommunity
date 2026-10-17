package at.uac.android.feature.directory

import java.net.URI

/** Narrow public destination shared by in-app navigation and external links. No arbitrary query routes. */
data class DirectoryRoute(val category: String? = null, val topic: String? = null,
    val section: String? = null, val region: String? = null, val recent: Boolean = false) {
    val path: String get() = if (recent) "directory/recent" else buildString {
        append("directory")
        category?.let { append("/$it") }
        topic?.let { append("/$it") }
        val params = listOfNotNull(section?.let { "section=$it" }, region?.let { "region=$it" })
        if (params.isNotEmpty()) append("?" + params.joinToString("&"))
    }
    companion object {
        val regions = setOf("burgenland", "kaernten", "niederoesterreich", "oberoesterreich",
            "salzburg", "steiermark", "tirol", "vorarlberg", "wien")
        fun parse(route: String): DirectoryRoute? {
            if (route.length > 512 || route.any { it.isISOControl() || it.isWhitespace() } || '%' in route || '\\' in route) return null
            val uri = runCatching { URI(route) }.getOrNull() ?: return null
            if (uri.scheme != null || uri.rawAuthority != null || uri.rawFragment != null) return null
            val parts = uri.path.orEmpty().split('/')
            if (parts.firstOrNull() != "directory" || parts.size !in 1..3) return null
            if (parts == listOf("directory", "recent")) return DirectoryRoute(recent = true).takeIf { uri.rawQuery == null }
            if (parts.drop(1).any { !DirectoryCatalog.validId(it) } || parts.getOrNull(1) in setOf("manage", "recent")) return null
            val parameters = mutableMapOf<String, String>()
            uri.rawQuery?.split('&')?.forEach {
                val pair = it.split('=')
                if (parts.size != 3 || pair.size != 2 || pair[0] !in setOf("section", "region") ||
                    parameters.put(pair[0], pair[1]) != null) return null
            }
            val section = parameters["section"]
            val region = parameters["region"]
            if (section != null && !DirectoryCatalog.validId(section) || region != null && region !in regions) return null
            return DirectoryRoute(parts.getOrNull(1), parts.getOrNull(2), section, region)
        }
    }
}
