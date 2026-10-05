package com.aktifdesk.aktifdesk

import android.Manifest
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
import android.text.TextUtils
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
                try {
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
                                startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://play.google.com/store/apps/details?id=$p"),
                                    ),
                                )
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
                        "requestUnlock" -> result.success(requestUnlock())
                        "launchApp" -> {
                            val pkg = call.argument<String>("package")
                            val url = call.argument<String>("url")
                            result.success(launchApp(pkg, url))
                        }
                        "requestScreenCapture" -> {
                            // MediaProjection + VirtualDisplay + encoder not bundled yet.
                            // Isolated stub — never throws into Flutter.
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "reason" to "not_implemented",
                                    "message" to "MediaProjection ekran paylaşımı henüz eklenmedi; kontrol (dokunma) Erişilebilirlik ile çalışır",
                                ),
                            )
                        }
                        "permissionStatus" -> result.success(permissionStatus())
                        "openPermissionSettings" -> {
                            val which = call.argument<String>("which") ?: ""
                            result.success(openPermissionSettings(which))
                        }
                        "requestRuntimePermissions" -> {
                            requestRuntimePermissions()
                            result.success(true)
                        }
                        "startHostForeground" -> {
                            val waiting = call.argument<Boolean>("waiting") ?: true
                            HostForegroundService.start(applicationContext, waiting)
                            result.success(true)
                        }
                        "updateHostForeground" -> {
                            val waiting = call.argument<Boolean>("waiting") ?: true
                            HostForegroundService.update(applicationContext, waiting)
                            result.success(true)
                        }
                        "stopHostForeground" -> {
                            HostForegroundService.stop(applicationContext)
                            result.success(true)
                        }
                        "injectTap" -> {
                            val x = (call.argument<Number>("x") ?: 0).toDouble()
                            val y = (call.argument<Number>("y") ?: 0).toDouble()
                            val abs = call.argument<Boolean>("absolute") ?: false
                            val svc = RemoteAccessibilityService.instance
                            if (svc == null) {
                                result.success(mapOf("ok" to false, "reason" to "accessibility_off",
                                    "message" to "Erişilebilirlik servisi kapalı"))
                            } else {
                                val ok = try {
                                    svc.tap(x, y, abs)
                                } catch (e: Exception) {
                                    false
                                }
                                result.success(mapOf("ok" to ok, "message" to if (ok) "Dokunma gönderildi" else "Dokunma başarısız"))
                            }
                        }
                        "injectSwipe" -> {
                            val x1 = (call.argument<Number>("x1") ?: 0).toDouble()
                            val y1 = (call.argument<Number>("y1") ?: 0).toDouble()
                            val x2 = (call.argument<Number>("x2") ?: 0).toDouble()
                            val y2 = (call.argument<Number>("y2") ?: 0).toDouble()
                            val dur = (call.argument<Number>("durationMs") ?: 300).toLong()
                            val abs = call.argument<Boolean>("absolute") ?: false
                            val svc = RemoteAccessibilityService.instance
                            if (svc == null) {
                                result.success(mapOf("ok" to false, "reason" to "accessibility_off",
                                    "message" to "Erişilebilirlik servisi kapalı"))
                            } else {
                                val ok = try {
                                    svc.swipe(x1, y1, x2, y2, dur, abs)
                                } catch (e: Exception) {
                                    false
                                }
                                result.success(mapOf("ok" to ok, "message" to if (ok) "Kaydırma gönderildi" else "Kaydırma başarısız"))
                            }
                        }
                        "injectKey" -> {
                            val key = call.argument<String>("key") ?: ""
                            val svc = RemoteAccessibilityService.instance
                            if (svc == null) {
                                result.success(mapOf("ok" to false, "reason" to "accessibility_off",
                                    "message" to "Erişilebilirlik servisi kapalı"))
                            } else {
                                val ok = try {
                                    svc.globalKey(key)
                                } catch (e: Exception) {
                                    false
                                }
                                result.success(mapOf("ok" to ok, "message" to if (ok) "Tuş gönderildi" else "Tuş desteklenmiyor / başarısız"))
                            }
                        }
                        "injectText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val svc = RemoteAccessibilityService.instance
                            if (svc == null) {
                                result.success(mapOf("ok" to false, "reason" to "accessibility_off",
                                    "message" to "Erişilebilirlik servisi kapalı"))
                            } else {
                                val ok = try {
                                    svc.typeText(text)
                                } catch (e: Exception) {
                                    false
                                }
                                result.success(mapOf("ok" to ok, "message" to if (ok) "Metin yazıldı" else "Odaklı alan yok veya yazılamadı"))
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // Never let native errors crash the Flutter isolate.
                    result.success(
                        mapOf(
                            "ok" to false,
                            "reason" to "native_error",
                            "message" to (e.message ?: e.javaClass.simpleName),
                        ),
                    )
                }
            }
    }

    private fun permissionStatus(): Map<String, Any?> {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val ignoringBattery = if (Build.VERSION.SDK_INT >= 23) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
        val overlay = if (Build.VERSION.SDK_INT >= 23) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
        val notifications = if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val notificationListener = isNotificationListenerEnabled()
        return mapOf(
            "accessibility" to isAccessibilityEnabled(),
            "accessibilityRunning" to RemoteAccessibilityService.isRunning(),
            "batteryOptimizationIgnored" to ignoringBattery,
            "overlay" to overlay,
            "notifications" to notifications,
            "notificationListener" to notificationListener,
            "foregroundService" to true, // declared; runtime start is separate
            "wakeLock" to true,
            "screenCapture" to false, // MediaProjection consent is session-based, not a sticky grant
        )
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, RemoteAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            val cn = ComponentName.unflattenFromString(splitter.next())
            if (cn != null && cn == expected) return true
        }
        return RemoteAccessibilityService.isRunning()
    }

    private fun isNotificationListenerEnabled(): Boolean {
        return try {
            val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                ?: return false
            val pkg = packageName
            flat.split(':').any { it.contains(pkg) }
        } catch (_: Exception) {
            false
        }
    }

    private fun openPermissionSettings(which: String): Boolean {
        return try {
            val intent = when (which) {
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "battery" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    } else {
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    }
                }
                "overlay" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    }
                }
                "notifications" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    }
                }
                "notification_listener" -> Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                "app" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
                else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun requestRuntimePermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (needed.isNotEmpty() && Build.VERSION.SDK_INT >= 23) {
            requestPermissions(needed.toTypedArray(), 1001)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            val lock = wakeLock ?: pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "aktifdesk:remote",
            ).also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
            if (!lock.isHeld) lock.acquire(10 * 60 * 1000L)
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
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
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
                    "Ekran uyandırıldı / kilit gevşetildi",
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
