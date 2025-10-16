import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui show Size;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart' show CameraImage, Plane;

InputImage inputImageFromCameraImage(CameraImage image, int rotationDegrees) {
  final bytes = _concatenatePlanes(image.planes);
  final format = Platform.isIOS
      ? InputImageFormat.bgra8888
      : InputImageFormat.yuv420; // Android must use yuv420

  final metadata = InputImageMetadata(
    size: ui.Size(image.width.toDouble(), image.height.toDouble()),
    rotation: _rotationFromDegrees(rotationDegrees),
    format: format,
    bytesPerRow: image.planes.isNotEmpty ? image.planes.first.bytesPerRow : 0,
  );

  return InputImage.fromBytes(bytes: bytes, metadata: metadata);
}

Uint8List _concatenatePlanes(List<Plane> planes) {
  final builder = BytesBuilder(copy: false);
  for (final p in planes) {
    builder.add(p.bytes);
  }
  return builder.toBytes();
}

InputImageRotation _rotationFromDegrees(int degrees) {
  switch (degrees) {
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}
