package at.uac.android.design

/** Keep the large brand lockup for the welcoming home feed; secondary routes use an app bar. */
internal fun isCompactHeaderRoute(route: String): Boolean = route != "home"
