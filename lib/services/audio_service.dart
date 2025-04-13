import 'package:just_audio/just_audio.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  Future<void> playRingtone() async {
    if (_isPlaying) return;

    try {
      _isPlaying = true;
      await _player.setAsset('assets/sounds/ringtone.mp3');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      print('Error playing ringtone: $e');
      _isPlaying = false;
    }
  }

  Future<void> stopRingtone() async {
    if (!_isPlaying) return;

    try {
      await _player.stop();
      _isPlaying = false;
    } catch (e) {
      print('Error stopping ringtone: $e');
    }
  }

  void dispose() {
    _player.dispose();
  }
}
