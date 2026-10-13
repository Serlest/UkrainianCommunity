package at.uac.android.design

/** Match the iOS brand lockup on all five root tabs; secondary routes use an app bar. */
internal fun isCompactHeaderRoute(route: String): Boolean =
    route !in setOf("home", "events", "organizations", "directory", "profile")
