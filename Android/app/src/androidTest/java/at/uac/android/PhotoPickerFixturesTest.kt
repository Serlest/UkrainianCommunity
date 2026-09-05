package at.uac.android

import android.net.Uri
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhotoPickerFixturesTest {
    @Test
    fun documentClickRequiresAdvertisedActionAndVisibleEnabledNativePackage() {
        val click = listOf(AccessibilityNodeInfo.ACTION_CLICK)
        // A separate isClickable flag is deliberately not accepted as proof of an available action.
        assertTrue(
            PhotoPickerFixtures.documentClickAllowed("com.android.documentsui", true, true, click)
        )
        assertTrue(
            PhotoPickerFixtures.documentClickAllowed(
                "com.google.android.documentsui",
                true,
                true,
                click,
            )
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed(
                "com.android.documentsui",
                true,
                true,
                emptyList(),
            )
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed(
                "com.android.documentsui",
                true,
                true,
                listOf(AccessibilityNodeInfo.ACTION_SELECT),
            )
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed("com.android.documentsui", true, false, click)
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed("com.android.documentsui", false, true, click)
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed("at.uac.android.local", true, true, click)
        )
        assertFalse(
            PhotoPickerFixtures.documentClickAllowed(
                "com.google.android.photopicker",
                true,
                true,
                click,
            )
        )
        assertFalse(PhotoPickerFixtures.documentClickAllowed(null, true, true, click))
    }

    @Test
    fun explicitCompatibilityPickerCanBeRecognizedWithoutSeedingAnyMedia() {
        assumeTrue(isExplicitApi26CompatibilityAvd())
        // The real Main cancel journey opens ACTION_OPEN_DOCUMENT without creating a fixture.
        // This guard regression performs no provider, MediaStore, or native-window mutation.
        assertEquals(
            setOf("com.android.documentsui", "com.google.android.documentsui"),
            PhotoPickerFixtures.pickerPackages(),
        )
    }

    @Test
    fun unregisteredDocumentCannotReachNativeSelection() {
        assumeTrue(isExplicitApi26CompatibilityAvd())
        val token = UUID.randomUUID().toString()
        val fixture =
            PhotoPickerFixtures.Fixture(
                Uri.parse(
                    "content://at.uac.android.local.test.photo_documents/document/${token}_UAC-NeverSeeded"
                ),
                "UAC-NeverSeeded",
                byteArrayOf(),
                token,
            )
        val failure = runCatching { PhotoPickerFixtures.selectOnlyPhoto(fixture) }.exceptionOrNull()
        assertTrue(failure is IllegalStateException)
        assertEquals(
            "Only this process's registered synthetic photo may be selected",
            failure?.message,
        )
    }
}
