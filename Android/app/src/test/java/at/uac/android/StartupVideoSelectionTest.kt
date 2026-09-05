package at.uac.android

import android.media.MediaCodecInfo.CodecProfileLevel
import at.uac.android.feature.startup.*
import org.junit.Assert.*
import org.junit.Test

class StartupVideoSelectionTest {
    private val original = StartupVideoAsset.ORIGINAL
    private val compat = StartupVideoAsset.COMPATIBILITY

    private fun supported(asset: StartupVideoAsset) =
        StartupCodecCheck(
            true,
            true,
            false,
            false,
            listOf(StartupCodecProfile(asset.profile, asset.level)),
            true,
            true,
            true,
        )

    @Test
    fun originalWinsWithoutEvenProbingTheDerivative() {
        val probed = mutableListOf<StartupVideoAsset>()
        assertEquals(
            original,
            selectStartupVideo {
                probed += it
                listOf(supported(it))
            },
        )
        assertEquals(listOf(original), probed)
    }

    @Test
    fun unsupportedPortraitChoosesOnlyCompatibleAsset() {
        assertEquals(
            compat,
            selectStartupVideo {
                listOf(supported(it).copy(sizeAndRateSupported = it == compat))
            },
        )
    }

    @Test
    fun noDecoderOrGlobalDiscoveryFailureUsesStatic() {
        assertNull(selectStartupVideo { emptyList() })
        assertNull(
            selectStartupVideo { throw IllegalStateException("synthetic discovery failure") }
        )
        assertNull(selectStartupVideo { listOf(supported(it).copy(formatSupported = false)) })
    }

    @Test
    fun metadataUsesAndroidConstantsNotAvcWireBytes() {
        assertEquals(CodecProfileLevel.AVCProfileMain, original.profile)
        assertEquals(CodecProfileLevel.AVCLevel51, original.level)
        assertEquals(CodecProfileLevel.AVCProfileBaseline, compat.profile)
        assertEquals(CodecProfileLevel.AVCLevel31, compat.level)
        assertEquals(original.width, compat.width * 4)
        assertEquals(original.height, compat.height * 4)
        assertEquals(original.framesPerSecond, compat.framesPerSecond, 0.0)
    }

    @Test
    fun profilesAndRecognizedLevelsMustMatchOneCompleteDecoder() {
        assertTrue(supported(original).supports(original))
        assertTrue(
            supported(original)
                .copy(
                    profiles =
                        listOf(StartupCodecProfile(original.profile, CodecProfileLevel.AVCLevel52))
                )
                .supports(original)
        )
        assertFalse(
            supported(original)
                .copy(
                    profiles =
                        listOf(StartupCodecProfile(original.profile, CodecProfileLevel.AVCLevel5))
                )
                .supports(original)
        )
        assertFalse(
            supported(original)
                .copy(
                    profiles =
                        listOf(
                            StartupCodecProfile(CodecProfileLevel.AVCProfileHigh, original.level)
                        )
                )
                .supports(original)
        )
        assertFalse(
            supported(original)
                .copy(profiles = listOf(StartupCodecProfile(original.profile, Int.MAX_VALUE)))
                .supports(original)
        )
        assertNull(
            selectStartupVideo { asset ->
                listOf(
                    supported(asset).copy(sizeAndRateSupported = false),
                    supported(asset).copy(profiles = emptyList()),
                )
            }
        )
    }

    @Test
    fun everyRequiredCapabilityIndependentlyRejectsTheDecoder() {
        val valid = supported(compat)
        listOf(
                valid.copy(decoder = false),
                valid.copy(avc = false),
                valid.copy(secureOnly = true),
                valid.copy(tunneledOnly = true),
                valid.copy(formatSupported = false),
                valid.copy(sizeAndRateSupported = false),
                valid.copy(bitrateSupported = false),
            )
            .forEach { assertFalse(it.supports(compat)) }
    }

    @Test
    fun compatibilityAssetKeepsExactlyTheOriginalAspectFit() {
        listOf(1080 to 1920, 1920 to 1080, 640 to 480).forEach { (width, height) ->
            assertEquals(
                startupAspectFit(width, height, original.width, original.height),
                startupAspectFit(width, height, compat.width, compat.height),
            )
        }
    }
}
