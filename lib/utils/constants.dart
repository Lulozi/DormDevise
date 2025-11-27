// 应用程序中用于选择器和布局边距的通用视觉常量。
// 将这些常量保留在此处，以便 UI 保持一致并可从单一位置进行调整。

const double kPickerItemExtent = 44.0;
const double kPickerFontScale = 2.0;
const double kPickerFontSizeDefault = 24.0; // 在无法获取主题基础大小时使用
const double kTimePickerFontSize = 40.0; // 时间选择器（小时/分钟）

const double kPickerDefaultGap = 12.0;
const double kPickerOuterGapScale = 3.0; // 外部间距 = 间距 * 比例

const double kMinYearWidth = 80.0;
const double kMinMonthWidth = 64.0;
const double kMinDayWidth = 64.0;

// 时间选择器宽度的约束
const double kTimePickerMinWidth = 48.0;
const double kPickerWidthScaleSmall = 1.3;
const double kPickerWidthScaleMedium = 1.6;
const double kPickerWidthScaleLarge = 2.4;

// 其他选择器的最小尺寸
const double kMinPickerColumnWidth = 24.0;

// 注意：
// 如果需要集中管理其他视觉常量（例如填充、部分高度），
// 请考虑将它们移至 AppTheme 或中央设计系统文件，而不是 utils。
