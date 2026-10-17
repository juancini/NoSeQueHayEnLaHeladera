import 'dart:typed_data';

class DrawingPng {
  static bool hasVisiblePixels(Uint8List rgbaPixels) {
    if (rgbaPixels.length % 4 != 0) {
      throw const FormatException('RGBA pixel data is incomplete');
    }
    for (var alphaIndex = 3; alphaIndex < rgbaPixels.length; alphaIndex += 4) {
      if (rgbaPixels[alphaIndex] != 0) return true;
    }
    return false;
  }
}
