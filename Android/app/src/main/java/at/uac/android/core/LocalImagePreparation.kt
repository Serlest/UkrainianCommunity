package at.uac.android.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

enum class LocalImagePolicy(
    val dimension: Int,
    val maximumBytes: Int,
    val square: Boolean,
    val cropAspect: Pair<Int, Int>? = null,
) {
    AVATAR(1024, 1_500_000, true),
    ORG_LOGO(1600, 3_000_000, false),
    CONTENT_COVER_16_9(1600, 3_000_000, false, 16 to 9),
    GALLERY_PHOTO(1600, 3_000_000, false),
}

enum class LocalImageFailure {
    INVALID,
    TOO_LARGE,
    UNSUPPORTED,
    UNREADABLE,
}

class LocalImageException(val reason: LocalImageFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

/**
 * No file permission, original URI persistence, original EXIF, or full-resolution decode is needed.
 */
object LocalImagePreparation {
    const val MAX_INPUT_BYTES = 20_000_000
    const val MAX_SOURCE_PIXELS = 100_000_000L
    private const val MAX_SOURCE_DIMENSION = 32_768

    suspend fun prepare(context: Context, uri: Uri, policy: LocalImagePolicy): ByteArray =
        withContext(Dispatchers.IO) {
            if (uri.scheme != "content") throw LocalImageException(LocalImageFailure.INVALID)
            val data =
                try {
                    context.contentResolver.openInputStream(uri)?.use { readBounded(it) }
                        ?: throw LocalImageException(LocalImageFailure.UNREADABLE)
                } catch (error: SecurityException) {
                    throw LocalImageException(LocalImageFailure.UNREADABLE, error)
                } catch (error: java.io.IOException) {
                    throw LocalImageException(LocalImageFailure.UNREADABLE, error)
                }
            prepareBytes(data, policy)
        }

    suspend fun readBounded(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            currentCoroutineContext().ensureActive()
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            if (output.size() > MAX_INPUT_BYTES - count)
                throw LocalImageException(LocalImageFailure.TOO_LARGE)
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    /**
     * Kept separate so byte limits and actual raster/EXIF processing can be tested without a
     * picker.
     */
    suspend fun prepareBytes(data: ByteArray, policy: LocalImagePolicy): ByteArray =
        withContext(Dispatchers.Default) {
            validateContainer(data)
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, options)
            if (!validDimensions(options.outWidth, options.outHeight))
                throw LocalImageException(LocalImageFailure.TOO_LARGE)
            val decodeLimit =
                when {
                    policy.square -> 2048
                    policy.cropAspect != null -> policy.dimension * 2
                    else -> policy.dimension
                }
            options.inSampleSize = sampleSize(options.outWidth, options.outHeight, decodeLimit)
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.ARGB_8888
            options.inScaled = false
            currentCoroutineContext().ensureActive()
            val decoded =
                BitmapFactory.decodeByteArray(data, 0, data.size, options)
                    ?: throw LocalImageException(LocalImageFailure.INVALID)
            try {
                val orientation =
                    try {
                        data.inputStream().use {
                            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
                        }
                    } catch (_: java.io.IOException) {
                        1
                    }
                val matrix =
                    Matrix().apply {
                        when (orientation) {
                            2 -> setScale(-1f, 1f)
                            3 -> setRotate(180f)
                            4 -> setScale(1f, -1f)
                            5 -> {
                                setRotate(90f)
                                postScale(-1f, 1f)
                            }
                            6 -> setRotate(90f)
                            7 -> {
                                setRotate(270f)
                                postScale(-1f, 1f)
                            }
                            8 -> setRotate(270f)
                        }
                    }
                val oriented =
                    Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                try {
                    currentCoroutineContext().ensureActive()
                    val size = outputSize(oriented.width, oriented.height, policy)
                    val opaque =
                        Bitmap.createBitmap(size.first, size.second, Bitmap.Config.ARGB_8888)
                    try {
                        val scale =
                            if (policy.square || policy.cropAspect != null)
                                maxOf(
                                    size.first.toFloat() / oriented.width,
                                    size.second.toFloat() / oriented.height,
                                )
                            else
                                minOf(
                                    size.first.toFloat() / oriented.width,
                                    size.second.toFloat() / oriented.height,
                                )
                        val left = (size.first - oriented.width * scale) / 2f
                        val top = (size.second - oriented.height * scale) / 2f
                        Canvas(opaque).apply {
                            drawColor(Color.WHITE)
                            drawBitmap(
                                oriented,
                                null,
                                RectF(
                                    left,
                                    top,
                                    left + oriented.width * scale,
                                    top + oriented.height * scale,
                                ),
                                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
                            )
                        }
                        for (quality in listOf(82, 75, 68, 61, 54, 47, 40, 35)) {
                            currentCoroutineContext().ensureActive()
                            val bytes =
                                ByteArrayOutputStream().use { output ->
                                    if (
                                        !opaque.compress(
                                            Bitmap.CompressFormat.JPEG,
                                            quality,
                                            output,
                                        )
                                    )
                                        throw LocalImageException(LocalImageFailure.INVALID)
                                    output.toByteArray()
                                }
                            if (validJpeg(bytes, policy)) return@withContext bytes
                        }
                        throw LocalImageException(LocalImageFailure.TOO_LARGE)
                    } finally {
                        opaque.recycle()
                    }
                } finally {
                    if (oriented !== decoded) oriented.recycle()
                }
            } finally {
                decoded.recycle()
            }
        }

    fun validDimensions(width: Int, height: Int): Boolean =
        width in 1..MAX_SOURCE_DIMENSION &&
            height in 1..MAX_SOURCE_DIMENSION &&
            width.toLong() * height <= MAX_SOURCE_PIXELS

    fun sampleSize(width: Int, height: Int, limit: Int): Int {
        require(validDimensions(width, height) && limit > 0)
        var sample = 1
        while ((maxOf(width, height) + sample - 1) / sample > limit) sample *= 2
        return sample
    }

    fun outputSize(width: Int, height: Int, policy: LocalImagePolicy): Pair<Int, Int> {
        require(width > 0 && height > 0)
        if (policy.square) return minOf(width, height, policy.dimension).let { it to it }
        policy.cropAspect?.let { (horizontal, vertical) ->
            // Exact integer aspect, no distortion or forced upscale. The UI previews this central
            // crop before upload.
            val units = minOf(width / horizontal, height / vertical, policy.dimension / horizontal)
            if (units < 1) throw LocalImageException(LocalImageFailure.INVALID)
            return units * horizontal to units * vertical
        }
        val scale = minOf(1.0, policy.dimension.toDouble() / maxOf(width, height))
        return maxOf(1, (width * scale).toInt()) to maxOf(1, (height * scale).toInt())
    }

    fun validJpeg(bytes: ByteArray, policy: LocalImagePolicy): Boolean =
        bytes.size in 4 until policy.maximumBytes &&
            bytes[0] == 0xff.toByte() &&
            bytes[1] == 0xd8.toByte() &&
            bytes[bytes.size - 2] == 0xff.toByte() &&
            bytes.last() == 0xd9.toByte()

    /**
     * Parse container chunks rather than trusting filename/MIME or searching compressed pixel
     * bytes.
     */
    fun validateContainer(data: ByteArray) {
        if (data.isEmpty()) throw LocalImageException(LocalImageFailure.INVALID)
        if (data.size > MAX_INPUT_BYTES) throw LocalImageException(LocalImageFailure.TOO_LARGE)
        fun starts(offset: Int, text: String) =
            offset >= 0 &&
                offset + text.length <= data.size &&
                text.indices.all { data[offset + it].toInt() and 0xff == text[it].code }
        fun u32(offset: Int, little: Boolean): Long {
            if (offset < 0 || offset + 4 > data.size)
                throw LocalImageException(LocalImageFailure.INVALID)
            var result = 0L
            for (index in 0..3) result =
                result or
                    ((data[offset + index].toLong() and 255) shl
                        (if (little) index * 8 else (3 - index) * 8))
            return result
        }
        if (data.size >= 4 && data[0] == 0xff.toByte() && data[1] == 0xd8.toByte()) {
            if (data[data.size - 2] != 0xff.toByte() || data.last() != 0xd9.toByte())
                throw LocalImageException(LocalImageFailure.INVALID)
            return
        }
        if (
            data.size >= 8 &&
                data.take(8) == listOf(137, 80, 78, 71, 13, 10, 26, 10).map(Int::toByte)
        ) {
            var offset = 8
            while (offset + 12 <= data.size) {
                val length = u32(offset, false)
                if (length > data.size.toLong() - offset - 12)
                    throw LocalImageException(LocalImageFailure.INVALID)
                if (starts(offset + 4, "acTL"))
                    throw LocalImageException(LocalImageFailure.UNSUPPORTED)
                if (starts(offset + 4, "IEND")) return
                offset += length.toInt() + 12
            }
            throw LocalImageException(LocalImageFailure.INVALID)
        }
        if (starts(0, "RIFF") && starts(8, "WEBP")) {
            val end = u32(4, true) + 8
            if (end != data.size.toLong()) throw LocalImageException(LocalImageFailure.INVALID)
            var offset = 12
            while (offset + 8 <= data.size) {
                val length = u32(offset + 4, true)
                if (length > data.size.toLong() - offset - 8)
                    throw LocalImageException(LocalImageFailure.INVALID)
                if (
                    starts(offset, "ANIM") ||
                        starts(offset, "ANMF") ||
                        starts(offset, "VP8X") && length > 0 && data[offset + 8].toInt() and 2 != 0
                )
                    throw LocalImageException(LocalImageFailure.UNSUPPORTED)
                offset += 8 + length.toInt() + (length.toInt() and 1)
            }
            if (offset != data.size) throw LocalImageException(LocalImageFailure.INVALID)
            return
        }
        throw LocalImageException(LocalImageFailure.UNSUPPORTED)
    }
}
