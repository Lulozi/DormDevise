package com.lulo.dormdevise

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

/**
 * 统一处理桌面组件的 pin 请求、预览推送和成功后的回桌面逻辑。
 */
object DoorWidgetPinRequestHelper {
    const val actionPinSuccess = "com.lulo.dormdevise.action.DOOR_WIDGET_PIN_SUCCESS"
    const val extraProviderClassName = "providerClassName"

    fun requestPin(
        activity: Activity,
        providerClass: Class<out AppWidgetProvider>,
        previewLayoutResId: Int,
        requestCode: Int,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        val appWidgetManager = activity.getSystemService(AppWidgetManager::class.java)
            ?: return false
        if (!appWidgetManager.isRequestPinAppWidgetSupported) {
            return false
        }

        pushGeneratedPreviewIfSupported(
            context = activity.applicationContext,
            providerClass = providerClass,
            previewLayoutResId = previewLayoutResId,
        )

        val provider = ComponentName(activity, providerClass)
        val successCallback = buildSuccessCallback(
            context = activity,
            providerClass = providerClass,
            requestCode = requestCode,
        )
        return appWidgetManager.requestPinAppWidget(provider, null, successCallback)
    }

    fun returnToHomeScreen(context: Context) {
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
                )
            }
            context.startActivity(homeIntent)
        } catch (_: Exception) {
            // 无法回桌面时静默忽略，避免影响 pin 成功回调。
        }
    }

    fun resolveProviderClass(className: String?): Class<out AppWidgetProvider>? {
        if (className.isNullOrBlank()) {
            return null
        }

        return try {
            Class.forName(className).asSubclass(AppWidgetProvider::class.java)
        } catch (_: ClassNotFoundException) {
            null
        } catch (_: ClassCastException) {
            null
        }
    }

    private fun buildSuccessCallback(
        context: Context,
        providerClass: Class<out AppWidgetProvider>,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, DoorWidgetPinReceiver::class.java).apply {
            action = actionPinSuccess
            putExtra(extraProviderClassName, providerClass.name)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Android 15+ 优先推送 generated preview，低版本继续走 previewLayout/previewImage 兜底。
     */
    private fun pushGeneratedPreviewIfSupported(
        context: Context,
        providerClass: Class<out AppWidgetProvider>,
        previewLayoutResId: Int,
    ) {
        if (Build.VERSION.SDK_INT < 35) {
            return
        }

        try {
            val method = AppWidgetManager::class.java.methods.firstOrNull { candidate ->
                candidate.name == "setWidgetPreview" &&
                    candidate.parameterTypes.size == 3 &&
                    candidate.parameterTypes[0] == ComponentName::class.java &&
                    candidate.parameterTypes[1] == Int::class.javaPrimitiveType &&
                    candidate.parameterTypes[2] == RemoteViews::class.java
            } ?: return

            method.invoke(
                AppWidgetManager.getInstance(context),
                ComponentName(context, providerClass),
                AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
                RemoteViews(context.packageName, previewLayoutResId),
            )
        } catch (_: Throwable) {
            // 预览推送失败时退回到 provider xml 中的 previewLayout / previewImage。
        }
    }
}
