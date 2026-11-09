package com.anychat.fork

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var shellChannel: MethodChannel? = null
    private var shellReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val guard = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GUARD_CHANNEL
        )
        guard.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, StreamService::class.java)
                    if (Build.VERSION.SDK_INT >= 26) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, StreamService::class.java)
                    intent.setAction(StreamService.ACTION_STOP)
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHELL_CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "termuxCheck" -> {
                    result.success(isTermuxInstalled())
                }
                "termuxRun" -> {
                    val script = call.argument<String>("script")
                    if (script == null) {
                        result.error("ARG", "script required", null)
                    } else {
                        result.success(sendTermuxCommand(script))
                    }
                }
                else -> result.notImplemented()
            }
        }
        shellChannel = channel
        registerShellReceiver()
    }

    override fun onDestroy() {
        val receiver = shellReceiver
        if (receiver != null) {
            try {
                unregisterReceiver(receiver)
            } catch (e: Exception) {
            }
            shellReceiver = null
        }
        shellChannel = null
        super.onDestroy()
    }

    private fun registerShellReceiver() {
        if (shellReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val id = intent.getStringExtra("id") ?: return
                val rc = intent.getIntExtra("rc", -999)
                val out = intent.getStringExtra("out") ?: ""
                shellChannel?.invokeMethod(
                    "onShellResult",
                    mapOf("id" to id, "rc" to rc, "out" to out)
                )
            }
        }
        val filter = IntentFilter("com.anychat.fork.SHELL_RESULT")
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        shellReceiver = receiver
    }

    private fun isTermuxInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo("com.termux", 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun sendTermuxCommand(script: String): Boolean {
        return try {
            val intent = Intent("com.termux.RUN_COMMAND")
            intent.setClassName("com.termux", "com.termux.app.RunCommandService")
            intent.putExtra(
                "com.termux.RUN_COMMAND_PATH",
                "/data/data/com.termux/files/usr/bin/bash"
            )
            intent.putExtra(
                "com.termux.RUN_COMMAND_ARGUMENTS",
                arrayOf("-c", script)
            )
            intent.putExtra(
                "com.termux.RUN_COMMAND_WORKDIR",
                "/data/data/com.termux/files/home"
            )
            intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            startService(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        const val GUARD_CHANNEL = "anychat/stream_guard"
        const val SHELL_CHANNEL = "anychat/termux"
    }
}
