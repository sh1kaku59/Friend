import 'package:flutter/material.dart';
import '../../services/friend_service.dart';
import '../../models/user_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  _FriendRequestsScreenState createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final FriendService _friendService = FriendService();
  String? currentUserId;
  List<UserModel> friendRequests = [];

  @override
  void initState() {
    super.initState();
    _getCurrentUserId();
  }

  /// Lấy ID của người dùng hiện tại
  void _getCurrentUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        currentUserId = user.uid;
        _fetchFriendRequests();
      });
    }
  }

  /// Lấy danh sách lời mời kết bạn
  void _fetchFriendRequests() async {
    if (currentUserId == null) return;
    List<String> requestIds = await _friendService.getFriendRequests(
      currentUserId!,
    );

    List<UserModel> requests = [];
    for (String requestId in requestIds) {
      final snapshot =
          await FirebaseDatabase.instance.ref().child("users/$requestId").get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        requests.add(UserModel.fromMap(requestId, data));
      }
    }

    setState(() {
      friendRequests = requests;
    });
  }

  /// Chấp nhận lời mời kết bạn
  void _acceptRequest(String senderUid) async {
    if (currentUserId == null) return;
    try {
      await _friendService.acceptFriendRequest(senderUid, currentUserId!);
      setState(() {
        friendRequests.removeWhere((user) => user.uid == senderUid);
      });
      _showDialog("Đã kết bạn thành công!");
    } catch (e) {
      print("Lỗi khi chấp nhận kết bạn: $e");
    }
  }

  /// Từ chối lời mời kết bạn
  void _rejectRequest(String friendId) async {
    if (currentUserId == null) return;
    await _friendService.rejectFriendRequest(currentUserId!, friendId);
    setState(() {
      friendRequests.removeWhere((user) => user.uid == friendId);
    });
    _showDialog("Đã từ chối lời mời kết bạn!");
  }

  /// Hiển thị thông báo
  void _showDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true, // Cho phép đóng khi nhấn bên ngoài
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 16,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 50),
                SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    "OK",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(80),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          "Lời mời kết bạn",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 48), // Để căn giữa tiêu đề
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body:
          friendRequests.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      "assets/background_notification.png",
                      width: 200,
                      height: 200,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Không có lời mời kết bạn nào!",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : Padding(
                padding: const EdgeInsets.only(
                  top: 16.0,
                ), // Thêm khoảng cách phía trên
                child: ListView.builder(
                  itemCount: friendRequests.length,
                  itemBuilder: (context, index) {
                    final user = friendRequests[index];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              user.avatarUrl != null &&
                                      user.avatarUrl!.startsWith("http")
                                  ? NetworkImage(user.avatarUrl!)
                                  : AssetImage("assets/default_avatar.png")
                                      as ImageProvider,
                          radius: 25,
                        ),
                        title: Text(
                          user.username,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(user.email),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.check, color: Colors.green),
                              onPressed: () => _acceptRequest(user.uid),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rejectRequest(user.uid),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
    );
  }
}
