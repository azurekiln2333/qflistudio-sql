package com.azurekiln.qfli.sqlab

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val installer = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qfli_sql/mysql_runtime")
            .setMethodCallHandler { call, result ->
                if (call.method != "layout") {
                    result.notImplemented()
                } else {
                    installer.execute {
                        try {
                            val layout = MySqlRuntime(applicationContext).prepare()
                            runOnUiThread { result.success(layout) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("mysql_layout", error.message, null) }
                        }
                    }
                }
            }
    }

    override fun onDestroy() {
        installer.shutdown()
        super.onDestroy()
    }
}
