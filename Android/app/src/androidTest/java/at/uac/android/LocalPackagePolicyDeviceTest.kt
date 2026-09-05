package at.uac.android

import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.security.NetworkSecurityPolicy
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.xmlpull.v1.XmlPullParser

/**
 * Inspects the installed package, including transitive manifest entries. No permissions or settings
 * are changed.
 */
class LocalPackagePolicyDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun localPackage() {
        check(context.packageName == "at.uac.android.local")
        check(
            BuildConfig.DEBUG
        ) // The test-only Compose host is deliberately not a future release surface.
    }

    @Suppress("DEPRECATION")
    @Test
    fun installedPermissionsAndOwnExportedComponentsStayNarrow() {
        localPackage()
        val info =
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_PERMISSIONS or
                    PackageManager.GET_ACTIVITIES or
                    PackageManager.GET_RECEIVERS or
                    PackageManager.GET_SERVICES or
                    PackageManager.GET_PROVIDERS,
            )
        val permissions = info.requestedPermissions.orEmpty()
        val flags = info.requestedPermissionsFlags ?: IntArray(permissions.size)
        assertEquals(permissions.size, flags.size)
        val implicit =
            permissions.indices
                .filter { flags[it] and PackageInfo.REQUESTED_PERMISSION_IMPLICIT != 0 }
                .map { permissions[it] }
                .toSet()
        // API 37's platform.xml splits INTERNET for targetSdk<37. This is not an app manifest
        // request.
        val compatibility =
            if (Build.VERSION.SDK_INT >= 37 && context.applicationInfo.targetSdkVersion < 37)
                setOf("android.permission.ACCESS_LOCAL_NETWORK")
            else emptySet()
        assertEquals(compatibility, implicit)
        assertEquals(
            setOf(
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.USE_BIOMETRIC",
                "android.permission.USE_FINGERPRINT",
                "android.permission.POST_NOTIFICATIONS",
                "android.permission.RECEIVE_BOOT_COMPLETED",
                "android.permission.WAKE_LOCK",
                "com.google.android.providers.gsf.permission.READ_GSERVICES",
                "${context.packageName}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
            ),
            permissions.toSet() - implicit,
        )
        val ownActivities =
            info.activities.orEmpty().filter { it.name.startsWith("at.uac.android.") }
        assertEquals(
            setOf("at.uac.android.MainActivity"),
            ownActivities.filter { it.exported }.map { it.name }.toSet(),
        )
        assertFalse(
            ownActivities.single { it.name == "at.uac.android.FoundationActivity" }.exported
        )
        assertFalse(
            info.receivers
                .orEmpty()
                .single { it.name == "at.uac.android.feature.reminders.ReminderReceiver" }
                .exported
        )
        assertTrue(
            info.providers.orEmpty().none {
                it.exported || it.name == "com.google.firebase.provider.FirebaseInitProvider"
            }
        )
        assertTrue(
            info.services.orEmpty().filter { it.exported }.all { !it.permission.isNullOrBlank() }
        )
        assertTrue(
            info.receivers.orEmpty().filter { it.exported }.all { !it.permission.isNullOrBlank() }
        )
    }

    @Test
    fun activeNetworkPolicyAllowsOnlyTheExactLocalEmulatorCleartextHost() {
        localPackage()
        val policy = NetworkSecurityPolicy.getInstance()
        assertFalse(policy.isCleartextTrafficPermitted)
        assertTrue(policy.isCleartextTrafficPermitted("10.0.2.2"))
        for (host in
            listOf(
                "10.0.2.2.example.invalid",
                "127.0.0.1",
                "127.0.0.2",
                "::1",
                "[::1]",
                "localhost",
                "ip6-localhost",
                "example.localhost",
                "10.0.2.3",
                "firebasestorage.googleapis.com",
                "example.invalid",
            )) assertFalse(host, policy.isCleartextTrafficPermitted(host))
    }

    @Test
    fun backupAndDeviceTransferRulesExcludeEveryDataDomain() {
        localPackage()
        assertEquals(0, context.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        val domains = setOf("root", "file", "database", "sharedpref", "external")
        val exclusions = mutableMapOf<String, MutableSet<String>>()
        context.resources.getXml(R.xml.data_extraction_rules).use { xml ->
            var section: String? = null
            while (xml.eventType != XmlPullParser.END_DOCUMENT) {
                if (xml.eventType == XmlPullParser.START_TAG)
                    when (xml.name) {
                        "cloud-backup",
                        "device-transfer" -> section = xml.name
                        "include" ->
                            fail(
                                "A broad include must not override this local package's no-backup policy"
                            )
                        "exclude" -> {
                            val group = checkNotNull(section)
                            assertEquals(".", xml.getAttributeValue(null, "path"))
                            exclusions
                                .getOrPut(group) { mutableSetOf() }
                                .add(xml.getAttributeValue(null, "domain"))
                        }
                    }
                if (xml.eventType == XmlPullParser.END_TAG && xml.name == section) section = null
                xml.next()
            }
        }
        assertEquals(mapOf("cloud-backup" to domains, "device-transfer" to domains), exclusions)
    }
}
