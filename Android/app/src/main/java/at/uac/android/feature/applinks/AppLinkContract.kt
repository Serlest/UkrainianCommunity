package at.uac.android.feature.applinks

import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.personal.validDocumentId
import java.net.URI

enum class AppLinkAccess {
    PUBLIC,
    SIGNED_IN,
}

data class AppLinkDestination(val route: String, val access: AppLinkAccess)

enum class AppLinkAction {
    OPEN,
    PROMPT_LOGIN,
    WAIT,
}

data class AppLinkResolution(val action: AppLinkAction, val route: String? = null)

/**
 * The manifest is only discovery. This parser is the security boundary: an Intent cannot invent an
 * internal route, change accounts, or turn a web URL into authorization.
 */
object AppLinkContract {
    const val CUSTOM_SCHEME = "ukrainiancommunity"

    fun parse(value: String?): AppLinkDestination? {
        if (value.isNullOrBlank() || value.length > 2_048) return null
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        if (
            uri.rawQuery != null ||
                uri.rawFragment != null ||
                uri.rawUserInfo != null ||
                uri.port != -1
        )
            return null
        val scheme = uri.scheme?.lowercase() ?: return null
        val rawPath = uri.rawPath.orEmpty()
        if (rawPath.contains(Regex("%(?:2f|5c|2e)", RegexOption.IGNORE_CASE))) return null
        val segments = uri.path.orEmpty().split('/').filter(String::isNotEmpty)
        if (segments.any { it == "." || it == ".." || it.contains('\\') }) return null

        if (scheme != CUSTOM_SCHEME) return null
        val host = uri.host?.lowercase() ?: return null
        val route = route(listOf(host) + segments) ?: return null
        return if (route == "profile/inbox") AppLinkDestination(route, AppLinkAccess.SIGNED_IN)
        else AppLinkDestination(route, AppLinkAccess.PUBLIC)
    }

    fun resolve(
        destination: AppLinkDestination,
        signedInReady: Boolean,
        guest: Boolean,
        privateSurfaceReady: Boolean,
    ): AppLinkResolution =
        when {
            destination.access == AppLinkAccess.PUBLIC ->
                AppLinkResolution(AppLinkAction.OPEN, destination.route)
            signedInReady && privateSurfaceReady ->
                AppLinkResolution(AppLinkAction.OPEN, destination.route)
            guest -> AppLinkResolution(AppLinkAction.PROMPT_LOGIN, "profile/login")
            else -> AppLinkResolution(AppLinkAction.WAIT)
        }

    private fun route(parts: List<String>): String? =
        when {
            parts == listOf("inbox") -> "profile/inbox"
            parts.size == 2 && parts[0] in setOf("news", "events") ->
                parts[1].takeIf(::validDocumentId)?.let { "${parts[0]}/$it" }
            parts.size == 2 && parts[0] == "organizations" ->
                parts[1].takeIf(OrganizationContract::id)?.let { "organizations/$it" }
            else -> null
        }
}
