import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';

class Signaling {
  RTCPeerConnection? peerConnection;
  MediaStream? _localStream;
  MediaStream? remoteStream;
  String? appointmentId;

  final _configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  static const String CALL_STATUS_RINGING = 'ringing';
  static const String CALL_STATUS_ACCEPTED = 'accepted';
  static const String CALL_STATUS_REJECTED = 'rejected';
  static const String CALL_STATUS_ENDED = 'ended';
  static const String CALL_STATUS_BUSY = 'busy';

  final _callStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callStateStream =>
      _callStateController.stream;
  String? _localUuid;
  StreamSubscription? _callSubscription;

  // Thêm các biến để theo dõi trạng thái cuộc gọi
  int _callDuration = 0;
  bool _isCallAccepted = false;
  Timer? _callDurationTimer;

  Future<void> initiateCall(String callerId, String receiverId) async {
    try {
      print("Initiating call from $callerId to $receiverId");

      // Kiểm tra xem người nhận có chặn người gọi không
      bool isBlocked = await isUserBlocked(callerId, receiverId);
      if (isBlocked) {
        throw Exception('Bạn không thể gọi cho người dùng này vì đã bị chặn');
      }

      // Kiểm tra xem người gọi có bị người nhận chặn không
      bool isBlockedByReceiver = await isUserBlocked(receiverId, callerId);
      if (isBlockedByReceiver) {
        throw Exception('Bạn không thể gọi cho người dùng này');
      }

      // Check for existing calls first
      final existingCallsSnapshot =
          await FirebaseDatabase.instance
              .ref('calls')
              .orderByChild('status')
              .equalTo('ringing')
              .get();

      if (existingCallsSnapshot.exists) {
        final calls = existingCallsSnapshot.value as Map;
        for (var call in calls.values) {
          if ((call['callerId'] == callerId &&
                  call['receiverId'] == receiverId) ||
              (call['callerId'] == receiverId &&
                  call['receiverId'] == callerId)) {
            print("Found existing active call between these users");
            throw Exception(
              'There is already an active call between these users',
            );
          }
        }
      }

      // Request permissions
      Map<Permission, PermissionStatus> statuses =
          await [Permission.camera, Permission.microphone].request();

      if (statuses[Permission.camera]!.isDenied ||
          statuses[Permission.microphone]!.isDenied) {
        throw Exception('Camera and Microphone permissions are required');
      }

      // Create appointment ID
      appointmentId = DateTime.now().millisecondsSinceEpoch.toString();
      print("Created appointment ID: $appointmentId");

      // Create peer connection
      peerConnection = await createPeerConnection(_configuration);
      print("Created peer connection");

      // Add local stream with explicit constraints
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'optional': []},
      });
      print("Got local stream");

      _localStream!.getTracks().forEach((track) {
        peerConnection!.addTrack(track, _localStream!);
      });
      print("Added local tracks to peer connection");

      // Listen for remote stream
      peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          _callStateController.add({
            'event': 'call_accepted',
            'remoteStream': remoteStream,
          });
        }
      };

      // Create and set local description
      final offer = await peerConnection!.createOffer();
      await peerConnection!.setLocalDescription(offer);
      print("Created and set local description");

      // Lấy thông tin người gọi
      final callerData = await getUserData(callerId);
      if (callerData == null) {
        throw Exception('Không tìm thấy thông tin người gọi');
      }

      // Save call data to database
      await FirebaseDatabase.instance.ref('calls/$appointmentId').set({
        'callerId': callerId,
        'receiverId': receiverId,
        'status': 'ringing',
        'offer': offer.sdp,
        'type': offer.type,
        'created': ServerValue.timestamp,
        'callerName': callerData['username'],
        'callerAvatar': callerData['avatar'],
        'accepted': false,
        'duration': 0,
      });
      print("Saved call data to database");

      // Bắt đầu đếm thời gian cuộc gọi khi được chấp nhận
      FirebaseDatabase.instance.ref('calls/$appointmentId').onValue.listen((
        event,
      ) {
        if (event.snapshot.value == null) return;

        final data = event.snapshot.value as Map<dynamic, dynamic>;
        if (data['status'] == 'accepted' && !_isCallAccepted) {
          _isCallAccepted = true;
          _startCallDurationTimer();
        }
      });
    } catch (e) {
      print("Error in initiateCall: $e");
      rethrow;
    }
  }

  Future<void> acceptCall(String appointmentId) async {
    try {
      print("Accepting call for appointment: $appointmentId");
      this.appointmentId = appointmentId;

      // Request permissions first
      Map<Permission, PermissionStatus> statuses =
          await [Permission.camera, Permission.microphone].request();

      if (statuses[Permission.camera]!.isDenied ||
          statuses[Permission.microphone]!.isDenied) {
        throw Exception('Camera and Microphone permissions are required');
      }

      // Get call data
      final callSnapshot =
          await FirebaseDatabase.instance.ref('calls/$appointmentId').get();
      if (!callSnapshot.exists) {
        throw Exception('Call not found');
      }

      final callData = callSnapshot.value as Map<dynamic, dynamic>;
      print("Got call data");

      // Create peer connection
      peerConnection = await createPeerConnection(_configuration);
      print("Created peer connection");

      // Add local stream with explicit constraints
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'optional': []},
      });
      print("Got local stream");

      _localStream!.getTracks().forEach((track) {
        peerConnection!.addTrack(track, _localStream!);
      });
      print("Added local tracks to peer connection");

      // Listen for remote stream
      peerConnection!.onTrack = (event) {
        print("Received remote track");
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
        }
      };

      // Set remote description
      final offer = RTCSessionDescription(callData['offer'], callData['type']);
      await peerConnection!.setRemoteDescription(offer);
      print("Set remote description");

      // Create and set local description
      final answer = await peerConnection!.createAnswer();
      await peerConnection!.setLocalDescription(answer);
      print("Created and set local description");

      // Update call status
      await FirebaseDatabase.instance.ref('calls/$appointmentId').update({
        'status': 'accepted',
        'answer': answer.sdp,
        'answerType': answer.type,
        'accepted': true,
      });

      // Bắt đầu đếm thời gian cuộc gọi
      _isCallAccepted = true;
      _startCallDurationTimer();

      print("Updated call status to accepted");
    } catch (e) {
      print("Error in acceptCall: $e");
      rethrow;
    }
  }

  Future<void> endCall() async {
    try {
      print("Ending call for appointment: $appointmentId");

      // Dừng timer đếm thời gian
      _callDurationTimer?.cancel();

      if (appointmentId != null) {
        await FirebaseDatabase.instance.ref('calls/$appointmentId').update({
          'status': 'ended',
          'endedAt': ServerValue.timestamp,
          'duration': _callDuration,
          'accepted': _isCallAccepted,
        });
      }

      // Reset các biến theo dõi trạng thái
      _callDuration = 0;
      _isCallAccepted = false;

      await _callSubscription?.cancel();
      _callSubscription = null;

      _localStream?.getTracks().forEach((track) => track.stop());
      if (peerConnection != null) {
        await peerConnection!.close();
        peerConnection = null;
      }

      _localStream = null;
      remoteStream = null;

      _callStateController.add({
        'event': 'call_ended',
        'message': 'Cuộc gọi đã kết thúc',
      });

      print("Call ended successfully");
    } catch (e) {
      print("Error in endCall: $e");
      rethrow;
    }
  }

  Future<void> rejectCall(String appointmentId) async {
    await FirebaseDatabase.instance.ref('calls/$appointmentId').update({
      'status': CALL_STATUS_REJECTED,
    });
    await endCall();
  }

  void _listenForCallUpdates(String callId, RTCPeerConnection pc) {
    _callSubscription = FirebaseDatabase.instance
        .ref('calls/$callId')
        .onValue
        .listen((event) async {
          if (event.snapshot.value == null) return;

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          switch (data['status']) {
            case CALL_STATUS_ENDED:
              _callStateController.add({'event': 'call_ended'});
              await endCall();
              break;
            case CALL_STATUS_REJECTED:
              _callStateController.add({'event': 'call_rejected'});
              await endCall();
              break;
          }
        });
  }

  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final snapshot =
          await FirebaseDatabase.instance.ref("users/$userId").get();
      if (!snapshot.exists) {
        throw Exception("User $userId not found");
      }
      final data = snapshot.value as Map<dynamic, dynamic>;
      return {
        "username": data["username"] ?? "Unknown User",
        "email": data["email"] ?? "",
        "avatar": data["avatar"] ?? "",
        "online": data["online"] ?? false,
      };
    } catch (e) {
      print("Error getting user data: $e");
      return null;
    }
  }

  Future<void> openUserMedia() async {
    try {
      // Kiểm tra và yêu cầu quyền trước
      await Permission.microphone.request();
      if (await Permission.microphone.isGranted) {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {'facingMode': 'user', 'optional': []},
        });
        _localStream!.getTracks().forEach((track) {
          peerConnection!.addTrack(track, _localStream!);
        });
      } else {
        throw Exception('Microphone permission not granted');
      }
    } catch (e) {
      throw Exception('Error accessing media devices: $e');
    }
  }

  Future<void> startCall(String callerId, String receiverId) async {
    appointmentId = const Uuid().v1(); // tạo id mới cho cuộc gọi
    _localUuid = callerId;

    if (_localStream == null) {
      throw Exception(
        "Local stream is not initialized. Call openUserMedia() first.",
      );
    }

    // Lấy thông tin người gọi và người nhận từ Firebase Realtime Database
    final callerData = await getUserData(callerId);
    final receiverData = await getUserData(receiverId);

    if (callerData == null || receiverData == null) {
      throw Exception("Không tìm thấy thông tin người gọi hoặc người nhận.");
    }

    // Gửi lời mời (offer)
    final pc = await _createPeerConnection(_localUuid!);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    await FirebaseDatabase.instance.ref('calls/$appointmentId').set({
      'offer': offer.toMap(),
      'callerId': callerId,
      'callerName': callerData['username'],
      'callerAvatar': callerData['avatar'],
      'receiverId': receiverId,
      'receiverName': receiverData['username'],
      'receiverAvatar': receiverData['avatar'],
      'status': 'ringing', // Trạng thái cuộc gọi
    });

    // Lắng nghe trạng thái cuộc gọi
    _callSubscription = FirebaseDatabase.instance
        .ref('calls/$appointmentId')
        .onValue
        .listen((event) async {
          if (event.snapshot.value != null) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            if (data['status'] == 'accepted') {
              // Người nhận đã chấp nhận cuộc gọi
              final answer = data['answer'];
              await pc.setRemoteDescription(
                RTCSessionDescription(answer['sdp'], answer['type']),
              );
            } else if (data['status'] == 'rejected') {
              // Người nhận từ chối cuộc gọi
              await endCall();
            }
          }
        });
  }

  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final pc = await createPeerConnection(_configuration);

    // Thêm local stream vào kết nối
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    peerConnection = pc;
    return pc;
  }

  Future<bool> isUserBlocked(String callerId, String receiverId) async {
    try {
      // Kiểm tra xem người nhận có chặn người gọi không
      final blockedSnapshot =
          await FirebaseDatabase.instance
              .ref('blocked_users/$receiverId/$callerId')
              .get();

      if (blockedSnapshot.exists) {
        final blockData = blockedSnapshot.value as Map<dynamic, dynamic>;
        return blockData['status'] == 'blocked';
      }

      return false;
    } catch (e) {
      print('Lỗi khi kiểm tra người dùng bị chặn: $e');
      return false;
    }
  }

  // Thêm hàm để đếm thời gian cuộc gọi
  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _callDuration++;
    });
  }

  // Thêm hàm dispose để cleanup
  void dispose() {
    _callDurationTimer?.cancel();
    _callDuration = 0;
    _isCallAccepted = false;
  }
}
