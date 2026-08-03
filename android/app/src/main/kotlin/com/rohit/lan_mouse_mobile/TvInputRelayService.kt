package com.rohit.lan_mouse_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import rikka.shizuku.Shizuku

/**
 * Root-only capture service. It observes getevent without EVIOCGRAB, so TV input
 * continues to work normally. The user-configured gate is fail-closed and must
 * print exactly "active" before any event leaves this service.
 */
class TvInputRelayService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val gateMonitor = Executors.newSingleThreadScheduledExecutor()
    private val running = AtomicBoolean(false)
    private val launching = AtomicBoolean(false)
    @Volatile private var captureProcess: Process? = null
    @Volatile private var activeCaptureDevices: Set<String> = emptySet()
    private var gateUntil = 0L
    private var gateOpen = false
    private var mouseX = 0
    private var mouseY = 0
    private var wheelYLegacy = 0
    private var wheelXLegacy = 0
    private var wheelYHighRes = 0
    private var wheelXHighRes = 0
    private val overlayHandler = Handler(Looper.getMainLooper())
    private var sourceOverlay: TextView? = null
    private var lastFallbackSource: String? = null
    @Volatile private var currentTclHardwareId: String? = null
    @Volatile private var sourceState = SourceState.Unknown
    private val sourceReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val source = intent.getIntExtra("arg1", Int.MIN_VALUE)
            sourceState = when (source) {
                TCL_SOURCE_HDMI -> SourceState.Hdmi1
                TCL_SOURCE_HDMI2 -> SourceState.Hdmi2
                TCL_SOURCE_HDMI3 -> SourceState.Hdmi3
                TCL_SOURCE_HDMI4 -> SourceState.Hdmi4
                TCL_SOURCE_AV -> SourceState.Av
                TCL_SOURCE_ANDROID -> SourceState.Android
                else -> SourceState.Unknown
            }
            gateUntil = 0
            Log.i(TAG, "TCL source changed: arg1=$source, state=$sourceState")
            gateMonitor.execute {
                currentTclHardwareId = resolveTclHardwareId(sourceState)
                showTclSourceOverlay(sourceState, currentTclHardwareId)
                syncCapture()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running.compareAndSet(false, true)) {
            Log.i(TAG, "starting Shizuku getevent capture")
            startForeground(NOTIFICATION_ID, notification())
            gateMonitor.scheduleWithFixedDelay({ syncCapture() }, 0, 500, TimeUnit.MILLISECONDS)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "capture service stopped")
        running.set(false)
        captureProcess?.destroy()
        hideSourceOverlay()
        worker.shutdownNow()
        gateMonitor.shutdownNow()
        unregisterReceiver(sourceReceiver)
        super.onDestroy()
    }

    private fun notification(): android.app.Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, CHANNEL_ID)
        } else {
            android.app.Notification.Builder(this)
        }
        return builder.setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentTitle("Lan Mouse CEC relay active")
            .setContentText("TV input is forwarded only while the selected HDMI gate is active.")
            .setOngoing(true)
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // A previous build exposed this command as the normal TCL gate. It is
        // now an opt-in fallback for non-TCL TVs, so never preserve an always-
        // active bring-up command across the migration.
        val savedGate = prefs.getString(GATE_COMMAND, null)
        if (savedGate == null || savedGate == "echo active" || savedGate == "echo inactive") {
            prefs.edit().putString(GATE_COMMAND, DEFAULT_GATE).apply()
            Log.i(TAG, "migrated custom fallback to universal TV-input detector")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Lan Mouse CEC relay", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        registerReceiver(sourceReceiver, IntentFilter(TCL_SOURCE_CHANGED))
    }

    private fun captureLoop() {
        try {
            // Like Key Mapper's bridge launcher, create the privileged process on
            // Shizuku's server side instead of exec'ing su from the app UID. This
            // matters on OEM Android builds where su launched by an app exits due
            // to its SELinux domain, despite the same command working over ADB.
            val process = startShizukuProcess(arrayOf("sh", "-c", bridgeCommand()))
            captureProcess = process
            Thread {
                process.errorStream.bufferedReader().useLines { lines ->
                    lines.forEach { Log.e(TAG, "Shizuku getevent: $it") }
                }
            }.start()
            BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
                lines.forEach { line ->
                    if (line == "@CEC_EXIT") {
                        TvInputRelayBridge.emit(mapOf("type" to "exit", "code" to "", "value" to 0))
                        stopSelf()
                    } else if (running.get()) parseLine(line)
                }
            }
            Log.w(TAG, "Shizuku getevent exited with ${process.waitFor()}")
        } catch (error: Exception) {
            Log.e(TAG, "unable to start Shizuku getevent", error)
            TvInputRelayBridge.emit(mapOf("type" to "error", "message" to "Unable to start Shizuku getevent: ${error.message}"))
        } finally {
            captureProcess = null
            activeCaptureDevices = emptySet()
            launching.set(false)
        }
    }

    private fun syncCapture() {
        val active = isActiveInput()
        val process = captureProcess
        if (!active && process != null) { process.destroy(); return }
        if (active && process == null && running.get() && launching.compareAndSet(false, true)) {
            worker.execute { captureLoop() }
        }
    }

    private fun bridgeCommand(): String {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val savedPaths = prefs.getStringSet(CAPTURE_DEVICES, emptySet()).orEmpty()
        val savedNames = prefs.getStringSet(CAPTURE_DEVICE_NAMES, emptySet()).orEmpty()
        val devices = resolveDevicePaths(savedPaths, savedNames)
        check(getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(CAPTURE_GRAB_CONFIRMED, false)) {
            "Reopen capture-device selection and save an explicit grab set"
        }
        check(devices.isNotEmpty()) { "Choose capture devices before enabling exclusive CEC capture" }
        activeCaptureDevices = devices.toSet()
        val storage = createDeviceProtectedStorageContext().filesDir
        val bridge = File(storage, "input_grab_bridge")
        // Refresh on every launch: app-private files survive APK upgrades, so
        // retaining an old helper here silently defeats native bridge fixes.
        assets.open(bridgeAssetName()).use { input -> bridge.outputStream().use { input.copyTo(it) } }
        val args = devices.joinToString(" ") { "'${it.replace("'", "'\\\"'\\\"'")}'" }
        return "cp '${bridge.absolutePath}' /data/local/tmp/lan_mouse_input_grab && chmod 700 /data/local/tmp/lan_mouse_input_grab && exec /data/local/tmp/lan_mouse_input_grab $args"
    }

    /** Event numbers are transient; retain names from the selector and resolve
     * them at capture start (for example after a USB receiver reconnects). */
    private fun resolveDevicePaths(savedPaths: Set<String>, savedNames: Set<String>): List<String> {
        if (savedNames.isEmpty()) return savedPaths.toList()
        return try {
            val process = startShizukuProcess(arrayOf("sh", "-c", "/system/bin/getevent -il"))
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            var path: String? = null
            val resolved = mutableListOf<String>()
            for (line in output.lineSequence()) {
                val device = DEVICE_HEADER.find(line)
                if (device != null) { path = device.groupValues[1]; continue }
                val name = DEVICE_NAME.find(line)
                if (name != null && path != null) {
                    if (name.groupValues[1] in savedNames) resolved += path!!
                    path = null
                }
            }
            if (resolved.isNotEmpty()) {
                Log.i(TAG, "resolved capture devices by name: $resolved")
                resolved
            } else savedPaths.toList()
        } catch (error: Exception) {
            Log.w(TAG, "could not resolve capture device names", error)
            savedPaths.toList()
        }
    }

    /** The release APK contains a helper for each supported native ABI. */
    private fun bridgeAssetName(): String = when {
        Build.SUPPORTED_ABIS.any { it == "arm64-v8a" } -> "input_grab_bridge_arm64-v8a"
        Build.SUPPORTED_ABIS.any { it == "x86_64" } -> "input_grab_bridge_x86_64"
        else -> "input_grab_bridge" // armeabi-v7a
    }

    /**
     * Key Mapper uses this Shizuku server-side process path as a MediaTek/OEM
     * fallback. It avoids a normal Android app process spawning `su`.
     */
    @Suppress("DiscouragedPrivateApi")
    private fun startShizukuProcess(command: Array<String>): Process {
        check(Shizuku.pingBinder()) { "Shizuku is not running" }
        check(Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            "Shizuku permission is not granted"
        }
        val method = Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
        )
        method.isAccessible = true
        return method.invoke(null, command, null, null) as Process
    }

    private fun parseLine(line: String) {
        val match = EVENT.find(line) ?: return
        val devicePath = match.groupValues[1]
        if (!isSelectedDevice(devicePath)) return
        val type = match.groupValues[2].lowercase()
        val code = match.groupValues[3].lowercase()
        val value = match.groupValues[4].toLong(16).toInt()
        // Temporary raw-key trace for the unresolved physical Meta mapping.
        // This logs the exact evdev value before it enters the Lan Mouse
        // protocol, while retaining a real Right Shift (0x0036) untouched.
        if (type == "0001" && verboseLogging()) {
            Log.i(TAG, "captured key: device=$devicePath code=0x$code value=$value")
        }
        when (type) {
            "0001" -> when {
                code in BUTTON_CODES -> emitIfActive("button", code, value)
                isForwardableKey(code) -> emitIfActive("key", code, value)
            }
            "0002" -> when (code) {
                "0000" -> mouseX += value
                "0001" -> mouseY += value
                // REL_WHEEL/REL_HWHEEL are whole detents. The corresponding
                // Lan Mouse event uses Windows' 120-units-per-detent scale.
                "0008" -> wheelYLegacy += value
                "0006" -> wheelXLegacy += value
                // Precision touchpads often send both legacy and high-res
                // values in one SYN frame; prefer the latter to avoid a
                // duplicate scroll event.
                "000b" -> wheelYHighRes += value
                "000c" -> wheelXHighRes += value
            }
            "0000" -> if (code == "0000") {
                if (mouseX != 0 || mouseY != 0) {
                    emitIfActive("mouse", mouseX.toString(), mouseY)
                    mouseX = 0; mouseY = 0
                }
                val wheelY = if (wheelYHighRes != 0) wheelYHighRes else wheelYLegacy * 120
                val wheelX = if (wheelXHighRes != 0) wheelXHighRes else wheelXLegacy * 120
                if (wheelY != 0) emitIfActive("wheel120", "0", wheelY)
                if (wheelX != 0) emitIfActive("wheel120", "1", wheelX)
                wheelYLegacy = 0; wheelXLegacy = 0
                wheelYHighRes = 0; wheelXHighRes = 0
            }
        }
    }

    private fun emitIfActive(type: String, code: String, value: Int) {
        if (isActiveInput()) TvInputRelayBridge.emit(mapOf("type" to type, "code" to code, "value" to value))
    }

    /**
     * Lan Mouse uses Linux evdev key codes end-to-end. The original small
     * whitelist accidentally omitted the ANSI right-hand cluster (comma,
     * period, slash, right Shift, right Ctrl, and right Alt). Forward normal
     * keyboard/consumer codes and reserve only keys that must remain local for
     * TV safety until the native grab bridge owns an explicit escape chord.
     */
    private fun isForwardableKey(code: String): Boolean {
        val value = code.toIntOrNull(16) ?: return false
        return value in 0x01..0x2ff && value !in LOCAL_SAFETY_KEYS
    }

    private fun isActiveInput(): Boolean {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val fallbackEnabled = prefs.getBoolean(CUSTOM_FALLBACK_ENABLED, false)
        val needsFallbackGate = sourceState == SourceState.Unknown && fallbackEnabled
        val needsSourceOverlay = fallbackEnabled && prefs.getBoolean(SHOW_SOURCE_OVERLAY, true)
        var detectedSource: String? = null
        val now = System.currentTimeMillis()
        if ((needsFallbackGate || needsSourceOverlay) && now >= gateUntil) {
            detectedSource = detectFallbackSource(prefs)
            if (detectedSource?.matches(Regex("HW[0-9]+")) == true) {
                if (detectedSource != lastFallbackSource) showSourceOverlay(detectedSource)
                lastFallbackSource = detectedSource
            } else lastFallbackSource = null
        }
        val inputIdentifier = inputIdentifier(prefs)
        when (sourceState) {
            SourceState.Hdmi1, SourceState.Hdmi2, SourceState.Hdmi3, SourceState.Hdmi4 ->
                return matchesTclInput(sourceState, currentTclHardwareId, inputIdentifier)
            SourceState.Av, SourceState.Android -> return false
            SourceState.Unknown -> Unit
        }
        // TCL uses its source-change broadcast. A command fallback is only
        // evaluated for a non-TCL device after the user explicitly enables it.
        if (!fallbackEnabled) return false
        if (now < gateUntil) return gateOpen
        val output = detectedSource ?: detectFallbackSource(prefs)
        val expected = inputIdentifier
        gateOpen = output == "active" || (expected.isNotEmpty() && output == expected)
        gateUntil = now + 250
        return gateOpen
    }

    private fun detectFallbackSource(prefs: android.content.SharedPreferences): String = try {
        val command = prefs.getString(GATE_COMMAND, DEFAULT_GATE) ?: DEFAULT_GATE
        val process = startShizukuProcess(arrayOf("sh", "-c", command))
        val output = process.inputStream.bufferedReader().readText().trim()
        process.waitFor()
        output
    } catch (_: Exception) { "" }

    /** TCL broadcasts identify the selected logical input. Resolve the port's
     * hardware ID once at each transition so the confirmation overlay works
     * even on TVs where `dumpsys activity starter` has no passthrough record. */
    private fun resolveTclHardwareId(source: SourceState): String? {
        val port = source.tclPort ?: return null
        return try {
            val process = startShizukuProcess(arrayOf("sh", "-c", "dumpsys tv_input"))
            val dump = process.inputStream.bufferedReader().readText()
            process.waitFor()
            TCL_HARDWARE.findAll(dump).firstOrNull { it.groupValues[2].toInt() == port }
                ?.groupValues?.get(1)
        } catch (_: Exception) { null }
    }

    /** Accept a TCL broadcast value (for example `8` or `arg1=8`) or an
     * Android TV hardware ID (`HW1413744128`). */
    private fun matchesTclInput(source: SourceState, hardwareId: String?, identifier: String): Boolean {
        val normalized = identifier.trim().uppercase()
        val expectedArg = TCL_ARG.find(normalized)?.groupValues?.get(1)?.toIntOrNull()
        if (expectedArg != null) return source.tclSourceCode == expectedArg
        val expectedHardware = HW_ID.find(normalized)?.groupValues?.get(1)
        return expectedHardware != null && hardwareId == expectedHardware
    }

    private fun showTclSourceOverlay(source: SourceState, hardwareId: String?) {
        if (!getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(SHOW_SOURCE_OVERLAY, false)) return
        when (source) {
            SourceState.Hdmi1, SourceState.Hdmi2, SourceState.Hdmi3, SourceState.Hdmi4 -> {
                val port = source.tclPort ?: return
                showSourceOverlay("HDMI $port" + (hardwareId?.let { "  (HW$it)" } ?: ""))
            }
            SourceState.Android -> showSourceOverlay("Android TV")
            SourceState.Av -> showSourceOverlay("AV")
            SourceState.Unknown -> Unit
        }
    }

    /** A short non-interactive HUD lets the user confirm the HW<n> ID while
     * actually viewing that HDMI input. It is strictly opt-in and is ignored
     * when Android's overlay permission has not been granted. */
    private fun showSourceOverlay(source: String) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(SHOW_SOURCE_OVERLAY, true) || !Settings.canDrawOverlays(this)) return
        overlayHandler.post {
            try {
                val wm = getSystemService(WindowManager::class.java)
                sourceOverlay?.let { wm.removeView(it) }
                val view = TextView(this).apply {
                    text = "Source: $source"
                    setTextColor(Color.WHITE)
                    textSize = 22f
                    setPadding(28, 18, 28, 18)
                    setBackgroundColor(0xcc000000.toInt())
                }
                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT,
                ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = 72 }
                wm.addView(view, params)
                sourceOverlay = view
                overlayHandler.removeCallbacksAndMessages(OVERLAY_TOKEN)
                overlayHandler.postAtTime({ hideSourceOverlay() }, OVERLAY_TOKEN,
                    System.currentTimeMillis() + OVERLAY_DURATION_MS)
            } catch (error: Exception) {
                Log.w(TAG, "unable to show source-ID overlay", error)
            }
        }
    }

    private fun hideSourceOverlay() {
        overlayHandler.post {
            sourceOverlay?.let { view ->
                try { getSystemService(WindowManager::class.java).removeView(view) } catch (_: Exception) { }
            }
            sourceOverlay = null
        }
    }

    private fun isSelectedDevice(devicePath: String): Boolean {
        if (activeCaptureDevices.isNotEmpty()) return devicePath in activeCaptureDevices
        val saved = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(CAPTURE_DEVICES, emptySet()) ?: emptySet()
        // An empty selection preserves the previous all-device behavior until
        // the user opens the selector and chooses explicit devices.
        return saved.isEmpty() || devicePath in saved
    }

    private fun verboseLogging(): Boolean = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean(VERBOSE_LOGGING, false)

    companion object {
        const val PREFS = "lan_mouse_tv_cec"
        const val GATE_COMMAND = "gate_command"
        const val CUSTOM_FALLBACK_ENABLED = "custom_fallback_enabled"
        const val SHOW_SOURCE_OVERLAY = "show_source_overlay"
        const val TCL_PC_SOURCE = "tcl_pc_source"
        const val PC_INPUT_NAME = "pc_input_name"
        const val PC_INPUT_IDENTIFIER = "pc_input_identifier"
        const val CAPTURE_DEVICES = "capture_devices"
        const val CAPTURE_DEVICE_NAMES = "capture_device_names"
        const val VERBOSE_LOGGING = "verbose_logging"
        const val CAPTURE_GRAB_CONFIRMED = "capture_grab_confirmed"
        // Report the active passthrough hardware ID on many Android TV builds.
        // A non-TCL user supplies the corresponding PC input ID (e.g. HW5).
        const val DEFAULT_GATE = "dumpsys activity starter | grep -o 'HW[0-9]*' | head -n 1"
        private const val CHANNEL_ID = "lan_mouse_cec"
        private const val NOTIFICATION_ID = 4242
        private const val TAG = "TvInputRelay"
        private const val OVERLAY_DURATION_MS = 4_000L
        private val OVERLAY_TOKEN = Any()
        private const val TCL_SOURCE_CHANGED = "com.tcl.inputsourcechanged"
        const val TCL_SOURCE_HDMI = 8
        const val TCL_SOURCE_HDMI2 = 9
        const val TCL_SOURCE_HDMI3 = 10
        // Inferred from the sequence HDMI1=8, HDMI2=9, HDMI3=10.
        const val TCL_SOURCE_HDMI4 = 11
        private const val TCL_SOURCE_AV = 3
        private const val TCL_SOURCE_ANDROID = 17
        private val EVENT = Regex("^(/dev/input/event\\d+):\\s+([0-9a-fA-F]{4})\\s+([0-9a-fA-F]{4})\\s+([0-9a-fA-F]{8})")
        private val TCL_HARDWARE = Regex("TvInputHardwareInfo \\{id=(\\d+), type=9,.*?hdmi_port=(\\d+),")
        private val TCL_ARG = Regex("^(?:ARG1\\s*=\\s*)?(\\d+)$")
        private val HW_ID = Regex("^HW(\\d+)$")
        private val DEVICE_HEADER = Regex("^add device \\d+: (/dev/input/event\\d+)$")
        private val DEVICE_NAME = Regex("^\\s+name:\\s+\\\"(.*)\\\"$")
        private val BUTTON_CODES = setOf("0110", "0111", "0112")
        // KEY_POWER, KEY_SLEEP, KEY_WAKEUP, KEY_RESTART, and KEY_SCREENLOCK.
        // These must never be forwarded/consumed by a PC-input relay.
        private val LOCAL_SAFETY_KEYS = setOf(0x74, 0x8e, 0x8f, 0x198, 0x98)

        /** Preserve the user's earlier HDMI choice / fallback ID on upgrade. */
        fun inputIdentifier(prefs: android.content.SharedPreferences): String {
            prefs.getString(PC_INPUT_IDENTIFIER, null)?.let { return it }
            val legacyHardware = prefs.getString("custom_fallback_source", "").orEmpty().trim()
            return if (legacyHardware.isNotEmpty()) legacyHardware
            else prefs.getInt(TCL_PC_SOURCE, TCL_SOURCE_HDMI).toString()
        }
    }

    private enum class SourceState(val tclSourceCode: Int? = null, val tclPort: Int? = null) {
        Unknown,
        Android(TCL_SOURCE_ANDROID),
        Av(TCL_SOURCE_AV),
        Hdmi1(TCL_SOURCE_HDMI, 1),
        Hdmi2(TCL_SOURCE_HDMI2, 2),
        Hdmi3(TCL_SOURCE_HDMI3, 3),
        Hdmi4(TCL_SOURCE_HDMI4, 4),
    }
}
