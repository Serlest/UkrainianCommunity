package at.uac.android.feature.personal

/** UI route guard; repository/server authorization remains independently enforced. */
data class ProfileManagementAccess(
    val owner: Boolean = false,
    val moderator: Boolean = false,
    val support: Boolean = false,
) {
    fun allows(route: String): Boolean {
        val root = route.split('/').take(2).joinToString("/")
        return when {
            route == "profile/announcements/manage" ||
                route.startsWith("profile/announcements/manage/") -> owner
            root in
                setOf(
                    "profile/analytics",
                    "profile/donation-settings",
                    "profile/featured-banners",
                    "profile/content-planning",
                    "profile/legal-evidence",
                ) -> owner
            root in
                setOf(
                    "profile/system-logs",
                    "profile/users",
                    "profile/moderation",
                    "profile/organization-review",
                ) -> moderator
            root == "profile/support" -> support
            root == "profile/administration" -> owner || moderator || support
            else -> true
        }
    }
}
