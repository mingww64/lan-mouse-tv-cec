package com.rohit.lan_mouse_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import af.shizuku.api.BinderContainer as AfBinderContainer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku

class MainActivity: FlutterActivity() {
    private var startWhenShizukuReady = false
    private var flutterControlChannel: MethodChannel? = null
    private var captureEndedOverlay: LinearLayout? = null

    // Retain these wire-compatible parcelables in release builds. ShizukuPlus
    // sends them while delivering its binder, before the standard library gets
    // a chance to consume the current-format parcelable.
    @Suppress("unused")
    private val shizukuPlusCompatibilityTypes = arrayOf<Class<*>>(
        rikka.shizuku.BinderContainer::class.java,
        AfBinderContainer::class.java,
    )

    private fun startCaptureService() {
        hideCaptureEndedOverlay()
        val intent = Intent(this, TvInputRelayService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    /** A real system overlay, shown above the HDMI source after the native
     * grabber exits. Unlike a Flutter dialog it stays visible while TV input
     * is selected, and its focused button is usable with a D-pad. */
    private fun showCaptureEndedOverlay(profile: String, client: String): Boolean {
        if (!Settings.canDrawOverlays(this)) return false
        runOnUiThread {
            try {
                val wm = getSystemService(WindowManager::class.java)
                captureEndedOverlay?.let { wm.removeView(it) }
                val padding = (20 * resources.displayMetrics.density).toInt()
                val panel = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(padding, padding, padding, padding)
                    background = GradientDrawable().apply {
                        setColor(0xf0202124.toInt())
                        cornerRadius = 12 * resources.displayMetrics.density
                        setStroke((1 * resources.displayMetrics.density).toInt(), 0xff5f6368.toInt())
                    }
                }
                panel.addView(TextView(this).apply {
                    text = "Capture ended"
                    textSize = 22f
                    setTextColor(Color.WHITE)
                })
                panel.addView(TextView(this).apply {
                    text = client
                    textSize = 15f
                    setTextColor(0xffc7c7c7.toInt())
                    setPadding(0, (6 * resources.displayMetrics.density).toInt(), 0, padding / 2)
                })
                val resume = Button(this).apply {
                    text = "Resume capture"
                    isAllCaps = false
                    isFocusable = true
                    setOnClickListener {
                        val channel = flutterControlChannel
                        if (channel == null) {
                            Log.w("TvInputRelay", "resume overlay has no Flutter channel")
                            return@setOnClickListener
                        }
                        channel.invokeMethod("resumeCapture", profile, object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                if (result == true) {
                                    Log.i("TvInputRelay", "resume overlay accepted for $profile")
                                    hideCaptureEndedOverlay()
                                } else Log.w("TvInputRelay", "resume overlay rejected for $profile")
                            }
                            override fun error(code: String, message: String?, details: Any?) {
                                Log.w("TvInputRelay", "resume overlay failed: $code $message")
                            }
                            override fun notImplemented() {
                                Log.w("TvInputRelay", "resume overlay callback is not implemented")
                            }
                        })
                    }
                }
                panel.addView(resume, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                panel.addView(Button(this).apply {
                    text = "Close"
                    isAllCaps = false
                    setOnClickListener {
                        flutterControlChannel?.invokeMethod("dismissCaptureEnded", null, object : MethodChannel.Result {
                            override fun success(result: Any?) { if (result == true) hideCaptureEndedOverlay() }
                            override fun error(code: String, message: String?, details: Any?) {
                                Log.w("TvInputRelay", "capture-ended overlay close failed: $code $message")
                            }
                            override fun notImplemented() { Log.w("TvInputRelay", "capture-ended overlay close is not implemented") }
                        })
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                val params = WindowManager.LayoutParams(
                    (420 * resources.displayMetrics.density).toInt(),
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT,
                ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = (72 * resources.displayMetrics.density).toInt() }
                wm.addView(panel, params)
                captureEndedOverlay = panel
                resume.requestFocus()
            } catch (error: Exception) {
                Log.w("TvInputRelay", "unable to show capture-ended overlay", error)
            }
        }
        return true
    }

    private fun hideCaptureEndedOverlay() {
        runOnUiThread {
            captureEndedOverlay?.let { view ->
                try { getSystemService(WindowManager::class.java).removeView(view) } catch (_: Exception) { }
            }
            captureEndedOverlay = null
        }
    }

    private fun startWhenPermitted() {
        if (Shizuku.checkSelfPermission() != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
        } else {
            startCaptureService()
        }
    }

    @Suppress("DiscouragedPrivateApi")
    private fun runShizukuCommand(command: String): String {
        check(Shizuku.pingBinder()) { "Shizuku is not ready" }
        check(Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            "Shizuku permission is not granted"
        }
        val method = Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
        )
        method.isAccessible = true
        val process = method.invoke(null, arrayOf("sh", "-c", command), null, null) as Process
        val output = process.inputStream.bufferedReader().readText()
        val error = process.errorStream.bufferedReader().readText()
        val exit = process.waitFor()
        check(exit == 0) { error.ifBlank { "command failed with exit $exit" } }
        return output
    }

    private fun inputDevices(): List<Map<String, String>> {
        val output = runShizukuCommand("/system/bin/getevent -il")
        val devices = mutableListOf<Map<String, String>>()
        var path: String? = null
        for (line in output.lineSequence()) {
            val device = DEVICE_HEADER.find(line)
            if (device != null) {
                path = device.groupValues[1]
                continue
            }
            val name = DEVICE_NAME.find(line)
            if (name != null && path != null) {
                devices += mapOf("path" to path!!, "name" to name.groupValues[1])
                path = null
            }
        }
        return devices
    }

    /** Keep service reads simple: on client selection, swap that profile's
     * settings into the existing live keys. */
    private fun activateProfile(prefs: android.content.SharedPreferences, profile: String) {
        require(profile.isNotBlank()) { "Profile ID is required" }
        val previous = prefs.getString(ACTIVE_PROFILE, null)
        if (previous == profile) return
        if (previous != null) {
            copySettings(prefs, PROFILE_PREFIX + previous, "")
            prefs.edit().putString(PROFILE_PREFIX + previous + PROFILE_TRIGGER,
                TvInputRelayService.inputIdentifier(prefs)).apply()
        }
        val profilePrefix = PROFILE_PREFIX + profile
        if (prefs.contains(profilePrefix + PROFILE_TRIGGER)) {
            copySettings(prefs, "", profilePrefix)
            prefs.edit().putString(TvInputRelayService.PC_INPUT_IDENTIFIER,
                prefs.getString(profilePrefix + PROFILE_TRIGGER, "") ?: "").apply()
        } else {
            // First use inherits the prior global configuration.
            copySettings(prefs, profilePrefix, "")
            val identifier = TvInputRelayService.inputIdentifier(prefs)
            prefs.edit()
                .putString(profilePrefix + PROFILE_TRIGGER, identifier)
                .apply()
        }
        prefs.edit().putString(ACTIVE_PROFILE, profile).apply()
    }

    private fun persistActiveProfile(prefs: android.content.SharedPreferences) {
        prefs.getString(ACTIVE_PROFILE, null)?.let {
            copySettings(prefs, PROFILE_PREFIX + it, "")
            prefs.edit().putString(PROFILE_PREFIX + it + PROFILE_TRIGGER,
                TvInputRelayService.inputIdentifier(prefs)).apply()
        }
    }

    private fun tvInputs(): List<Map<String, String>> {
        val dump = runShizukuCommand("dumpsys tv_input")
        val registered = TV_INPUT_ID.findAll(dump).map { it.groupValues[1] }.toSet()
        val inputs = linkedMapOf<String, Map<String, String>>()
        for (line in dump.lineSequence()) {
            val hardware = TV_HARDWARE.find(line) ?: continue
            val id = hardware.groupValues[1]
            if (registered.isNotEmpty() && id !in registered) continue
            val type = hardware.groupValues[2].toInt()
            val port = HDMI_PORT.find(line)?.groupValues?.get(1)?.toIntOrNull()
            val name = when (type) {
                2 -> "Live TV"
                3 -> "AV"
                5 -> "Component"
                7 -> "S-Video"
                9 -> "HDMI ${port ?: "?"}"
                else -> "TV input (type $type)"
            }
            inputs.putIfAbsent(id, mapOf(
                "name" to name,
                "identifier" to "HW$id",
                "tclArg" to if (type == 9 && port != null) (7 + port).toString() else "",
            ))
        }
        return inputs.values.toList()
    }

    private fun copySettings(prefs: android.content.SharedPreferences, destinationPrefix: String, sourcePrefix: String) {
        val editor = prefs.edit()
        for (key in PROFILE_STRING_KEYS) {
            val value = prefs.getString(sourcePrefix + key, null)
            if (value == null) editor.remove(destinationPrefix + key) else editor.putString(destinationPrefix + key, value)
        }
        for (key in PROFILE_BOOLEAN_KEYS) editor.putBoolean(destinationPrefix + key, prefs.getBoolean(sourcePrefix + key, false))
        for (key in PROFILE_SET_KEYS) editor.putStringSet(destinationPrefix + key,
            prefs.getStringSet(sourcePrefix + key, emptySet()) ?: emptySet())
        editor.apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Shizuku.addBinderReceivedListener {
            if (startWhenShizukuReady) {
                startWhenShizukuReady = false
                startWhenPermitted()
            }
        }
        Shizuku.addRequestPermissionResultListener { requestCode, resultCode ->
            if (requestCode == SHIZUKU_REQUEST_CODE) {
                if (resultCode == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    startCaptureService()
                } else {
                    TvInputRelayBridge.emit(mapOf("type" to "error", "message" to "Shizuku permission was denied"))
                }
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lan_mouse_tv_cec/input_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = TvInputRelayBridge.setSink(events)
                override fun onCancel(arguments: Any?) = TvInputRelayBridge.setSink(null)
            })
        flutterControlChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lan_mouse_tv_cec/control")
        flutterControlChannel!!.setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(TvInputRelayService.PREFS, MODE_PRIVATE)
                when (call.method) {
                    "activateProfile" -> {
                        val profile = call.arguments as? String
                        if (profile.isNullOrBlank()) result.error("invalid_profile", "Profile ID is required", null)
                        else try { activateProfile(prefs, profile); result.success(null) }
                        catch (error: IllegalArgumentException) { result.error("invalid_profile", error.message, null) }
                    }
                    "getTvInputs" -> try { result.success(tvInputs()) }
                    catch (error: Exception) { result.error("tv_input_query_failed", error.message, null) }
                    "getProfileTrigger" -> result.success(
                        TvInputRelayService.inputIdentifier(prefs)
                    )
                    "setProfileTrigger" -> {
                        val identifier = call.arguments as? String
                        if (identifier.isNullOrBlank()) result.error("invalid_trigger", "A TV input is required", null)
                        else {
                            prefs.edit().putString(TvInputRelayService.PC_INPUT_IDENTIFIER, identifier).apply()
                            persistActiveProfile(prefs)
                            result.success(null)
                        }
                    }
                    "start" -> {
                        if (!Shizuku.pingBinder()) {
                            // The provider receives the binder shortly after an
                            // Activity starts on ShizukuPlus. Do not fail the
                            // first Flutter request during that short window.
                            startWhenShizukuReady = true
                        } else {
                            startWhenPermitted()
                        }
                        result.success(null)
                    }
                    "isCaptureRunning" -> result.success(
                        prefs.getBoolean(TvInputRelayService.CAPTURE_SERVICE_RUNNING, false)
                    )
                    "showCaptureEndedOverlay" -> {
                        val args = call.arguments as? Map<*, *>
                        val profile = args?.get("profile") as? String
                        val client = args?.get("client") as? String
                        if (profile.isNullOrBlank() || client.isNullOrBlank()) {
                            result.error("invalid_overlay", "Expected profile and client", null)
                        } else result.success(showCaptureEndedOverlay(profile, client))
                    }
                    "hideCaptureEndedOverlay" -> { hideCaptureEndedOverlay(); result.success(null) }
                    "stop" -> { stopService(Intent(this, TvInputRelayService::class.java)); result.success(null) }
                    "getCustomFallback" -> result.success(mapOf(
                        "enabled" to prefs.getBoolean(TvInputRelayService.CUSTOM_FALLBACK_ENABLED, false),
                        "command" to (prefs.getString(TvInputRelayService.GATE_COMMAND, TvInputRelayService.DEFAULT_GATE)
                            ?: TvInputRelayService.DEFAULT_GATE),
                        "showOverlay" to prefs.getBoolean(TvInputRelayService.SHOW_SOURCE_OVERLAY, true),
                    ))
                    "setCustomFallback" -> {
                        val args = call.arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean
                        val command = args?.get("command") as? String
                        val showOverlay = args?.get("showOverlay") as? Boolean ?: true
                        if (enabled == null || command.isNullOrBlank()) {
                            result.error("invalid_fallback", "Expected enabled and command", null)
                        } else {
                            prefs.edit()
                                .putBoolean(TvInputRelayService.CUSTOM_FALLBACK_ENABLED, enabled)
                                .putString(TvInputRelayService.GATE_COMMAND, command)
                                .putBoolean(TvInputRelayService.SHOW_SOURCE_OVERLAY, showOverlay)
                                .apply()
                            if (!showOverlay) {
                                sendBroadcast(Intent(TvInputRelayService.HIDE_SOURCE_OVERLAY)
                                    .setPackage(packageName))
                            }
                            persistActiveProfile(prefs)
                            result.success(null)
                        }
                    }
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "requestOverlayPermission" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "getInputDevices" -> try {
                        result.success(inputDevices())
                    } catch (error: Exception) {
                        Log.e("TvInputRelay", "unable to enumerate input devices", error)
                        result.error("device_query_failed", error.message, null)
                    }
                    "getCaptureDevices" -> result.success(
                        prefs.getStringSet(TvInputRelayService.CAPTURE_DEVICES, emptySet())?.toList() ?: emptyList<String>()
                    )
                    "getVerboseLogging" -> result.success(
                        prefs.getBoolean(TvInputRelayService.VERBOSE_LOGGING, false)
                    )
                    "setVerboseLogging" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) result.error("invalid_verbose", "Expected a boolean", null)
                        else {
                            prefs.edit().putBoolean(TvInputRelayService.VERBOSE_LOGGING, enabled).apply()
                            persistActiveProfile(prefs)
                            result.success(null)
                        }
                    }
                    "setCaptureDevices" -> {
                        val devices = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>()
                            ?.filter { it.startsWith("/dev/input/event") }
                            ?.toSet()
                        if (devices == null) result.error("invalid_devices", "Expected input device paths", null)
                        else {
                            val names = try {
                                inputDevices().filter { it["path"] in devices }
                                    .mapNotNull { it["name"] as? String }.toSet()
                            } catch (_: Exception) { emptySet() }
                            prefs.edit()
                                .putStringSet(TvInputRelayService.CAPTURE_DEVICES, devices)
                                .putStringSet(TvInputRelayService.CAPTURE_DEVICE_NAMES, names)
                                .putBoolean(TvInputRelayService.CAPTURE_GRAB_CONFIRMED, true)
                                .apply()
                            persistActiveProfile(prefs)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val SHIZUKU_REQUEST_CODE = 850
        private val DEVICE_HEADER = Regex("^add device \\d+: (/dev/input/event\\d+)$")
        private val DEVICE_NAME = Regex("^\\s+name:\\s+\\\"(.*)\\\"$")
        private const val ACTIVE_PROFILE = "active_relay_profile"
        private const val PROFILE_PREFIX = "profile:"
        private const val PROFILE_TRIGGER = "trigger"
        private val PROFILE_STRING_KEYS = arrayOf(
            TvInputRelayService.GATE_COMMAND,
        )
        private val PROFILE_BOOLEAN_KEYS = arrayOf(
            TvInputRelayService.CUSTOM_FALLBACK_ENABLED, TvInputRelayService.SHOW_SOURCE_OVERLAY,
            TvInputRelayService.CAPTURE_GRAB_CONFIRMED,
        )
        private val PROFILE_SET_KEYS = arrayOf(
            TvInputRelayService.CAPTURE_DEVICES, TvInputRelayService.CAPTURE_DEVICE_NAMES,
        )
        private val TV_INPUT_ID = Regex("TvInputInfo\\{id=.*?/HW(\\d+)")
        private val TV_HARDWARE = Regex("TvInputHardwareInfo \\{id=(\\d+), type=(\\d+),")
        private val HDMI_PORT = Regex("hdmi_port=(\\d+),")
    }
}
