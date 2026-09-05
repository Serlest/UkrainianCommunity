# iPhone build 65 brand originals

These files are byte-identical copies from the current iOS source bundle, not regenerated artwork.
Source images/videos and Desktop alternatives remain untouched. Android `drawable-nodpi` prevents density-based resampling.

| Android resource | iOS original | SHA-256 |
| --- | --- | --- |
| `uac_logo_lockup.png` | `logo1.imageset/logo1.png` | `e74369b2501f8ff05fb219c99512dfdb7e41f29eef6fe9e3924c8d1d3ab2b4bb` |
| `uac_logo_mark.png` | `logo2.imageset/logo2.png` | `b10eabcdf57fe617e13b5fc5bcb27635a57a312aa9cfea8db4518e17691d5760` |
| `uac_app_icon.png` | `AppIcon.appiconset/ios-marketing.png` | `52b699dc3bc8fb5ae441989f5da336c17534df53f77c3f8ef0f49c72cdb2bfa5` |
| `uac_background.png` | `background.imageset/background.png` | `be0db8e8d345ade02a023d487d244d4342a81cc11909e443888add578e66638c` |
| `uac_start_animation.mp4` | `Resources/Videos/startAnimation.mp4` | `437cc48a24209a770404c61b5e29a9641815e6b584f03126b1a8c18c52a952d0` |

The horizontal logo is 2398×834; the square logo is 1024×1024; the original background is 853×1844.
The actual iOS app icon is a different 1024×1024 asset from logo2. Android's adaptive icon uses that original with a white background and a safe inset; inspect its launcher mask separately. The original video metadata reports 1896×4096 and 5.041992 seconds; startup must follow readiness, not force users to wait for the full clip.
Keep the original aspect ratio. The adaptive header may crop the symbol from the horizontal lockup exactly as iOS `AdaptiveBrandLockupView` does, with real scalable text alongside it. Android uses its native sans-serif font; it does not redistribute Apple's system fonts.

Import alone is not visual or playback proof. Verify the integrated header, theme, reduced-motion launch, light/dark appearance, large type, and real navigation separately.

## Compatibility-only video derivative

`raw/uac_start_animation_compat.mp4` is an explicitly lossy native AVFoundation derivative, not another byte-identical original. SHA-256: `cc03fde74aaa18bfbecbc9b73c5399b1b8ea467ad04d09e112bb06e2d13a7b31`. It is exactly quarter-sized (474×1024), H.264 Baseline 3.1, silent, without cropping; all 121 presentation timestamps and the exact duration match the original. Representative decoded frames were compared visually; mild softness/tonal differences remain.

Original preference is capability-based, not an Android-version cutoff. Codec discovery runs off-main, with a complete same-decoder profile/level/format/size/rate/bitrate check. Unsupported/discovery failure remains static; the chosen player's later failure does not start a resource-retry chain. Original assets remain untouched. This selection and derivative still require real Android frame/lifecycle verification; source integration alone is not proof.
