package at.uac.android.feature.appupdate

data class AndroidRelease(
    val packageName: String,
    val versionName: String,
    val minimumSdk: Int,
    val available: Boolean,
)

data class AndroidUpdate(val versionName: String, val storeUri: String)

class ReleaseVersion private constructor(private val parts: List<Int>) :
    Comparable<ReleaseVersion> {
  override fun compareTo(other: ReleaseVersion): Int {
    repeat(maxOf(parts.size, other.parts.size)) { index ->
      val difference = parts.getOrElse(index) { 0 }.compareTo(other.parts.getOrElse(index) { 0 })
      if (difference != 0) return difference
    }
    return 0
  }

  companion object {
    fun parse(value: String): ReleaseVersion? {
      val pieces = value.split('.')
      if (pieces.size !in 1..4 || pieces.any { it.isEmpty() || it.any { c -> !c.isDigit() } })
          return null
      val parsed = pieces.map { it.toIntOrNull() ?: return null }.toMutableList()
      while (parsed.size > 1 && parsed.last() == 0) parsed.removeAt(parsed.lastIndex)
      return ReleaseVersion(parsed)
    }
  }
}

object AndroidUpdatePolicy {
  fun available(
      installedVersion: String,
      deviceSdk: Int,
      expectedPackage: String,
      release: AndroidRelease?,
  ): AndroidUpdate? {
    if (
        release == null ||
            !release.available ||
            release.packageName != expectedPackage ||
            deviceSdk < release.minimumSdk
    )
        return null
    val installed = ReleaseVersion.parse(installedVersion) ?: return null
    val published = ReleaseVersion.parse(release.versionName) ?: return null
    if (published <= installed || !Regex("[a-zA-Z][a-zA-Z0-9_.]{2,199}").matches(expectedPackage))
        return null
    return AndroidUpdate(release.versionName, "market://details?id=$expectedPackage")
  }
}
