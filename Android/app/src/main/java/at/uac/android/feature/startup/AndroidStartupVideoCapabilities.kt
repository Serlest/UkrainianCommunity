package at.uac.android.feature.startup

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat

/** Call off-main. Only codec metadata is inspected; no codec, Surface or player is created here. */
internal fun supportedStartupVideo(): StartupVideoAsset? =
    try {
        val decoders =
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter {
                !it.isEncoder && it.supportedTypes.any { type -> type.equals("video/avc", true) }
            }
        selectStartupVideo { asset ->
            decoders.mapNotNull { decoder ->
                try {
                    val capabilities = decoder.getCapabilitiesForType("video/avc")
                    val video = capabilities.videoCapabilities ?: return@mapNotNull null
                    val format =
                        MediaFormat.createVideoFormat("video/avc", asset.width, asset.height)
                            .apply {
                                setInteger(MediaFormat.KEY_PROFILE, asset.profile)
                                setInteger(MediaFormat.KEY_LEVEL, asset.level)
                                setInteger(MediaFormat.KEY_BIT_RATE, asset.bitrate)
                                setFloat(
                                    MediaFormat.KEY_FRAME_RATE,
                                    asset.framesPerSecond.toFloat(),
                                )
                            }
                    StartupCodecCheck(
                        decoder = true,
                        avc = true,
                        secureOnly =
                            capabilities.isFeatureRequired(
                                MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback
                            ),
                        tunneledOnly =
                            capabilities.isFeatureRequired(
                                MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback
                            ),
                        profiles =
                            capabilities.profileLevels.map {
                                StartupCodecProfile(it.profile, it.level)
                            },
                        formatSupported = capabilities.isFormatSupported(format),
                        sizeAndRateSupported =
                            video.areSizeAndRateSupported(
                                asset.width,
                                asset.height,
                                asset.framesPerSecond,
                            ),
                        bitrateSupported = video.bitrateRange.contains(asset.bitrate),
                    )
                } catch (_: Exception) {
                    // A broken vendor entry cannot make unrelated capabilities appear supported.
                    null
                }
            }
        }
    } catch (_: Exception) {
        null
    }
