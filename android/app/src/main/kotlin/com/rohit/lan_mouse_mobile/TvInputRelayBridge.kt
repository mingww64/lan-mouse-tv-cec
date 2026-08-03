package com.rohit.lan_mouse_mobile

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Keeps the native foreground capture service connected to the running Dart isolate. */
object TvInputRelayBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    fun setSink(newSink: EventChannel.EventSink?) { sink = newSink }

    fun emit(event: Map<String, Any>) {
        mainHandler.post { sink?.success(event) }
    }
}
