package com.aktifdesk.aktifdesk

import android.app.KeyguardManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val moonlightPackages = listOf("com.limelight", "com.limelight.root", "com.limelight.debug")
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aktifdesk/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moonlightPackage" -> result.success(findMoonlight())
                    "launchMoonlight" -> {
                        val pkg = findMoonlight()
                        if (pkg == null) {
                            result.success(false)
                        } else {
                            val i = Intent().apply {
                                component = ComponentName(pkg, "com.limelight.ShortcutTrampoline")
                                putExtra("UUID", call.argument<String>("uuid"))
                                call.argument<String>("pcName")?.let { putExtra("Name", it); putExtra("PcName", it) }
                                call.argument<String>("appId")?.let { putExtra("AppId", it) }
                                call.argument<String>("appName")?.let { putExtra("AppName", it) }
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            try {
                                startActivity(i)
                                result.success(true)
                            } catch (e: ActivityNotFoundException) {
                                result.success(false)
                            } catch (e: SecurityException) {
                                result.success(false)
                            }
                        }
                    }
                    "openMoonlight" -> {
                        val pkg = findMoonlight()
                        val i = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (i != null) startActivity(i)
                        result.success(i != null)
                    }
                    "openStore" -> {
                        val p = call.argument<String>("package") ?: "com.limelight"
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$p")))
                        } catch (e: ActivityNotFoundException) {
                            startActivity(Intent(Intent.ACTION_VIEW,
                                Uri.parse("https://play.google.com/store/apps/details?id=$p")))
                        }
                        result.success(true)
                    }
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                acquireWakeLock()
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                releaseWakeLock()
                            }
                        }
                        result.success(true)
                    }
                    "multicastLock" -> {
                        val on = call.argument<Boolean>("on") ?: true
                        try {
                            if (on) {
                                val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                                val lock = multicastLock ?: wifi.createMulticastLock("aktifdesk-discovery").also {
                                    it.setReferenceCounted(false)
                                    multicastLock = it
                                }
                                if (!lock.isHeld) lock.acquire()
                            } else {
                                multicastLock?.let { if (it.isHeld) it.release() }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "requestUnlock" -> {
                        result.success(requestUnlock())
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("package")
                        val url = call.argument<String>("url")
                        result.success(launchApp(pkg, url))
                    }
                    "requestScreenCapture" -> {
                        // MediaProjection consent + VirtualDisplay + encoder are
                        // not wired in v1.2.0; keep a clear stub for a later release.
                        result.success(mapOf(
                            "ok" to false,
                            "reason" to "not_implemented",
                            "message" to "MediaProjection ekran paylaşımı henüz eklenmedi"
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            val lock = wakeLock ?: pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "aktifdesk:remote"
            ).also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
            if (!lock.isHeld) lock.acquire(10 * 60 * 1000L) // 10 min, refreshed by keepScreenOn
        } catch (_: Exception) {
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
    }

    private fun requestUnlock(): Map<String, Any?> {
        return try {
            runOnUiThread {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
                if (Build.VERSION.SDK_INT >= 27) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                }
            }
            acquireWakeLock()
            val kg = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            val secure = kg.isKeyguardSecure
            if (!secure && kg.isKeyguardLocked) {
                if (Build.VERSION.SDK_INT < 26) {
                    @Suppress("DEPRECATION")
                    kg.newKeyguardLock("aktifdesk").disableKeyguard()
                }
            }
            mapOf(
                "ok" to true,
                "secure" to secure,
                "message" to if (secure)
                    "Ekran uyandırıldı; güvenli kilit (PIN/desen) uzaktan açılamaz"
                else
                    "Ekran uyandırıldı / kilit gevşetildi"
            )
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to (e.message ?: "unlock failed"))
        }
    }

    private fun launchApp(packageName: String?, url: String?): Boolean {
        try {
            if (!url.isNullOrBlank()) {
                val uri = Uri.parse(url)
                if (uri.scheme != "http" && uri.scheme != "https") return false
                startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            }
            if (!packageName.isNullOrBlank()) {
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                    ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launch)
                return true
            }
        } catch (_: Exception) {
            return false
        }
        return false
    }

    private fun findMoonlight(): String? = moonlightPackages.firstOrNull { pkg ->
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(pkg, 0)
            }
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
}
