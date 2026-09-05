package at.uac.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.personal.PersonalSession
import at.uac.android.feature.profilemedia.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileMediaDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun encoded(
        bitmap: Bitmap,
        format: Bitmap.CompressFormat = Bitmap.CompressFormat.JPEG,
    ): ByteArray =
        ByteArrayOutputStream().use {
            val compressed = bitmap.compress(format, 100, it)
            System.out.println(
                "SYNTHETIC_RASTER_ENCODE format=$format compressed=$compressed bytes=${it.size()}"
            )
            assertTrue("Synthetic raster compression must succeed", compressed)
            it.toByteArray()
        }

    private fun solid(): ByteArray =
        Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888).let { bitmap ->
            try {
                bitmap.eraseColor(Color.rgb(20, 80, 160))
                encoded(bitmap)
            } finally {
                bitmap.recycle()
            }
        }

    @Test
    fun actualRasterProcessingNormalizesEightOrientationsAndStripsMetadata() = runBlocking {
        val source = Bitmap.createBitmap(80, 48, Bitmap.Config.ARGB_8888)
        val colors = listOf(Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW)
        Canvas(source).apply {
            val paint = Paint()
            for (index in colors.indices) {
                paint.color = colors[index]
                drawRect(
                    (index % 2) * 40f,
                    (index / 2) * 24f,
                    (index % 2 + 1) * 40f,
                    (index / 2 + 1) * 24f,
                    paint,
                )
            }
        }
        val original =
            try {
                encoded(source)
            } finally {
                source.recycle()
            }
        val expected =
            listOf(
                listOf(0, 1, 2, 3),
                listOf(1, 0, 3, 2),
                listOf(3, 2, 1, 0),
                listOf(2, 3, 0, 1),
                listOf(0, 2, 1, 3),
                listOf(2, 0, 3, 1),
                listOf(3, 1, 2, 0),
                listOf(1, 3, 0, 2),
            )
        val sourceBounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(original, 0, original.size, sourceBounds)
        val jpegMagic =
            original.size >= 3 &&
                original[0] == 0xff.toByte() &&
                original[1] == 0xd8.toByte() &&
                original[2] == 0xff.toByte()
        assertTrue("Synthetic orientation source must really be JPEG", jpegMagic)
        assertEquals("image/jpeg", sourceBounds.outMimeType)
        assertEquals(80, sourceBounds.outWidth)
        assertEquals(48, sourceBounds.outHeight)
        for (orientation in 1..8) {
            val file = File.createTempFile("synthetic-avatar-exif-", ".jpg", context.cacheDir)
            try {
                file.writeBytes(original)
                assertArrayEquals("Synthetic fixture write read-back", original, file.readBytes())
                val fixtureExif = ExifInterface(file.absolutePath)
                val structuralDiagnostic =
                    "orientation=$orientation jpegMagic=$jpegMagic sourceBytes=${original.size} " +
                        "fileBytes=${file.length()} bitmapMime=${sourceBounds.outMimeType} " +
                        "bitmapWidth=${sourceBounds.outWidth} bitmapHeight=${sourceBounds.outHeight} " +
                        "exifWidth=${fixtureExif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, -1)} " +
                        "exifHeight=${fixtureExif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, -1)} " +
                        "inputOrientation=${fixtureExif.getAttributeInt(ExifInterface.TAG_ORIENTATION, -1)}"
                // These are generated test bytes, never a user's image, path or metadata.
                System.out.println("SYNTHETIC_RASTER_BEFORE_EXIF_SAVE $structuralDiagnostic")
                fixtureExif.apply {
                    setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                    setAttribute(ExifInterface.TAG_MAKE, "SYNTHETIC_PRIVATE_CAMERA")
                    setAttribute(ExifInterface.TAG_DATETIME, "2026:09:03 02:00:00")
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE, "48/1,12/1,0/1")
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "16/1,18/1,0/1")
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
                    try {
                        saveAttributes()
                    } catch (error: IOException) {
                        // Preserve the actual failure and tiny source; never skip an orientation.
                        throw AssertionError(
                            "Synthetic EXIF fixture save failed: $structuralDiagnostic",
                            error,
                        )
                    }
                }
                val savedExif = ExifInterface(file.absolutePath)
                assertNotNull(savedExif.latLong)
                assertEquals(
                    orientation,
                    savedExif.getAttributeInt(ExifInterface.TAG_ORIENTATION, -1),
                )
                assertEquals(
                    "SYNTHETIC_PRIVATE_CAMERA",
                    savedExif.getAttribute(ExifInterface.TAG_MAKE),
                )
                assertEquals(
                    "2026:09:03 02:00:00",
                    savedExif.getAttribute(ExifInterface.TAG_DATETIME),
                )
                val orientedBytes = file.readBytes()
                assertTrue(
                    "Tiny EXIF JPEG regression must remain below the old sniff size",
                    orientedBytes.size < 5_000,
                )
                if (orientation == 6 && isExplicitApi26CompatibilityAvd()) {
                    // Independently preserve the exact Android 8 parser regression. The product
                    // must normalize this very same input, not pad it or default to orientation 1.
                    val legacy = android.media.ExifInterface(orientedBytes.inputStream())
                    assertEquals(
                        0,
                        legacy.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, -1),
                    )
                    assertEquals(6, savedExif.getAttributeInt(ExifInterface.TAG_ORIENTATION, -1))
                    System.out.println(
                        "SYNTHETIC_TINY_EXIF_REGRESSION bytes=${orientedBytes.size} legacyOrientation=0 supportedOrientation=6"
                    )
                }
                val jpeg =
                    LocalImagePreparation.prepareBytes(
                        orientedBytes,
                        LocalImagePolicy.ORG_LOGO,
                    )
                assertTrue(LocalImagePreparation.validJpeg(jpeg, LocalImagePolicy.ORG_LOGO))
                val exif = ExifInterface(jpeg.inputStream())
                assertNull(exif.getAttribute(ExifInterface.TAG_MAKE))
                assertNull(exif.getAttribute(ExifInterface.TAG_DATETIME))
                assertNull(exif.latLong)
                assertEquals(
                    ExifInterface.ORIENTATION_UNDEFINED,
                    exif.getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_UNDEFINED,
                    ),
                )
                val rendered = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)!!
                try {
                    assertEquals(if (orientation >= 5) 48 else 80, rendered.width)
                    assertEquals(if (orientation >= 5) 80 else 48, rendered.height)
                    for (quadrant in 0..3) {
                        val actual =
                            rendered.getPixel(
                                rendered.width * (if (quadrant % 2 == 0) 1 else 3) / 4,
                                rendered.height * (if (quadrant / 2 == 0) 1 else 3) / 4,
                            )
                        val wanted = colors[expected[orientation - 1][quadrant]]
                        assertTrue(
                            "EXIF $orientation quadrant $quadrant",
                            colorDistance(actual, wanted) < 80,
                        )
                    }
                } finally {
                    rendered.recycle()
                }
            } finally {
                assertTrue(file.delete())
            }
        }
    }

    @Test
    fun actualPngAlphaFlattensToWhiteAndAvatarRemainsCenterCropped() = runBlocking {
        val transparent = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val png =
            try {
                transparent.eraseColor(Color.TRANSPARENT)
                Canvas(transparent)
                    .drawRect(32f, 32f, 96f, 96f, Paint().apply { color = Color.RED })
                encoded(transparent, Bitmap.CompressFormat.PNG)
            } finally {
                transparent.recycle()
            }
        assertArrayEquals(
            byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10),
            png.copyOfRange(0, 8),
        )
        val pngBounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(png, 0, png.size, pngBounds)
        assertEquals("image/png", pngBounds.outMimeType)
        val white = LocalImagePreparation.prepareBytes(png, LocalImagePolicy.AVATAR)
        assertTrue(LocalImagePreparation.validJpeg(white, LocalImagePolicy.AVATAR))
        val whiteBitmap = BitmapFactory.decodeByteArray(white, 0, white.size)!!
        try {
            assertEquals(128, whiteBitmap.width)
            assertEquals(128, whiteBitmap.height)
            assertTrue(colorDistance(Color.WHITE, whiteBitmap.getPixel(2, 2)) < 20)
            assertTrue(colorDistance(Color.RED, whiteBitmap.getPixel(64, 64)) < 40)
        } finally {
            whiteBitmap.recycle()
        }
        val wide = Bitmap.createBitmap(300, 100, Bitmap.Config.ARGB_8888)
        val wideBytes =
            try {
                Canvas(wide).apply {
                    drawColor(Color.RED)
                    drawRect(100f, 0f, 200f, 100f, Paint().apply { color = Color.GREEN })
                    drawRect(200f, 0f, 300f, 100f, Paint().apply { color = Color.BLUE })
                }
                encoded(wide)
            } finally {
                wide.recycle()
            }
        val centered = LocalImagePreparation.prepareBytes(wideBytes, LocalImagePolicy.AVATAR)
        val square = BitmapFactory.decodeByteArray(centered, 0, centered.size)!!
        try {
            assertEquals(100, square.width)
            assertEquals(100, square.height)
            assertTrue(colorDistance(Color.GREEN, square.getPixel(50, 50)) < 30)
        } finally {
            square.recycle()
        }
    }

    @Test
    fun ownCanonicalStorageUploadRulesAndProfileReadBackOrOfflineGate() = runBlocking {
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val storage = LocalStorage.instance(context)
        val source = FirebaseProfileMediaSource(storage, db, auth)
        val photo =
            PreparedAvatar(LocalImagePreparation.prepareBytes(solid(), LocalImagePolicy.AVATAR))
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            try {
                ProfileMediaRepository(source, { null }).save(photo, AvatarOperation(), {}, {})
                fail("Guest upload")
            } catch (error: ProfileMediaException) {
                assertEquals(ProfileMediaFailure.SIGN_IN, error.reason)
            }
            return@runBlocking
        }
        val email = "avatar-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-avatar-local-only!"
        var uid: String? = null
        auth.signOut()
        try {
            val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
            uid = user.uid
            db.document("users/$uid")
                .set(
                    registeredProfileFields(
                        uid,
                        AuthRegistration(
                            email,
                            "Avatar Demo",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val own = storage.reference.child(profileAvatarPath(uid))
            denied {
                own.putBytes(
                        photo.jpeg,
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
            }
            user.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            user.reload().await()
            auth.currentUser!!.getIdToken(true).await()
            assertTrue(auth.currentUser!!.isEmailVerified)
            val session = PersonalSession(uid, true, true, 1)
            val repository = ProfileMediaRepository(source, { session })
            // A concurrent text update must survive the avatar-only transaction.
            db.document("users/$uid")
                .update(
                    mapOf(
                        "displayName" to "Fresh server name",
                        "city" to "Graz",
                        "bio" to "Private biography",
                    )
                )
                .await()
            val result = repository.save(photo, AvatarOperation(), {}, {})
            assertTrue(LocalStorage.urlMatches(result.draft.avatarUrl, profileAvatarPath(uid)))
            assertEquals("Fresh server name", result.draft.displayName)
            assertEquals("Graz", result.draft.city)
            assertEquals("Private biography", result.draft.bio)
            assertArrayEquals(photo.jpeg, own.getBytes(1_500_000).await())
            assertEquals("image/jpeg", own.metadata.await().contentType)
            val published = db.document("publicProfiles/$uid").get(Source.SERVER).await()
            assertEquals(result.draft.avatarUrl, published.getString("avatarURL"))
            assertEquals("Fresh server name", published.getString("displayName"))
            assertFalse(published.contains("bio"))
            assertFalse(published.contains("email"))
            assertFalse(published.contains("telegramUsername"))
            val privateProfile = db.document("users/$uid").get(Source.SERVER).await()
            assertEquals("user", privateProfile.getString("globalRole"))
            assertEquals("active", privateProfile.getString("accountStatus"))
            assertEquals(email, privateProfile.getString("email"))
            assertEquals(uid, repository.save(photo, AvatarOperation(), {}, {}).uid)
            denied {
                storage.reference
                    .child("profileImages/foreign-avatar-user/avatar.jpg")
                    .putBytes(
                        photo.jpeg,
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
            }
            denied {
                storage.reference
                    .child("profileImages/$uid/other.jpg")
                    .putBytes(
                        photo.jpeg,
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
            }
            denied {
                own.putBytes(
                        photo.jpeg,
                        StorageMetadata.Builder().setContentType("image/png").build(),
                    )
                    .await()
            }
            denied {
                own.putBytes(
                        ByteArray(3 * 1024 * 1024),
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
            }
            assertArrayEquals(photo.jpeg, own.getBytes(1_500_000).await())
            own.delete().await()
        } finally {
            if (uid != null) {
                if (auth.currentUser?.uid == uid && auth.currentUser?.isEmailVerified == true) {
                    try {
                        storage.reference.child(profileAvatarPath(uid)).delete().await()
                    } catch (error: StorageException) {
                        if (error.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) throw error
                    }
                }
                withContext(Dispatchers.IO) {
                    listOf("users/$uid", "publicProfiles/$uid").forEach {
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath(it),
                            "DELETE",
                        )
                    }
                }
            }
            auth.currentUser?.delete()?.await()
            auth.signOut()
        }
    }

    private fun colorDistance(a: Int, b: Int) =
        kotlin.math.abs(Color.red(a) - Color.red(b)) +
            kotlin.math.abs(Color.green(a) - Color.green(b)) +
            kotlin.math.abs(Color.blue(a) - Color.blue(b))

    private suspend fun denied(action: suspend () -> Unit) {
        try {
            action()
            fail("Unchanged Storage Rules must deny the upload")
        } catch (error: StorageException) {
            assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
        }
    }
}
