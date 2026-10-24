package com.izmirimexpress.kurye

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // In-app updates (lib/services/app_update_service.dart): Dart
        // downloads the new APK into updatesDir, then hands it to the
        // system installer here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "izmirim/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "updatesDir" -> {
                    val dir = File(cacheDir, "updates").apply { mkdirs() }
                    result.success(dir.absolutePath)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("no_path", null, null)
                        return@setMethodCallHandler
                    }
                    // Android 8+: the rider has to allow this app to install
                    // apps once; send them to that switch first.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success("needs_permission")
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success("started")
                }
                else -> result.notImplemented()
            }
        }
    }
}
