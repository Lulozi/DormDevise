package com.lulo.dormdevise

import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
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
					val title = call.argument<String>("title") ?: "课程提醒"
					val body = call.argument<String>("body") ?: ""
					val isAlarm = call.argument<Boolean>("isAlarm") ?: false
					val enableVibration = call.argument<Boolean>("enableVibration") ?: true
					AlarmNotificationScheduler.schedule(
						context = applicationContext,
						id = id,
						triggerAtMillis = triggerAtMillis,
						title = title,
						body = body,
						isAlarm = isAlarm,
						enableVibration = enableVibration
					)
					result.success(null)
				}
				"showNow" -> {
					val id = call.argument<Int>("id") ?: 0
					val title = call.argument<String>("title") ?: "课程提醒"
					val body = call.argument<String>("body") ?: ""
					val isAlarm = call.argument<Boolean>("isAlarm") ?: false
					val enableVibration = call.argument<Boolean>("enableVibration") ?: true
					AlarmNotificationScheduler.showNow(
						context = applicationContext,
						id = id,
						title = title,
						body = body,
						isAlarm = isAlarm,
						enableVibration = enableVibration
					)
					result.success(null)
				}
				"cancelAll" -> {
					AlarmNotificationScheduler.cancelAll(applicationContext)
					result.success(null)
				}
				"restore" -> {
					AlarmNotificationScheduler.restoreAll(applicationContext)
					result.success(null)
				}
                "list" -> {
                    val ids = AlarmNotificationScheduler.getScheduledIds(applicationContext)
                    result.success(ids)
                }
				else -> result.notImplemented()
			}
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"dormdevise/window"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"setSoftInputMode" -> {
					val mode = when (call.argument<String>("mode")) {
						"adjustNothing" -> WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
						"adjustPan" -> WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
						else -> WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
					}
					runOnUiThread {
						window.setSoftInputMode(mode)
						result.success(null)
					}
				}
				"setShowWhenLocked" -> {
					val show = call.argument<Boolean>("show") ?: false
					val turn = call.argument<Boolean>("turn") ?: false
					runOnUiThread {
						setShowWhenLockedAndTurnScreenOn(show, turn)
						result.success(null)
					}
				}
				else -> result.notImplemented()
			}
		}

		handlePendingRoute(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleLockscreenFlagsIfNeeded(intent)
		handlePendingRoute(intent)
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		handleLockscreenFlagsIfNeeded(intent)
	}

	/**
	 * 根据 Intent 中的额外字段按需在运行时打开或关闭锁屏显示与点亮屏幕。
	 * 期望的 extras:
	 *  - "showOnLock": Boolean
	 *  - "turnScreenOn": Boolean
	 */
	private fun handleLockscreenFlagsIfNeeded(intent: Intent?) {
		val showOnLock = intent?.getBooleanExtra("showOnLock", false) ?: false
		val turnOn = intent?.getBooleanExtra("turnScreenOn", false) ?: false
		if (showOnLock || turnOn) {
			runOnUiThread {
				setShowWhenLockedAndTurnScreenOn(showOnLock, turnOn)
			}
		}
	}

	private fun setShowWhenLockedAndTurnScreenOn(show: Boolean, turn: Boolean) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
			setShowWhenLocked(show)
			setTurnScreenOn(turn)
		} else {
			if (show || turn) {
				window.addFlags(
					WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
					WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
				)
			} else {
				window.clearFlags(
					WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
					WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
				)
			}
		}
	}

	private fun handlePendingRoute(intent: Intent?) {
		val route = intent?.getStringExtra("route")?.trim()
		if (!route.isNullOrEmpty()) {
			flutterEngine?.navigationChannel?.pushRoute(route)
			intent.removeExtra("route")
		}
	}
}
