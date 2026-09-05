import groovy.json.JsonSlurper
import java.io.File
import org.gradle.api.artifacts.ProjectDependency

plugins { id("com.android.application") }

// An external, read-only SDK config is optional for compilation. Never copy it
// into :app, source resources, outputs, or a google-services plugin input.
val sdkConfigPath = providers.gradleProperty("uacPushProbeSdkConfig").orNull
var verifiedApiKey = ""

if (!sdkConfigPath.isNullOrBlank()) {
    check(File(sdkConfigPath).isAbsolute) { "An absolute test SDK config path is required" }
    val source = file(sdkConfigPath)
    check(source.isFile) { "An existing test SDK config file is required" }
    val json = JsonSlurper().parse(source) as Map<*, *>
    val project = json["project_info"] as? Map<*, *>
    check(
        project != null &&
            project["project_id"] == "uac-android-test-20260903" &&
            project["project_number"] == "966536981122"
    ) {
        "Push probe only accepts the approved test project"
    }
    val clients = (json["client"] as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
    val client =
        clients.singleOrNull {
            val info = it["client_info"] as? Map<*, *>
            val android = info?.get("android_client_info") as? Map<*, *>
            info != null &&
                android?.get("package_name") == "at.serlest.ukrainiancommunity.staging" &&
                info["mobilesdk_app_id"] == "1:966536981122:android:2b617eb5d71f37b8dbe29b"
        } ?: error("Push probe SDK app/package mismatch")
    val keys =
        (client["api_key"] as? List<*>)
            ?.mapNotNull { (it as? Map<*, *>)?.get("current_key") as? String }
            .orEmpty()
    verifiedApiKey =
        keys.singleOrNull()?.takeIf { it.matches(Regex("AIza[A-Za-z0-9_-]{35}")) }
            ?: error("Push probe requires one valid test SDK API key")
}

android {
    namespace = "at.uac.pushprobe"
    compileSdk = 36
    defaultConfig {
        applicationId = "at.serlest.ukrainiancommunity.staging"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1-test-probe"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "TEST_API_KEY", "\"$verifiedApiKey\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }

kotlin { jvmToolchain(17) }

val verifyProbeIsolation by tasks.registering {
    doLast {
        val forbidden =
            setOf(
                "firebase-auth",
                "firebase-firestore",
                "firebase-functions",
                "firebase-storage",
                "firebase-analytics",
                "firebase-crashlytics",
                "firebase-perf",
                "firebase-config",
            )
        val runtime = configurations.getByName("debugRuntimeClasspath")
        check(runtime.allDependencies.none { it is ProjectDependency }) {
            "Push probe cannot depend on the UAC app or another project"
        }
        check(
            runtime.resolvedConfiguration.resolvedArtifacts.none {
                it.moduleVersion.id.group == "com.google.firebase" &&
                    it.name.removeSuffix("-ktx") in forbidden
            }
        ) {
            "Push probe contains a forbidden application/private-data SDK"
        }
    }
}

tasks.named("preBuild") { dependsOn(verifyProbeIsolation) }

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    implementation(platform("com.google.firebase:firebase-bom:34.18.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-installations")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
