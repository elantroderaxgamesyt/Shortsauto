import java.util.Properties

// Firma de la versión para Play Store: android/key.properties (no se sube a git).
// En GitHub Actions se crea a partir de los secretos del repositorio.
val propsFirma = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "es.revisornominas.revisor_nominas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Id en Google Play: no se puede cambiar después de publicar.
        applicationId = "es.revisornominas.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob exige minSdk 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        // Id de la app en AdMob. Por defecto el de PRUEBA de Google; el real se pasa con la
        // variable de entorno ADMOB_APP_ID al compilar (en GitHub Actions, variable del repositorio).
        manifestPlaceholders["admobAppId"] =
            System.getenv("ADMOB_APP_ID")?.takeIf { it.isNotBlank() } ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (propsFirma.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(propsFirma.getProperty("storeFile"))
                storePassword = propsFirma.getProperty("storePassword")
                keyAlias = propsFirma.getProperty("keyAlias")
                keyPassword = propsFirma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sin key.properties se firma con la clave de depuración (vale para probar, no para Play Store).
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
