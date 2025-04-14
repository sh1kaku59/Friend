import 'package:flutter/material.dart';
import '../../services/friend_service.dart';
import '../../models/user_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Thêm model cho thông báo cuộc gọi
class CallNotification {
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final String status; // 'missed', 'completed', 'incoming'
  final DateTime timestamp;
  final String appointmentId;
  final int
  duration; // Thời gian cuộc gọi (giây), chỉ có với cuộc gọi completed

  CallNotification({
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.status,
    required this.timestamp,
    required this.appointmentId,
    this.duration = 0,
  });

  factory CallNotification.fromMap(Map<dynamic, dynamic> map, String id) {
    return CallNotification(
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerAvatar: map['callerAvatar'] ?? '',
      status: map['status'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      appointmentId: id,
      duration: map['duration'] ?? 0,
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();
  String? currentUserId;
  List<UserModel> friendRequests = [];
  List<CallNotification> callNotifications = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getCurrentUserId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Lấy ID của người dùng hiện tại
  void _getCurrentUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        currentUserId = user.uid;
        _fetchFriendRequests();
        _fetchCallNotifications();
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

  void _fetchCallNotifications() async {
    if (currentUserId == null) return;

    final callsRef = FirebaseDatabase.instance.ref().child('calls');
    final query = callsRef
        .orderByChild('participants/${currentUserId}')
        .equalTo(true);

    query.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      final calls = <CallNotification>[];
      final data = event.snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        if (value is Map) {
          final call = CallNotification.fromMap(
            value as Map<dynamic, dynamic>,
            key,
          );
          calls.add(call);
        }
      });

      // Sắp xếp theo thời gian mới nhất
      calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        callNotifications = calls;
      });
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

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  Widget _buildCallIcon(String status) {
    IconData iconData;
    Color iconColor;

    switch (status) {
      case 'missed':
        iconData = Icons.call_missed;
        iconColor = Colors.red;
        break;
      case 'completed':
        iconData = Icons.call_made;
        iconColor = Colors.green;
        break;
      case 'incoming':
        iconData = Icons.call_received;
        iconColor = Colors.blue;
        break;
      default:
        iconData = Icons.call;
        iconColor = Colors.grey;
    }

    return Icon(iconData, color: iconColor);
  }

  Widget _buildFriendRequestsList() {
    if (friendRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/background_notification.png",
              width: 200,
              height: 200,
            ),
            SizedBox(height: 20),
            Text(
              "Không có lời mời kết bạn nào!",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(height: 16),
        Expanded(
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
      ],
    );
  }

  Widget _buildCallList() {
    if (callNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color.fromARGB(
                  255,
                  255,
                  255,
                  255,
                )?.withOpacity(0.1),
              ),
              child: Icon(
                Icons.phone_missed,
                size: 120,
                color: Colors.blue[400],
              ),
            ),
            SizedBox(height: 16),
            Text(
              "Không có cuộc gọi nào!",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: callNotifications.length,
            itemBuilder: (context, index) {
              final call = callNotifications[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(call.callerAvatar),
                    radius: 25,
                  ),
                  title: Text(
                    call.callerName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Row(
                    children: [
                      _buildCallIcon(call.status),
                      SizedBox(width: 8),
                      Text(_formatTimestamp(call.timestamp)),
                      if (call.status == 'completed') ...[
                        Text(' • '),
                        Text(_formatDuration(call.duration)),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.call, color: Colors.blue),
                    onPressed: () {
                      // Xử lý gọi lại
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(130),
        child: Material(
          elevation: 6,
          child: Container(
            decoration: BoxDecoration(color: Colors.blue),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
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
                              "Thông báo",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 48),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(
                        text: 'Lời mời kết bạn',
                        icon: Icon(Icons.person_add),
                      ),
                      Tab(text: 'Cuộc gọi', icon: Icon(Icons.call)),
                    ],
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    dividerColor: Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFriendRequestsList(), _buildCallList()],
      ),
    );
  }
}
