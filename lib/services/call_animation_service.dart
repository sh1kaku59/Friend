import 'package:flutter_vibrate/flutter_vibrate.dart';
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

    if (await Vibrate.canVibrate) {
      _isVibrating = true;
      // Rung mỗi 2 giây
      _vibrationTimer = Timer.periodic(Duration(seconds: 2), (timer) {
        Vibrate.feedback(FeedbackType.warning);
      });
    }
  }

  void stopVibration() {
    _vibrationTimer?.cancel();
    _isVibrating = false;
  }

  void dispose() {
    stopVibration();
  }
}
