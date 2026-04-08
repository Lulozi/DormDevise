package com.lulo.dormdevise

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.appwidget.AppWidgetProviderInfo
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.RemoteViews
import java.util.Locale

/**
 * 统一处理桌面组件的 pin 请求、预览推送和成功后的回桌面逻辑。
 */
object DoorWidgetPinRequestHelper {
    const val actionPinSuccess = "com.lulo.dormdevise.action.DOOR_WIDGET_PIN_SUCCESS"
    const val extraProviderClassName = "providerClassName"
    private const val fallbackTypeNone = "none"
    private const val fallbackTypePermission = "permission"
    private const val fallbackTypeHomeScreen = "home_screen"
    private const val fallbackTypeAppDetails = "app_details"

    private data class PinRequestResult(
        val requestAccepted: Boolean,
        val pinSupported: Boolean,
        val fallbackOpened: Boolean,
        val fallbackType: String,
        val manufacturer: String,
        val brand: String,
        val launcherPackage: String?,
    ) {
        fun toMap(): Map<String, Any?> = hashMapOf(
            "requestAccepted" to requestAccepted,
            "pinSupported" to pinSupported,
            "fallbackOpened" to fallbackOpened,
            "fallbackType" to fallbackType,
            "manufacturer" to manufacturer,
            "brand" to brand,
            "launcherPackage" to launcherPackage,
        )
    }

    private data class PinFallbackResult(
        val opened: Boolean,
        val type: String,
    )

    fun requestPin(
        activity: Activity,
        providerClass: Class<out AppWidgetProvider>,
        previewLayoutResId: Int,
        requestCode: Int,
    ): Map<String, Any?> {
        val manufacturer = Build.MANUFACTURER.orEmpty()
        val brand = Build.BRAND.orEmpty()
        val launcherPackage = resolveLauncherPackage(activity)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return PinRequestResult(
                requestAccepted = false,
                pinSupported = false,
                fallbackOpened = false,
                fallbackType = fallbackTypeNone,
                manufacturer = manufacturer,
                brand = brand,
                launcherPackage = launcherPackage,
            ).toMap()
        }

        val appWidgetManager = activity.getSystemService(AppWidgetManager::class.java)
            ?: return PinRequestResult(
                requestAccepted = false,
                pinSupported = false,
                fallbackOpened = false,
                fallbackType = fallbackTypeNone,
                manufacturer = manufacturer,
                brand = brand,
                launcherPackage = launcherPackage,
            ).toMap()
        val pinSupported = appWidgetManager.isRequestPinAppWidgetSupported
        if (pinSupported) {
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
            val requestAccepted = appWidgetManager.requestPinAppWidget(provider, null, successCallback)
            if (requestAccepted) {
                return PinRequestResult(
                    requestAccepted = true,
                    pinSupported = true,
                    fallbackOpened = false,
                    fallbackType = fallbackTypeNone,
                    manufacturer = manufacturer,
                    brand = brand,
                    launcherPackage = launcherPackage,
                ).toMap()
            }
        }

        val fallback = openPinFallback(
            activity = activity,
            manufacturer = manufacturer,
        )
        return PinRequestResult(
            requestAccepted = false,
            pinSupported = pinSupported,
            fallbackOpened = fallback.opened,
            fallbackType = fallback.type,
            manufacturer = manufacturer,
            brand = brand,
            launcherPackage = launcherPackage,
        ).toMap()
    }

    private fun openPinFallback(
        activity: Activity,
        manufacturer: String,
    ): PinFallbackResult {
        if (isVivoFamilyDevice(manufacturer)) {
            openVivoPermissionPage(activity)?.let { return it }
            if (openAppDetailsPage(activity)) {
                return PinFallbackResult(
                    opened = true,
                    type = fallbackTypeAppDetails,
                )
            }
        }

        activity.moveTaskToBack(true)
        returnToHomeScreen(activity)
        return PinFallbackResult(
            opened = true,
            type = fallbackTypeHomeScreen,
        )
    }

    private fun isVivoFamilyDevice(manufacturer: String): Boolean {
        val normalizedManufacturer = manufacturer.lowercase(Locale.ROOT)
        val normalizedBrand = Build.BRAND.orEmpty().lowercase(Locale.ROOT)
        return normalizedManufacturer.contains("vivo") ||
            normalizedManufacturer.contains("iqoo") ||
            normalizedBrand.contains("vivo") ||
            normalizedBrand.contains("iqoo")
    }

    private fun openVivoPermissionPage(activity: Activity): PinFallbackResult? {
        val candidateIntents = listOf(
            Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.SoftPermissionDetailActivity",
                )
                putExtra("packagename", activity.packageName)
                putExtra("packageName", activity.packageName)
            },
            Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.PurviewTabActivity",
                )
                putExtra("packagename", activity.packageName)
                putExtra("packageName", activity.packageName)
            },
            Intent().apply {
                component = ComponentName(
                    "com.bbk.launcher2",
                    "com.bbk.launcher2.installshortcut.PurviewActivity",
                )
            },
        )
        val opened = candidateIntents.any { intent -> openIntentSafely(activity, intent) }
        return if (opened) {
            PinFallbackResult(
                opened = true,
                type = fallbackTypePermission,
            )
        } else {
            null
        }
    }

    private fun openAppDetailsPage(activity: Activity): Boolean = openIntentSafely(
        activity = activity,
        intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", activity.packageName, null)
        },
    )

    private fun openIntentSafely(
        activity: Activity,
        intent: Intent,
    ): Boolean {
        return try {
            if (intent.resolveActivity(activity.packageManager) == null) {
                false
            } else {
                activity.startActivity(intent)
                true
            }
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
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

    private fun resolveLauncherPackage(context: Context): String? {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        return homeIntent.resolveActivity(context.packageManager)
            ?.takeUnless { it.packageName == "android" }
            ?.packageName
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
