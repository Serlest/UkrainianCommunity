package at.uac.android.feature.startup

/** Fixed, reviewed bundled media only. Profile/level values here are Android AVC constants. */
internal enum class StartupVideoAsset(
    val width: Int,
    val height: Int,
    val bitrate: Int,
    val profile: Int,
    val level: Int,
) {
    ORIGINAL(1896, 4096, 2_376_794, 0x02, 0x8000),
    COMPATIBILITY(474, 1024, 1_098_432, 0x01, 0x200);

    val framesPerSecond: Double
        get() = 24.0
}

internal data class StartupCodecProfile(val profile: Int, val level: Int)

/** A complete check for one candidate on one decoder; never merge different decoders' limits. */
internal data class StartupCodecCheck(
    val decoder: Boolean,
    val avc: Boolean,
    val secureOnly: Boolean,
    val tunneledOnly: Boolean,
    val profiles: List<StartupCodecProfile>,
    val formatSupported: Boolean,
    val sizeAndRateSupported: Boolean,
    val bitrateSupported: Boolean,
) {
    fun supports(asset: StartupVideoAsset): Boolean =
        decoder &&
            avc &&
            !secureOnly &&
            !tunneledOnly &&
            formatSupported &&
            sizeAndRateSupported &&
            bitrateSupported &&
            profiles.any {
                it.profile == asset.profile && avcLevelAtLeast(it.level, asset.level)
            }
}

private fun avcLevelAtLeast(actual: Int, required: Int): Boolean {
    // Recognized Android AVC levels 1, 1b, 1.1 ... 6.2. Unknown bit patterns are not support.
    val levels =
        listOf(
            0x01,
            0x02,
            0x04,
            0x08,
            0x10,
            0x20,
            0x40,
            0x80,
            0x100,
            0x200,
            0x400,
            0x800,
            0x1000,
            0x2000,
            0x4000,
            0x8000,
            0x10000,
            0x20000,
            0x40000,
            0x80000,
        )
    val actualRank = levels.indexOf(actual)
    val requiredRank = levels.indexOf(required)
    return requiredRank >= 0 && actualRank >= requiredRank
}

/** Null means the unchanged static brand background, including global discovery failure. */
internal fun selectStartupVideo(
    checks: (StartupVideoAsset) -> List<StartupCodecCheck>
): StartupVideoAsset? =
    try {
        StartupVideoAsset.entries.firstOrNull { asset -> checks(asset).any { it.supports(asset) } }
    } catch (_: Exception) {
        null
    }
