import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:friend/models/user_model.dart'; // Import UserModel

class FriendService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// 🟢 Lấy danh sách bạn bè
  Future<List<String>> getFriends(String userId) async {
    final snapshot = await _db.child("friends/$userId").get();
    if (snapshot.exists) {
      return snapshot.children.map((e) => e.key!).toList();
    }
    return [];
  }

  /// 🔍 Lấy thông tin người dùng từ Firebase
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    final snapshot = await _db.child("users/$userId").get();
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;

      return {
        "username": data["username"],
        "email": data["email"],
        "avatar":
            data["avatar"] ??
            "https://yourdomain.com/avatars/default_avatar.png",
      };
    }
    return null;
  }

  /// 🔍 **Tìm kiếm người dùng theo email**
  Future<List<UserModel>> searchUsers(
    String query,
    String currentUserId,
  ) async {
    if (query.isEmpty) return [];

    final snapshot = await _db.child("users").get();
    if (!snapshot.exists) return [];

    List<UserModel> results = [];
    final data = snapshot.value as Map<dynamic, dynamic>;

    data.forEach((key, value) {
      final user = UserModel.fromMap(key, value);
      if (user.uid != currentUserId &&
          user.email.toLowerCase().contains(query.toLowerCase())) {
        results.add(user);
      }
    });

    return results;
  }

  /// **🔄 Đặt trạng thái user online/offline tự động**
  void setUserOnline(String currentUserId) {
    final userRef = _db.child("users/$currentUserId");

    _db.child(".info/connected").onValue.listen((event) {
      final isConnected = event.snapshot.value as bool? ?? false;
      if (isConnected) {
        userRef.update({"online": true});
        userRef.onDisconnect().update({
          "online": false,
          "lastOnline": DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  /// **👥 Lắng nghe danh sách bạn bè thay đổi**
  Stream<List<String>> listenToFriends(String currentUserId) {
    return _db.child("friends/$currentUserId").onValue.map((event) {
      if (event.snapshot.value == null) return [];
      Map<dynamic, dynamic> friendsMap =
          event.snapshot.value as Map<dynamic, dynamic>;
      return friendsMap.keys.cast<String>().toList();
    });
  }

  /// 🔍 Gửi yêu cầu kết bạn (tránh gửi trùng)
  Future<void> sendFriendRequest(String email) async {
    DatabaseReference usersRef = _db.child("users");

    // 🔍 In ra email cần tìm
    // print("Email tìm kiếm trước khi xử lý: $email");

    // 🛠 Kiểm tra xem email có phải là một địa chỉ email hợp lệ không
    if (!email.contains("@") || !email.contains(".")) {
      print("🚨 Email không hợp lệ: $email");
      throw Exception("Định dạng email không đúng!");
    }

    // 🔥 Chuyển email về dạng lowercase để tránh lỗi tìm kiếm
    email = email.trim().toLowerCase();

    // 🔍 Truy vấn Firebase để tìm user theo email
    DataSnapshot snapshot =
        await usersRef.orderByChild("email").equalTo(email).get();

    if (!snapshot.exists) {
      print("🚨 Không tìm thấy người dùng nào với email này trong Firebase!");
      throw Exception("Không tìm thấy người dùng với email này!");
    }

    // 📌 Lấy UID của người nhận
    String receiverUid = snapshot.children.first.key!;
    print("📌 Tìm thấy UID của người nhận: $receiverUid");

    String senderUid = FirebaseAuth.instance.currentUser!.uid;

    // ⛔ Không thể gửi yêu cầu cho chính mình
    if (receiverUid == senderUid) {
      throw Exception("Không thể gửi kết bạn cho chính mình!");
    }

    // 🔄 Kiểm tra xem đã gửi lời mời chưa
    DataSnapshot requestCheck =
        await _db
            .child("friend_requests")
            .child(receiverUid)
            .child(senderUid)
            .get();

    if (requestCheck.exists) {
      throw Exception("Bạn đã gửi lời mời kết bạn trước đó!");
    }

    // 🔄 Kiểm tra xem đã là bạn bè chưa
    DataSnapshot checkFriend =
        await _db.child("friends").child(senderUid).child(receiverUid).get();
    if (checkFriend.exists) {
      throw Exception("Hai bạn đã là bạn bè!");
    }

    // ✅ Gửi lời mời kết bạn
    await _db.child("friend_requests").child(receiverUid).child(senderUid).set({
      "status": "pending",
      "timestamp": ServerValue.timestamp,
    });

    // ✅ Lưu trạng thái đã gửi lời mời kết bạn
    await _db
        .child("users")
        .child(senderUid)
        .child("sent_requests")
        .child(receiverUid)
        .set(true);

    // print("✅ Đã gửi lời mời kết bạn!");
  }

  /// 📩 Lấy danh sách yêu cầu kết bạn đến userId
  Future<List<String>> getFriendRequests(String userId) async {
    final snapshot = await _db.child("friend_requests/$userId").get();
    if (snapshot.exists) {
      return snapshot.children.map((e) => e.key!).toList();
    }
    return [];
  }

  /// ✅ Chấp nhận lời mời kết bạn
  Future<void> acceptFriendRequest(String senderUid, String receiverUid) async {
    final database = FirebaseDatabase.instance.ref();

    try {
      // Xóa lời mời kết bạn
      await database.child("friend_requests/$receiverUid/$senderUid").remove();

      // Thêm bạn bè vào danh sách của cả hai người
      await database.child("friends/$receiverUid/$senderUid").set(true);
      await database.child("friends/$senderUid/$receiverUid").set(true);

      print("✅ Đã chấp nhận kết bạn giữa $senderUid và $receiverUid");
    } catch (e) {
      print("❌ Lỗi khi chấp nhận kết bạn: $e");
      throw Exception("Không thể chấp nhận kết bạn");
    }
  }

  /// ❌ Từ chối lời mời kết bạn
  Future<void> rejectFriendRequest(String userId, String friendId) async {
    await _db.child("friend_requests/$userId/$friendId").remove();
    print("❌ Đã từ chối lời mời kết bạn!");
  }

  /// 🚫 Xóa bạn bè
  Future<void> removeFriend(String friendId) async {
    String userId = FirebaseAuth.instance.currentUser!.uid;

    await _db.child("friends/$userId/$friendId").remove();
    await _db.child("friends/$friendId/$userId").remove();

    print("❌ Đã xóa bạn bè!");
  }

  /// 🔒 Chặn người dùng
  Future<void> blockUser(String userId, String blockedUserId) async {
    await _db.child('blocked_users/$userId/$blockedUserId').set({
      'blockedAt': ServerValue.timestamp,
      'status': 'blocked',
    });
  }

  /// �� Bỏ chặn người dùng
  Future<void> unblockUser(String userId, String blockedUserId) async {
    await _db.child('blocked_users/$userId/$blockedUserId').remove();
  }

  /// 🔍 Kiểm tra người dùng có bị chặn không
  Future<bool> isUserBlocked(String userId, String blockedUserId) async {
    final blockedSnapshot =
        await _db.child('blocked_users/$userId/$blockedUserId').get();
    return blockedSnapshot.exists;
  }
}
