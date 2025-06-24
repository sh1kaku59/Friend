import 'package:vibration/vibration.dart';
import 'dart:async';

class CallAnimationService {
  static final CallAnimationService _instance =
      CallAnimationService._internal();
  factory CallAnimationService() => _instance;
  CallAnimationService._internal();

  bool _isVibrating = false;
  Timer? _vibrationTimer;

  Future<void> startVibration() async {
    if (_isVibrating) return;

    // Kiểm tra thiết bị có hỗ trợ vibration không
    if (await Vibration.hasVibrator() ?? false) {
      _isVibrating = true;
      // Rung mỗi 2 giây với pattern: rung 500ms, nghỉ 1500ms
      _vibrationTimer = Timer.periodic(Duration(seconds: 2), (timer) {
        Vibration.vibrate(duration: 500);
      });
    }
  }

  void stopVibration() {
    _vibrationTimer?.cancel();
    Vibration.cancel(); // Dừng vibration hiện tại
    _isVibrating = false;
  }

  void dispose() {
    stopVibration();
  }
}
