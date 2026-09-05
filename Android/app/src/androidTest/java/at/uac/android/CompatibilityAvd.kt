package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry

/** Additional test-only opt-in for the exact disposable minimum-version AVD created by root. */
internal fun isExplicitApi26CompatibilityAvd(): Boolean {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    if (
        InstrumentationRegistry.getArguments().getString("expectCompatibilityApi26") != "true" ||
            Build.VERSION.SDK_INT != 26 ||
            Build.HARDWARE != "ranchu" ||
            Build.MODEL != "Android SDK built for arm64" ||
            instrumentation.targetContext.packageName != "at.uac.android.local"
    )
        return false
    fun property(name: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(
                instrumentation.uiAutomation.executeShellCommand("getprop $name")
            )
            .bufferedReader()
            .use { it.readLine()?.trim().orEmpty() }
    return property("ro.kernel.qemu") == "1" &&
        property("ro.kernel.qemu.avd_name") == "UAC_API_26_Compat_ARM64"
}
