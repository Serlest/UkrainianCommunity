package at.uac.android.feature.browse

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import at.uac.android.R
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

@Composable
fun PublicImage(
    url: String,
    description: String,
    language: String,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    fallback: UacIcon = UacIcon.NEWS,
    presentation: PublicImagePresentation = PublicImagePresentation.STANDARD,
) {
    val address = remember(url) { PublicMediaPolicy.address(url) }
    var bitmap by remember(address, presentation) { mutableStateOf<ImageBitmap?>(null) }
    var loading by remember(address, presentation) { mutableStateOf(address != null) }
    LaunchedEffect(address, presentation) {
        if (address != null)
            bitmap =
                withContext(Dispatchers.IO) {
                    PublicImageWork.load(presentation) {
                        val context = currentCoroutineContext()
                        val connection = URI(address).toURL().openConnection() as HttpURLConnection
                        try {
                            connection.instanceFollowRedirects = false
                            connection.connectTimeout = 3_000
                            connection.readTimeout = 3_000
                            check(connection.responseCode == 200)
                            check(connection.contentLengthLong <= PublicMediaPolicy.MAX_BYTES)
                            val bytes =
                                connection.inputStream.use {
                                    PublicMediaPolicy.bytes(it) { context.ensureActive() }
                                }
                            context.ensureActive()
                            decodePublicImage(bytes, presentation)?.asImageBitmap()
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            null
                        } finally {
                            connection.disconnect()
                        }
                    }
                }
        loading = false
    }
    if (presentation != PublicImagePresentation.STANDARD) {
        BoxWithConstraints(modifier.clipToBounds(), contentAlignment = Alignment.Center) {
            check(constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
                "Public image viewport must be bounded"
            }
            val scale =
                if (presentation == PublicImagePresentation.VIEWPORT_FIT) ContentScale.Fit
                else ContentScale.Crop
            when {
                url == "https://example.invalid/media/community.png" ->
                    Image(
                        painterResource(R.drawable.ic_local_uac),
                        description,
                        Modifier.fillMaxSize(),
                        contentScale = scale,
                    )
                bitmap != null ->
                    Image(
                        bitmap!!,
                        description,
                        Modifier.fillMaxSize().testTag("loaded-media"),
                        contentScale = scale,
                    )
                loading ->
                    CircularProgressIndicator(Modifier.size(32.dp).testTag("public-media-loading"))
                else ->
                    Column(
                        Modifier.padding(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        UacSymbol(fallback, modifier = Modifier.size(28.dp))
                        Text(
                            tr(language, "Bild nicht verfügbar", "Зображення недоступне"),
                            Modifier.testTag("public-media-unavailable"),
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
            }
        }
    } else if (compact) {
        Box(modifier, contentAlignment = Alignment.Center) {
            if (bitmap != null)
                Image(
                    bitmap!!,
                    null,
                    Modifier.fillMaxSize().testTag("loaded-media"),
                    contentScale = ContentScale.Crop,
                )
            else UacSymbol(fallback, modifier = Modifier.size(28.dp))
        }
    } else
        when {
            url == "https://example.invalid/media/community.png" ->
                Image(
                    painterResource(R.drawable.ic_local_uac),
                    description,
                    modifier.fillMaxWidth().height(120.dp),
                    contentScale = ContentScale.Fit,
                )
            bitmap != null ->
                Image(
                    bitmap!!,
                    description,
                    modifier.fillMaxWidth().heightIn(max = 280.dp).testTag("loaded-media"),
                    contentScale = ContentScale.Fit,
                )
            loading ->
                Text(tr(language, "Bild wird geladen…", "Завантаження зображення…"), modifier)
            url.isNotEmpty() ->
                Text(
                    tr(
                        language,
                        "Bild nicht verfügbar (lokale Testversion). ",
                        "Зображення недоступне (локальна версія). ",
                    ) + description,
                    modifier,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
        }
}

/** Uses the same verified dimension/byte policy; only new thumbnails receive more downsampling. */
internal fun decodePublicImage(bytes: ByteArray, presentation: PublicImagePresentation): Bitmap? {
    require(bytes.size <= PublicMediaPolicy.MAX_BYTES)
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    options.inSampleSize =
        PublicImageSizing.sampleSize(options.outWidth, options.outHeight, presentation)
    options.inJustDecodeBounds = false
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.also { bitmap ->
        if (
            presentation == PublicImagePresentation.VIEWPORT_CROP &&
                maxOf(bitmap.width, bitmap.height) > PublicImageSizing.THUMBNAIL_EDGE
        ) {
            bitmap.recycle()
            error("Decoded public thumbnail exceeds viewport budget")
        }
    }
}
