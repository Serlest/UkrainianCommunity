plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val productionKeystorePath =
    providers.environmentVariable("UAC_PRODUCTION_KEYSTORE").orElse(providers.gradleProperty("uac.production.keystore"))
val productionKeystorePassword =
    providers.environmentVariable("UAC_PRODUCTION_KEYSTORE_PASSWORD").orElse(providers.gradleProperty("uac.production.keystorePassword"))
val productionKeyAlias =
    providers.environmentVariable("UAC_PRODUCTION_KEY_ALIAS").orElse(providers.gradleProperty("uac.production.keyAlias"))
val productionKeyPassword =
    providers.environmentVariable("UAC_PRODUCTION_KEY_PASSWORD").orElse(providers.gradleProperty("uac.production.keyPassword"))

android {
    namespace = "at.uac.android"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
        targetSdk = 36
        // Product/build identity follows the current iOS TestFlight baseline.
        versionCode = 79
        versionName = "1.0.3"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["appLabel"] = "UAC"
    }
    flavorDimensions += "backend"
    productFlavors {
        create("local") {
            dimension = "backend"
            applicationId = "at.uac.android.local"
            versionNameSuffix = "-local"
            manifestPlaceholders["appLabel"] = "UAC Local"
            manifestPlaceholders["enableCloudMessaging"] = "false"
            buildConfigField("boolean", "USE_LOCAL_BACKEND", "true")
            buildConfigField("boolean", "USE_DEBUG_APP_CHECK", "false")
            buildConfigField("String", "BACKEND_APP_NAME", "\"uac-local\"")
            buildConfigField("String", "BACKEND_PROJECT_ID", "\"demo-uac-android\"")
            buildConfigField(
                "String",
                "BACKEND_APPLICATION_ID",
                "\"1:1234567890:android:0000000000000000000000\"",
            )
            buildConfigField(
                "String",
                "BACKEND_API_KEY",
                "\"synthetic-local-key-not-a-credential\"",
            )
            buildConfigField("String", "BACKEND_BUCKET", "\"demo-uac-android.appspot.com\"")
        }
        create("staging") {
            dimension = "backend"
            applicationId = "at.serlest.ukrainiancommunity.staging"
            versionNameSuffix = "-staging"
            manifestPlaceholders["appLabel"] = "UAC Staging"
            manifestPlaceholders["enableCloudMessaging"] = "true"
            buildConfigField("boolean", "USE_LOCAL_BACKEND", "false")
            buildConfigField("boolean", "USE_DEBUG_APP_CHECK", "true")
            buildConfigField("String", "BACKEND_APP_NAME", "\"[DEFAULT]\"")
            buildConfigField(
                "String",
                "BACKEND_PROJECT_ID",
                "\"${providers.environmentVariable("UAC_STAGING_FIREBASE_PROJECT_ID").orElse(providers.gradleProperty("uac.staging.firebase.projectId")).orElse("uac-android-test-20260903").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_APPLICATION_ID",
                "\"${providers.environmentVariable("UAC_STAGING_FIREBASE_APPLICATION_ID").orElse(providers.gradleProperty("uac.staging.firebase.applicationId")).orElse("").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_API_KEY",
                "\"${providers.environmentVariable("UAC_STAGING_FIREBASE_API_KEY").orElse(providers.gradleProperty("uac.staging.firebase.apiKey")).orElse("").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_BUCKET",
                "\"${providers.environmentVariable("UAC_STAGING_FIREBASE_BUCKET").orElse(providers.gradleProperty("uac.staging.firebase.bucket")).orElse("uac-android-test-20260903.firebasestorage.app").get()}\"",
            )
            resValue("string", "google_app_id", providers.environmentVariable("UAC_STAGING_FIREBASE_APPLICATION_ID").orElse(providers.gradleProperty("uac.staging.firebase.applicationId")).orElse("").get())
            resValue("string", "google_api_key", providers.environmentVariable("UAC_STAGING_FIREBASE_API_KEY").orElse(providers.gradleProperty("uac.staging.firebase.apiKey")).orElse("").get())
            resValue("string", "project_id", providers.environmentVariable("UAC_STAGING_FIREBASE_PROJECT_ID").orElse(providers.gradleProperty("uac.staging.firebase.projectId")).orElse("uac-android-test-20260903").get())
            resValue("string", "google_storage_bucket", providers.environmentVariable("UAC_STAGING_FIREBASE_BUCKET").orElse(providers.gradleProperty("uac.staging.firebase.bucket")).orElse("uac-android-test-20260903.firebasestorage.app").get())
            resValue("string", "gcm_defaultSenderId", "966536981122")
        }
        create("production") {
            dimension = "backend"
            applicationId = "at.serlest.ukrainiancommunity"
            manifestPlaceholders["appLabel"] = "UAC"
            manifestPlaceholders["enableCloudMessaging"] = "true"
            buildConfigField("boolean", "USE_LOCAL_BACKEND", "false")
            buildConfigField("boolean", "USE_DEBUG_APP_CHECK", "false")
            buildConfigField("String", "BACKEND_APP_NAME", "\"[DEFAULT]\"")
            buildConfigField(
                "String",
                "BACKEND_PROJECT_ID",
                "\"${providers.environmentVariable("UAC_PRODUCTION_FIREBASE_PROJECT_ID").orElse(providers.gradleProperty("uac.production.firebase.projectId")).orElse("").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_APPLICATION_ID",
                "\"${providers.environmentVariable("UAC_PRODUCTION_FIREBASE_APPLICATION_ID").orElse(providers.gradleProperty("uac.production.firebase.applicationId")).orElse("").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_API_KEY",
                "\"${providers.environmentVariable("UAC_PRODUCTION_FIREBASE_API_KEY").orElse(providers.gradleProperty("uac.production.firebase.apiKey")).orElse("").get()}\"",
            )
            buildConfigField(
                "String",
                "BACKEND_BUCKET",
                "\"${providers.environmentVariable("UAC_PRODUCTION_FIREBASE_BUCKET").orElse(providers.gradleProperty("uac.production.firebase.bucket")).orElse("").get()}\"",
            )
            resValue("string", "google_app_id", providers.environmentVariable("UAC_PRODUCTION_FIREBASE_APPLICATION_ID").orElse(providers.gradleProperty("uac.production.firebase.applicationId")).orElse("").get())
            resValue("string", "google_api_key", providers.environmentVariable("UAC_PRODUCTION_FIREBASE_API_KEY").orElse(providers.gradleProperty("uac.production.firebase.apiKey")).orElse("").get())
            resValue("string", "project_id", providers.environmentVariable("UAC_PRODUCTION_FIREBASE_PROJECT_ID").orElse(providers.gradleProperty("uac.production.firebase.projectId")).orElse("").get())
            resValue("string", "google_storage_bucket", providers.environmentVariable("UAC_PRODUCTION_FIREBASE_BUCKET").orElse(providers.gradleProperty("uac.production.firebase.bucket")).orElse("").get())
            resValue("string", "gcm_defaultSenderId", "919042658790")
        }
    }
    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (
                productionKeystorePath.isPresent &&
                    productionKeystorePassword.isPresent &&
                    productionKeyAlias.isPresent &&
                    productionKeyPassword.isPresent
            ) {
                signingConfig = signingConfigs.create("production") {
                    storeFile = file(productionKeystorePath.get())
                    storePassword = productionKeystorePassword.get()
                    keyAlias = productionKeyAlias.get()
                    keyPassword = productionKeyPassword.get()
                }
            }
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
        resValues = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

