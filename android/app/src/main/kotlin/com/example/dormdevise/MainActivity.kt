package com.lulo.dormdevise

import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
	private var receiver: PackageInstallReceiver? = null
	private var eventSink: EventChannel.EventSink? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		val channel = EventChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"dormdevise/update/install_events"
		)

		channel.setStreamHandler(object : EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				eventSink = events
				// 注册广播接收器
				if (receiver == null) {
					receiver = PackageInstallReceiver { pkg ->
						events?.success(pkg)
					}
					val filter = IntentFilter()
					filter.addAction(Intent.ACTION_PACKAGE_ADDED)
					filter.addAction(Intent.ACTION_PACKAGE_REPLACED)
					filter.addDataScheme("package")
					applicationContext.registerReceiver(receiver, filter)
				}
			}

			override fun onCancel(arguments: Any?) {
				// 取消订阅时注销广播接收器
				try {
					if (receiver != null) {
						applicationContext.unregisterReceiver(receiver)
						receiver = null
					}
				} catch (e: Exception) {
					// 忽略注销异常
				}
				eventSink = null
			}
		})
	}
}
