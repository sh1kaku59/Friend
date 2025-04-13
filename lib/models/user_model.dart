class UserModel {
  final String uid;
  final String email;
  final String username;
  final bool online;
  final String? avatarUrl; // Thêm trường avatar
  final DateTime? lastOnline;
  final Map<String, bool> friends;
  final Map<String, bool> friendRequestsSent;
  final Map<String, bool> friendRequestsReceived;

  UserModel({
    required this.uid,
    required this.email,
    required this.username,
    required this.online,
    this.avatarUrl,
    this.lastOnline,
    required this.friends,
    required this.friendRequestsSent,
    required this.friendRequestsReceived,
  });

  UserModel copyWith({
    String? uid,
    String? email,
    String? username,
    bool? isOnline,
    String? avatarUrl,
    DateTime? lastOnline,
    Map<String, bool>? friends,
    Map<String, bool>? friendRequestsSent,
    Map<String, bool>? friendRequestsReceived,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      username: username ?? this.username,
      online: isOnline ?? online,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastOnline: lastOnline ?? this.lastOnline,
      friends: friends ?? this.friends,
      friendRequestsSent: friendRequestsSent ?? this.friendRequestsSent,
      friendRequestsReceived:
          friendRequestsReceived ?? this.friendRequestsReceived,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "email": email,
      "username": username,
      "isOnline": online,
      "avatar": avatarUrl, // Lưu avatar vào Firebase Database
      "lastOnline": lastOnline?.millisecondsSinceEpoch,
      "friends": friends,
      "requests_sent": friendRequestsSent,
      "requests_received": friendRequestsReceived,
    };
  }

  factory UserModel.fromMap(String uid, Map<dynamic, dynamic> data) {
    return UserModel(
      uid: uid,
      email: data["email"] ?? "",
      username: data["username"] ?? "Unknown",
      online: data["online"] ?? false,
      avatarUrl: data["avatar"], // Lấy ảnh đại diện từ Firebase Database
      lastOnline:
          data["lastOnline"] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                data["lastOnline"],
              ) // 🕒 Chuyển timestamp thành DateTime
              : null,
      friends: Map<String, bool>.from(data["friends"] ?? {}),
      friendRequestsSent: Map<String, bool>.from(data["requests_sent"] ?? {}),
      friendRequestsReceived: Map<String, bool>.from(
        data["requests_received"] ?? {},
      ),
    );
  }
}
