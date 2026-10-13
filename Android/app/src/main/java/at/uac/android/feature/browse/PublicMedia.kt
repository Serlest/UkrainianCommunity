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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import at.uac.android.BuildConfig
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
    adaptiveBackdrop: Boolean = false,
    fallback: UacIcon = UacIcon.NEWS,
    presentation: PublicImagePresentation = PublicImagePresentation.STANDARD,
    externalBanner: Boolean = false,
    showUnavailableText: Boolean = true,
    onLoadStateChanged: ((Boolean) -> Unit)? = null,
) {
    val bucketAddress = remember(url) { PublicMediaPolicy.address(url) }
    val address =
        remember(url, externalBanner) {
            bucketAddress
                ?: if (externalBanner && !BuildConfig.USE_LOCAL_BACKEND)
                    ExternalBannerMediaPolicy.address(url)
                else null
        }
    var bitmap by remember(address, presentation) { mutableStateOf<ImageBitmap?>(null) }
    var loading by remember(address, presentation) { mutableStateOf(address != null) }
    val loadCallback by rememberUpdatedState(onLoadStateChanged)
    LaunchedEffect(url, address, loading, bitmap) {
        loadCallback?.invoke(!loading &&
            (url.isBlank() || url == "https://example.invalid/media/community.png" || bitmap != null))
    }
    LaunchedEffect(address, presentation) {
        if (address != null)
            bitmap =
                withContext(Dispatchers.IO) {
                    PublicImageWork.load(presentation) {
                        val context = currentCoroutineContext()
                        if (bucketAddress == null) {
                            try {
                                val bytes =
                                    ExternalBannerMedia.bytes(address) { context.ensureActive() }
                                context.ensureActive()
                                return@load decodePublicImage(bytes, presentation)?.asImageBitmap()
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Exception) {
                                return@load null
                            }
                        }
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
            if (adaptiveBackdrop && bitmap != null) {
                Image(
                    bitmap!!,
                    null,
                    Modifier.fillMaxSize().blur(24.dp).alpha(.45f),
                    contentScale = ContentScale.Crop,
                )
            }
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
                        (if (!showUnavailableText && LocalDensity.current.fontScale > 1.3f)
                            Modifier.align(Alignment.TopCenter).padding(top = 20.dp)
                        else Modifier.offset(y = if (showUnavailableText) 0.dp else (-30).dp))
                            .padding(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        UacSymbol(fallback,
                            tr(language, "Bild nicht verfügbar", "Зображення недоступне"),
                            modifier = Modifier.size(28.dp).testTag("public-media-unavailable"))
                        if (showUnavailableText)
                            Text(
                                tr(language, "Bild nicht verfügbar", "Зображення недоступне"),
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
                        "Bild nicht verfügbar. ",
                        "Зображення недоступне. ",
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
