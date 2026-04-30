/**
 * Calculate relative luminance in range 0..1. The color values r, g and b must be within the 0..255 range.
  */
function calculateLuminance(r, g, b) {
    return 0.2126 * r / 255 + 0.7152 * g / 255 + 0.0722 * b / 255;
}

export { calculateLuminance };
