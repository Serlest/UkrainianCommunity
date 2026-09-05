plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "at.uac.android"
    compileSdk = 36
    defaultConfig {
        // Deliberately not the future Play/Firebase production identity.
        applicationId = "at.uac.android.local"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1-local"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// No release variant exists until the separately approved release package.
androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }

kotlin { jvmToolchain(17) }

val verifyLocalOnly by tasks.registering {
    doLast {
        check(
            fileTree(projectDir) {
                    include("**/google-services.json")
                    exclude("build/**")
                }
                .isEmpty
        ) {
            "Firebase cloud configuration is forbidden in the local-only package."
        }
    }
}

tasks.named("preBuild") { dependsOn(verifyLocalOnly) }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.03.01"))
    implementation("androidx.core:core-ktx:1.18.0")
    // API 26's platform EXIF reader rejects valid tiny JPEGs during its 5000-byte sniff.
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    implementation("androidx.activity:activity-compose:1.13.0")
    // Biometric 1.1 brings Fragment 1.2.5, whose legacy request-code check rejects Activity Result
    // launchers.
    implementation("androidx.fragment:fragment:1.9.0")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    implementation(platform("com.google.firebase:firebase-bom:34.18.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-storage")
    // Local callable protocol only: Functions SDK requires IID/FIS even with useEmulator.
    // Keep the synthetic key invalid; do not initialize identifiers or cloud SDK fallbacks.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.03.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    // 3.7 uses the public input service; older transitive Espresso fails on API 37.
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
