package com.perfu.tareas_rapidas.tareas_rapidas  // <-- AJUSTA este paquete a tu app

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val CHANNEL = "local_store"
    private val PREFS = "local_store_prefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            when (call.method) {
                "get" -> {
                    val key = call.argument<String>("key")
                    if (key == null) {
                        result.error("ARG", "key es null", null)
                        return@setMethodCallHandler
                    }
                    val value = prefs.getString(key, null)
                    result.success(value) // puede ser null
                }

                "set" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key == null) {
                        result.error("ARG", "key es null", null)
                        return@setMethodCallHandler
                    }
                    prefs.edit().putString(key, value).apply()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
