package at.uac.android

import at.uac.android.core.LocalStorage
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalStorageUrlTest {
    @Test fun acceptsOnlyTheCompiledBucketAndExactAvatarObject() {
        val path = "profileImages/member/avatar.jpg"
        val encoded = "profileImages%2Fmember%2Favatar.jpg"
        val bucket = LocalStorage.BUCKET
        val token = "A".repeat(32)
        val cloud = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media&token=$token"
        val local = "http://10.0.2.2:9198/v0/b/$bucket/o/$encoded"
        val accepted = if (BuildConfig.USE_LOCAL_BACKEND) local else cloud
        val rejected = if (BuildConfig.USE_LOCAL_BACKEND) cloud else local
        assertTrue(LocalStorage.urlMatches(accepted, path))
        assertFalse(LocalStorage.urlMatches(rejected, path))
        assertFalse(LocalStorage.urlMatches(accepted.replace(bucket, "foreign-bucket"), path))
        assertFalse(LocalStorage.urlMatches(accepted, "profileImages/other/avatar.jpg"))
        assertFalse(LocalStorage.urlMatches(accepted.replace(encoded, "profileImages%252Fmember%252Favatar.jpg"), path))
        if (!BuildConfig.USE_LOCAL_BACKEND) {
            assertFalse(LocalStorage.urlMatches(cloud.replace("?alt=media&token=$token", ""), path))
            assertFalse(LocalStorage.urlMatches(cloud.replace("https://", "http://"), path))
            assertFalse(LocalStorage.urlMatches(cloud.replace(".com/", ".com:443/"), path))
            assertFalse(LocalStorage.urlMatches("$cloud#fragment", path))
        }
    }
}
