plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("dev.flutter.flutter-gradle-plugin")
    // O plugin do Google Services já está sendo aplicado via FlutterFire CLI
    // Não precisa declarar aqui de novo
}

android {
    namespace = "com.example.garcon"  // mude se o seu package for diferente
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"  // <- forma correta no .kts (sem JavaVersion.toString())
    }

    defaultConfig {
        applicationId = "com.example.garcon"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["appAuthQuotaEnabled"] = "false"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            firebaseCrashlytics {
            mappingFileUploadEnabled = true
            }
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
            manifestPlaceholders["appAuthQuotaEnabled"] = "false"
        }
        debug {
            manifestPlaceholders["appAuthQuotaEnabled"] = "false"
        }
    }
}

dependencies {
    // Firebase BoM (sempre use a versão mais recente)
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-storage")

    // Google Play Billing (versão estável e compatível com in_app_purchase 5+)
    implementation("com.android.billingclient:billing:6.2.1")
}

// O plugin do Google Services é aplicado automaticamente pelo FlutterFire
// Se você NÃO precisa (e nem deve) colocar "apply plugin" aqui quando usa .kts
// Ele já está no bloco plugins lá em cima graças ao FlutterFire CLI

flutter {
    source = "../.."
}