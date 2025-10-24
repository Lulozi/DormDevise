package com.lulo.dormdevise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

/**
 * 简单的广播接收器，用于捕获安装/替换完成的广播，并通过回调传回包名。
 */
class PackageInstallReceiver(
    private val onPackageInstalled: (String) -> Unit
) : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        try {
            if (intent == null) return
            val action = intent.action
            if (action == Intent.ACTION_PACKAGE_ADDED || action == Intent.ACTION_PACKAGE_REPLACED) {
                val data: Uri? = intent.data
                val pkg = data?.schemeSpecificPart
                if (pkg != null) {
                    onPackageInstalled(pkg)
                    Log.d("PackageInstallReceiver", "Package installed: $pkg")
                }
            }
        } catch (e: Exception) {
            Log.e("PackageInstallReceiver", "onReceive error", e)
        }
    }
}
