// lib/services/call_service.dart
import 'package:firebase_database/firebase_database.dart';
// import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class CallService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Biến này sẽ chứa địa chỉ API backend thực tế
  late final String _livekitTokenApiUrl;

  CallService() {
    // Khởi tạo _livekitTokenApiUrl dựa trên môi trường
    if (kIsWeb) {
      // Nếu chạy trên Web (trên cùng máy với Node.js server)
      _livekitTokenApiUrl = 'http://localhost:3000/get-livekit-token';
    } else if (Platform.isAndroid) {
      // Nếu chạy trên Android
      // 10.0.2.2 là địa chỉ IP đặc biệt để truy cập localhost của máy tính từ Android Emulator
      // THAY THẾ 'YOUR_LOCAL_IP_ADDRESS' BẰNG ĐỊA CHỈ IP CỤC BỘ CỦA MÁY TÍNH CỦA BẠN
      // Ví dụ: 'http://192.168.1.100:3000/get-livekit-token'
      // Để tìm địa chỉ IP cục bộ của bạn, mở Command Prompt/Terminal và gõ:
      // - Windows: ipconfig
      // - macOS/Linux: ifconfig hoặc ip a
      _livekitTokenApiUrl =
          'http://10.0.2.2:3000/get-livekit-token'; // Dành cho Emulator
      // Nếu bạn muốn dùng địa chỉ IP cục bộ cho cả emulator và thiết bị vật lý, hãy uncomment dòng dưới và thay địa chỉ IP:
      // _livekitTokenApiUrl = 'http://YOUR_LOCAL_IP_ADDRESS:3000/get-livekit-token';
    } else {
      // Đối với các nền tảng khác (iOS, Desktop), bạn có thể cấu hình riêng hoặc sử dụng localhost nếu backend chạy cùng máy
      _livekitTokenApiUrl = 'http://localhost:3000/get-livekit-token';
    }
  }

  // Khởi tạo cuộc gọi
  Future<String> initiateCall({
    required String callerId,
    required String receiverId,
    required String type,
  }) async {
    try {
      // Kiểm tra xem có cuộc gọi đang diễn ra không
      final existingCall =
          await _database
              .child('calls')
              .orderByChild('status')
              .equalTo('accepted')
              .get();

      if (existingCall.exists) {
        final calls = existingCall.value as Map;
        final hasActiveCall = calls.values.any(
          (call) =>
              (call['callerId'] == callerId ||
                  call['receiverId'] == callerId) &&
              call['status'] == 'accepted',
        );

        if (hasActiveCall) {
          throw Exception('User is already in a call');
        }
      }

      final callId = _database.child('calls').push().key!;
      final roomId = 'room_$callId';

      final callerInfo = await getCallerInfo(callerId);

      await _database.child('calls/$callId').set({
        'callerId': callerId,
        'receiverId': receiverId,
        'status': 'pending',
        'type': type,
        'roomId': roomId,
        'startTime': ServerValue.timestamp,
        'callerName': callerInfo['username'],
        'callerAvatar': callerInfo['avatar'] ?? '',
      });

      // Cập nhật trạng thái người gọi
      await _database.child('users/$callerId').update({
        'inCall': true,
        'lastOnline': ServerValue.timestamp,
      });

      return callId;
    } catch (e) {
      print('Error initiating call: $e');
      throw Exception('Failed to initiate call');
    }
  }

  // Cập nhật trạng thái cuộc gọi
  Future<void> updateCallStatus(String callId, String status) async {
    await _database.child('calls/$callId').update({
      'status': status,
      if (status == 'ended') 'endTime': ServerValue.timestamp,
    });
  }

  // Lắng nghe cuộc gọi đến
  Stream<DatabaseEvent> listenToIncomingCalls(String userId) {
    return _database
        .child('calls')
        .orderByChild('receiverId')
        .equalTo(userId)
        .onValue;
  }

  Future<Map<String, dynamic>> getCallerInfo(String callerId) async {
    try {
      final snapshot = await _database.child('users/$callerId').get();
      if (!snapshot.exists) {
        throw Exception('User not found');
      }
      return Map<String, dynamic>.from(snapshot.value as Map);
    } catch (e) {
      print('Error getting caller info: $e');
      throw Exception('Failed to get caller information');
    }
  }

  Future<String> getLiveKitToken(String roomId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse(_livekitTokenApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'roomId': roomId}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        // In ra toàn bộ dữ liệu nhận được để debug
        print('LiveKit Token API Response Status: ${response.statusCode}');
        print('LiveKit Token API Response Body: ${response.body}');
        print('Parsed data: $data');

        // Kiểm tra xem khóa 'token' có tồn tại và giá trị của nó có phải là String không
        if (data.containsKey('token') && data['token'] is String) {
          return data['token'] as String;
        } else {
          // Báo lỗi cụ thể nếu định dạng token không đúng
          throw Exception(
            'Invalid token format from API. Expected a string \'token\', but received: ${data['token']} (Type: ${data['token'].runtimeType})',
          );
        }
      } else {
        // Log phản hồi lỗi từ server nếu status không phải 200
        print('LiveKit Token API Error Status: ${response.statusCode}');
        print('LiveKit Token API Error Body: ${response.body}');
        throw Exception(
          'Failed to get LiveKit token. Status: ${response.statusCode}, Body: ${response.body}',
        );
      }
    } catch (e) {
      // In ra lỗi mạng hoặc lỗi phân tích cú pháp JSON
      print('Network or JSON Parsing Error in getLiveKitToken: $e');
      throw Exception(
        'Failed to get LiveKit token due to network or parsing issue: $e',
      );
    }
  }

  Future<void> handleCallEnded(String callId) async {
    try {
      final callSnapshot = await _database.child('calls/$callId').get();
      if (!callSnapshot.exists) return;

      final callData = callSnapshot.value as Map<dynamic, dynamic>;
      final callerId = callData['callerId'];
      final receiverId = callData['receiverId'];

      await _database.child('calls/$callId').update({
        'status': 'ended',
        'endTime': ServerValue.timestamp,
      });

      // Đảm bảo cập nhật trạng thái inCall của cả hai người dùng
      await Future.wait([
        _database.child('users/$callerId').update({
          'inCall': false,
          'lastOnline': ServerValue.timestamp,
        }),
        _database.child('users/$receiverId').update({
          'inCall': false,
          'lastOnline': ServerValue.timestamp,
        }),
      ]);

      // Xóa cuộc gọi sau 5 phút (có thể điều chỉnh thời gian này)
      Future.delayed(Duration(minutes: 5), () async {
        await _database.child('calls/$callId').remove();
      });
    } catch (e) {
      print('Error handling call end: $e');
      throw Exception('Failed to handle call end properly');
    }
  }

  Stream<DatabaseEvent> listenToCallStatus(String callId) {
    return _database.child('calls/$callId').onValue;
  }

  Future<bool> isUserInCall(String userId) async {
    final snapshot =
        await _database
            .child('calls')
            .orderByChild('status')
            .equalTo('accepted')
            .get();

    if (!snapshot.exists) return false;

    final calls = snapshot.value as Map<dynamic, dynamic>;
    return calls.values.any(
      (call) =>
          (call['callerId'] == userId || call['receiverId'] == userId) &&
          call['status'] == 'accepted',
    );
  }
}
