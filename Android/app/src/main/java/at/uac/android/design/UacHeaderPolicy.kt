package at.uac.android.design

/** Auth forms already own their meaningful title; keep public/account roots fully branded. */
internal fun isCompactAuthHeaderRoute(route: String): Boolean =
    route == "profile/login" || route == "profile/register" || route == "profile/reset"
