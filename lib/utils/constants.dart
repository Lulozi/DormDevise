// Common visual constants used for pickers and layout margins across the app.
// Keep these here so the UI is consistent and tuneable from a single place.

const double kPickerItemExtent = 44.0;
const double kPickerFontScale = 2.0;
const double kPickerFontSizeDefault =
    24.0; // used where theme base-size isn't available
const double kTimePickerFontSize = 40.0; // time pickers (hours/minutes)

const double kPickerDefaultGap = 12.0;
const double kPickerOuterGapScale = 3.0; // outerGap = gap * scale

const double kMinYearWidth = 80.0;
const double kMinMonthWidth = 64.0;
const double kMinDayWidth = 64.0;

// Constrains for time pickers width
const double kTimePickerMinWidth = 48.0;
const double kPickerWidthScaleSmall = 1.3;
const double kPickerWidthScaleMedium = 1.6;
const double kPickerWidthScaleLarge = 2.4;

// Min sizes for other pickers
const double kMinPickerColumnWidth = 24.0;

// NOTE:
// If you need to centralize other visual constants (e.g. paddings, section heights),
// consider moving them into an AppTheme or central design system file rather than utils.
