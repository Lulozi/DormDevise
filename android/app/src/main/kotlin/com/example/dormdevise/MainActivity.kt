package com.lulo.dormdevise

import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private var receiver: PackageInstallReceiver? = null
	private var eventSink: EventChannel.EventSink? = null

	/**
	 * 解析启动参数中的路由信息，支持直接进入配置页面。
	 */
	override fun getInitialRoute(): String {
		val route = intent?.getStringExtra("route")?.trim()
		return if (route.isNullOrEmpty()) "/" else route
	}

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

		// 原生闹钟通知渠道：用于自定义 RemoteViews 以将关闭按钮放到右侧
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"dormdevise/alarm_notifications"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"schedule" -> {
					val id = call.argument<Int>("id") ?: 0
					val triggerAtMillis = call.argument<Long>("triggerAtMillis") ?: 0L
					val course = call.argument<String>("course") ?: "课程"
					val location = call.argument<String>("location") ?: "未知教室"
					val minutes = call.argument<Int>("minutes") ?: 0
					AlarmNotificationScheduler.schedule(applicationContext, id, triggerAtMillis, course, location, minutes)
					result.success(null)
				}
				"showNow" -> {
					val id = call.argument<Int>("id") ?: 0
					val course = call.argument<String>("course") ?: "课程"
					val location = call.argument<String>("location") ?: "未知教室"
					val minutes = call.argument<Int>("minutes") ?: 0
					AlarmNotificationScheduler.showNow(applicationContext, id, course, location, minutes)
					result.success(null)
				}
				"cancelAll" -> {
					AlarmNotificationScheduler.cancelAll(applicationContext)
					result.success(null)
				}
                "list" -> {
                    val ids = AlarmNotificationScheduler.getScheduledIds(applicationContext)
                    result.success(ids)
                }
				else -> result.notImplemented()
			}
		}

		handlePendingRoute(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handlePendingRoute(intent)
	}

	private fun handlePendingRoute(intent: Intent?) {
		val route = intent?.getStringExtra("route")?.trim()
		if (!route.isNullOrEmpty()) {
			flutterEngine?.navigationChannel?.pushRoute(route)
			intent.removeExtra("route")
		}
	}
}
