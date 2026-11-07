package com.anychat.fork

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "app.anychat/shared"
        var pendingShare: String? = null
    }

    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stashIfShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consume" -> {
                    val text = pendingShare
                    pendingShare = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        pendingShare?.let { text ->
            pendingShare = null
            channel?.invokeMethod("sharedText", text)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stashIfShare(intent)?.let { text ->
            channel?.invokeMethod("sharedText", text)
        }
    }

    private fun stashIfShare(intent: Intent): String? {
        if (intent.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (type != "text/plain" && !type.startsWith("text/")) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (text.isNullOrEmpty()) return null
        pendingShare = text
        return text
    }
}
