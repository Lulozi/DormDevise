package com.lulo.dormdevise.crop

import android.content.Context
import android.util.AttributeSet
import android.widget.FrameLayout
import com.lulo.dormdevise.R
import com.yalantis.ucrop.view.GestureCropImageView

/**
 * 重置按钮容器：保留 uCrop 原有“回正角度”逻辑，同时补充“缩放归位”。
 */
class UCropResetAllButtonLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    override fun setOnClickListener(listener: OnClickListener?) {
        if (listener == null) {
            super.setOnClickListener(null)
            return
        }

        super.setOnClickListener { view ->
            // 先执行 uCrop 默认重置旋转，再补充缩放归位。
            listener.onClick(view)
            resetScaleToInitial()
        }
    }

    private fun resetScaleToInitial() {
        val cropImageView = rootView.findViewById<GestureCropImageView?>(R.id.image_view_crop)
            ?: return

        // 将缩放回到初始最小值，并重新贴合裁剪框。
        val targetScale = cropImageView.minScale
        val centerX = cropImageView.width / 2f
        val centerY = cropImageView.height / 2f
        cropImageView.zoomOutImage(targetScale, centerX, centerY)
        cropImageView.setImageToWrapCropBounds()
    }
}