androidComponents {
    beforeVariants(selector().all()) { variant ->
        val backend = variant.productFlavors.firstOrNull { it.first == "backend" }?.second
        variant.enable =
            (backend == "local" && variant.buildType == "debug") ||
                (backend == "staging" && variant.buildType == "debug") ||
                (backend == "production" && variant.buildType == "release")
    }
}

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

val verifyProductionReleaseConfiguration by tasks.registering {
    doLast {
        val required =
            mapOf(
                "UAC_PRODUCTION_FIREBASE_PROJECT_ID" to providers.environmentVariable("UAC_PRODUCTION_FIREBASE_PROJECT_ID").orElse(providers.gradleProperty("uac.production.firebase.projectId")).orNull,
                "UAC_PRODUCTION_FIREBASE_APPLICATION_ID" to providers.environmentVariable("UAC_PRODUCTION_FIREBASE_APPLICATION_ID").orElse(providers.gradleProperty("uac.production.firebase.applicationId")).orNull,
                "UAC_PRODUCTION_FIREBASE_API_KEY" to providers.environmentVariable("UAC_PRODUCTION_FIREBASE_API_KEY").orElse(providers.gradleProperty("uac.production.firebase.apiKey")).orNull,
                "UAC_PRODUCTION_FIREBASE_BUCKET" to providers.environmentVariable("UAC_PRODUCTION_FIREBASE_BUCKET").orElse(providers.gradleProperty("uac.production.firebase.bucket")).orNull,
                "UAC_PRODUCTION_KEYSTORE" to productionKeystorePath.orNull,
                "UAC_PRODUCTION_KEYSTORE_PASSWORD" to productionKeystorePassword.orNull,
                "UAC_PRODUCTION_KEY_ALIAS" to productionKeyAlias.orNull,
                "UAC_PRODUCTION_KEY_PASSWORD" to productionKeyPassword.orNull,
            )
        val missing = required.filterValues { it.isNullOrBlank() }.keys
        check(missing.isEmpty()) { "Production release configuration missing: ${missing.joinToString()}" }
        check(file(productionKeystorePath.get()).isFile) { "Production keystore file is missing" }
    }
}

tasks.named("preBuild") { dependsOn(verifyLocalOnly) }
tasks.matching { it.name == "preProductionReleaseBuild" }.configureEach {
    dependsOn(verifyProductionReleaseConfiguration)
}

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
    implementation("com.google.firebase:firebase-functions")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-appcheck")
    implementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
    "stagingImplementation"("com.google.firebase:firebase-appcheck-debug-testing:19.4.1")
    // The CI helper still declares AndroidX Test 1.5/1.6. Keep the staging app-side
    // registrar binary-compatible with the current runner/Espresso shipped in the test APK.
    "stagingImplementation"("androidx.test:core:1.7.0")
    "stagingImplementation"("androidx.test:monitor:1.8.0")
    "stagingImplementation"("androidx.test.services:storage:1.6.0")
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
