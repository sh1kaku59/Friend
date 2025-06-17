import 'package:flutter/material.dart';
import '../../services/friend_service.dart';
import '../../models/user_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login_screen.dart';
import '../call/call_screen.dart';
import 'view_profile.dart';
import 'package:friend/screens/friend/notifications_screen.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'dart:io';
import 'success_dialog.dart';
import '../call/incoming_call_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/callservice.dart';

class FriendListScreen extends StatefulWidget {
  const FriendListScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _FriendListScreenState createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen> {
  final FriendService _friendService = FriendService();
  String? currentUserId;
  String? username;
  String? email;
  String? avatarUrl;
  final _searchController = TextEditingController();
  List<UserModel> searchResults = [];
  Map<String, bool> requestSent = {};
  bool showSearchResults = false;
  late DatabaseReference userRef;
  List<String> friendIds = []; // Danh sách UID bạn bè
  bool hasNewFriendRequest = false;
  // Thêm biến để lưu số lượng lời mời kết bạn
  int friendRequestCount = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode(); // Thêm FocusNode
  final CallService _callService = CallService();

  // Thêm một Map để theo dõi các cuộc gọi đến đang hiển thị IncomingCallScreen
  // Điều này giúp tránh việc đẩy nhiều IncomingCallScreen cho cùng một cuộc gọi
  final Map<String, bool> _activeIncomingCallScreens = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      // Cập nhật UI khi text thay đổi để hiển thị/ẩn nút xóa
      setState(() {});
    });
    _getCurrentUserId();
    if (currentUserId != null) {
      _friendService.setUserOnline(currentUserId!);
    }
    _listenForFriendRequests();
    _getFriends();
    _listenToIncomingCalls();
  }

  /// Lấy user ID hiện tại
  void _getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      currentUserId = user.uid;
      userRef = FirebaseDatabase.instance.ref("users/$currentUserId");
      if (currentUserId != null) {
        _friendService.setUserOnline(currentUserId!);
      }
      _getFriends();
      _getUserData();
    }
  }

  /// Lấy danh sách bạn bè
  void _getFriends() {
    if (currentUserId != null) {
      _friendService.listenToFriends(currentUserId!).listen((friends) {
        if (mounted) {
          setState(() {
            friendIds = friends;
          });
        }
      });
    }
  }

  /// Tìm kiếm người dùng
  void _searchUsers(String query) async {
    if (currentUserId != null) {
      final results = await _friendService.searchUsers(query, currentUserId!);
      setState(() {
        searchResults = results;
        showSearchResults = results.isNotEmpty;
      });
    }
  }

  /// Gửi yêu cầu kết bạn
  void _sendFriendRequest(String email) {
    _friendService
        .sendFriendRequest(email)
        .then((_) {
          if (!mounted) return;
          setState(() {
            requestSent[email] = true;
          });
          // Show success dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return SuccessDialog(message: "Gửi yêu cầu kết bạn thành công!");
            },
          );
        })
        .catchError((error) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Lỗi gửi yêu cầu: $error")));
        });
  }

  /// Lắng nghe yêu cầu kết bạn
  void _listenForFriendRequests() {
    FirebaseDatabase.instance
        .ref('friend_requests/$currentUserId')
        .onValue
        .listen((event) {
          if (event.snapshot.exists) {
            final requests = event.snapshot.value as Map<dynamic, dynamic>;
            setState(() {
              friendRequestCount = requests.length; // Cập nhật số lượng lời mời
              hasNewFriendRequest = friendRequestCount > 0;
            });
          } else {
            setState(() {
              friendRequestCount = 0; // Không có lời mời
              hasNewFriendRequest = false;
            });
          }
        });
  }

  /// Xóa bạn bè
  void _removeFriend(String friendId) async {
    if (currentUserId == null) return;
    await _friendService.removeFriend(friendId);

    // Show success dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return SuccessDialog(message: "Hủy kết bạn thành công!");
        },
      );
    }
  }

  /// Lấy thông tin người dùng
  void _getUserData() async {
    String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final userData = await _friendService.getUserData(currentUserId);
    if (userData != null) {
      setState(() {
        username = userData["username"];
        email = userData["email"];
        avatarUrl = userData["avatar"];
      });
    }

    // Lấy danh sách yêu cầu kết bạn đã gửi
    final sentRequestsSnapshot =
        await FirebaseDatabase.instance
            .ref()
            .child("users/$currentUserId/sent_requests")
            .get();

    if (sentRequestsSnapshot.exists) {
      final sentRequests = sentRequestsSnapshot.value as Map<dynamic, dynamic>;
      setState(() {
        requestSent = sentRequests.map((key, value) => MapEntry(key, true));
      });
    }
  }

  /// **🔄 Refresh danh sách bạn bè**
  Future<void> _refreshFriendsList() async {
    _getFriends();
    _getUserData();
  }

  /// **📤 Upload ảnh đại diện**
  // Future<void> _uploadAvatar() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery);
  //   if (pickedFile == null || currentUserId == null) return;

  //   final file = File(pickedFile.path);
  //   final storageRef = FirebaseStorage.instance.ref().child(
  //     "avatars/$currentUserId.jpg",
  //   );

  //   // Upload file
  //   await storageRef.putFile(file, SettableMetadata(contentType: "image/jpeg"));

  //   // Lấy URL đầy đủ
  //   final String downloadUrl = await storageRef.getDownloadURL();
  //   debugPrint("Avatar URL: $downloadUrl"); // Debug URL

  //   // Cập nhật vào Firebase Database
  //   await FirebaseDatabase.instance.ref().child("users/$currentUserId").update({
  //     "avatar": downloadUrl,
  //   });

  //   // Cập nhật state để hiển thị ảnh mới
  //   setState(() {
  //     avatarUrl = downloadUrl;
  //   });
  // }

  /// **🚀 Stream lắng nghe danh sách bạn bè**
  Stream<List<UserModel>> getFriendsStream() {
    return FirebaseDatabase.instance
        .ref()
        .child("friends/$currentUserId")
        .onValue
        .asyncMap((event) async {
          if (event.snapshot.value == null) return [];
          Map<dynamic, dynamic> friendsMap =
              event.snapshot.value as Map<dynamic, dynamic>;

          List<UserModel> friends = [];
          for (String friendId in friendsMap.keys) {
            final snapshot =
                await FirebaseDatabase.instance
                    .ref()
                    .child("users/$friendId")
                    .get();
            if (snapshot.exists) {
              final data = snapshot.value as Map<dynamic, dynamic>;
              friends.add(UserModel.fromMap(friendId, data));
            }
          }
          return friends;
        });
  }

  /// **🕒 Hiển thị thời gian
  String _getLastSeenText(DateTime? lastOnline) {
    if (lastOnline == null) return "Không có thông tin";

    Duration difference = DateTime.now().difference(lastOnline);
    if (difference.inMinutes < 1) {
      return "Vừa xong";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes} phút trước";
    } else if (difference.inHours < 24) {
      return "${difference.inHours} giờ trước";
    } else {
      return "${difference.inDays} ngày trước";
    }
  }

  /// **🚪 Đăng xuất user**
  void _logout() async {
    if (currentUserId != null) {
      await FirebaseDatabase.instance
          .ref()
          .child("users/$currentUserId")
          .update({"online": false});
    }

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  /// **🗑️ Dispose**
  @override
  void dispose() {
    _scrollController.dispose(); // Dispose controller
    _searchFocusNode.dispose(); // Dispose focus node
    _searchController.dispose();
    if (currentUserId != null) {
      FirebaseDatabase.instance.ref().child("users/$currentUserId").update({
        "online": false,
        "lastOnline": ServerValue.timestamp,
      });
    }
    super.dispose();
  }

  // Thêm method để scroll với animation
  void _scrollToSearch() {
    Scrollable.ensureVisible(
      context,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    ).then((_) {
      // Sau khi scroll xong, focus vào ô tìm kiếm với animation
      Future.delayed(Duration(milliseconds: 200), () {
        _searchFocusNode.requestFocus();
      });
    });
  }

  /// **👤 Xem hồ sơ bạn bè**
  void _viewProfile(
    BuildContext context,
    UserModel friend,
    String currentUserId,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return ViewProfileDialog(friend: friend, currentUserId: currentUserId);
      },
    );
  }

  /// Bắt đầu cuộc gọi
  void _startCall(
    String friendId,
    String friendName,
    String friendAvatar,
  ) async {
    final callService = CallService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) return;

    try {
      // Kiểm tra người dùng đang trong cuộc gọi khác
      final isInCall = await callService.isUserInCall(currentUserId);
      if (isInCall) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bạn đang trong một cuộc gọi khác')),
        );
        print(
          'DEBUG: User $currentUserId is already in a call. Cannot initiate new call.',
        );
        return;
      }

      // Kiểm tra người nhận đang trong cuộc gọi khác
      final isReceiverInCall = await callService.isUserInCall(friendId);
      if (isReceiverInCall) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Người nhận đang trong một cuộc gọi khác')),
        );
        print(
          'DEBUG: Receiver $friendId is already in a call. Cannot initiate new call.',
        );
        return;
      }

      // Kiểm tra quyền camera và microphone
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isDenied || micStatus.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cần quyền truy cập camera và microphone')),
        );
        print('DEBUG: Camera/Mic permissions denied for initiating call.');
        return;
      }

      // Kiểm tra trạng thái online của người nhận
      final receiverSnapshot =
          await FirebaseDatabase.instance.ref('users/$friendId').get();

      if (!receiverSnapshot.exists ||
          (receiverSnapshot.value as Map)['online'] == false) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Người dùng không trực tuyến')));
        print('DEBUG: Receiver $friendId is not online. Cannot initiate call.');
        return;
      }

      // Tạo cuộc gọi mới
      final callId = await callService.initiateCall(
        callerId: currentUserId,
        receiverId: friendId,
        type: 'video',
      );
      print('DEBUG: Call initiated with ID: $callId');

      // Chuyển đến màn hình cuộc gọi (cho người gọi)
      if (mounted) {
        print('DEBUG: Navigating to CallScreen from FriendListScreen.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => CallScreen(
                  callId: callId,
                  userId: currentUserId,
                  isIncoming: false,
                  type: 'video',
                  remoteParticipantName: friendName,
                  remoteParticipantAvatar: friendAvatar,
                ),
          ),
        );
      }
    } catch (e) {
      print('ERROR: Error starting call from FriendListScreen: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể bắt đầu cuộc gọi')));
      }
    }
  }

  void _listenToIncomingCalls() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _callService.listenToIncomingCalls(currentUserId).listen((event) {
      if (event.snapshot.value == null) return;

      final calls = event.snapshot.value as Map<dynamic, dynamic>;
      calls.forEach((callId, callData) {
        // Chỉ hiển thị IncomingCallScreen nếu nó chưa được hiển thị cho cuộc gọi này
        if (callData['status'] == 'pending' &&
            !_activeIncomingCallScreens.containsKey(callId)) {
          print(
            'DEBUG: Incoming call detected: $callId. Showing IncomingCallScreen.',
          );
          _activeIncomingCallScreens[callId] =
              true; // Đánh dấu là đang hiển thị
          _showIncomingCallScreen(
            callId: callId,
            callerId: callData['callerId'],
            callerName: callData['callerName'],
            callerAvatar: callData['callerAvatar'],
            type: callData['type'],
          );
        } else if (callData['status'] != 'pending' &&
            _activeIncomingCallScreens.containsKey(callId)) {
          // Nếu cuộc gọi không còn pending, xóa khỏi danh sách đang hoạt động
          _activeIncomingCallScreens.remove(callId);
          print(
            'DEBUG: Incoming call $callId status changed to ${callData['status']}. Removing from active screens.',
          );
        }
      });
    });
  }

  void _showIncomingCallScreen({
    required String callId,
    required String callerId,
    required String callerName,
    required String callerAvatar,
    required String type,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => IncomingCallScreen(
              callId: callId,
              callerId: callerId,
              callerName: callerName,
              callerAvatar: callerAvatar,
              type: type,
            ),
      ),
    ).then((_) {
      // Khi IncomingCallScreen bị pop, xóa khỏi danh sách đang hoạt động
      print(
        'DEBUG: IncomingCallScreen for $callId was popped. Removing from active screens.',
      );
      _activeIncomingCallScreens.remove(callId);
    });
  }

  /// **🚫 Chặn người dùng**
  Future<void> _blockFriend(String friendId) async {
    try {
      bool confirm = await showDialog(
        context: context,
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
                  Icon(Icons.block, color: Colors.red, size: 50),
                  SizedBox(height: 16),
                  Text(
                    'Xác nhận chặn',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Bạn có chắc chắn muốn chặn người dùng này không?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(
                            "Hủy",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            "Chặn",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (confirm != true) return;
      if (currentUserId == null) return;

      // Chặn bạn bè tạm thời đưa vào danh sách bị chặn
      await _friendService.blockUser(currentUserId!, friendId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã chặn người dùng thành công')),
        );
      }

      setState(() {});
    } catch (e) {
      // print('Lỗi khi chặn người dùng: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Có lỗi xảy ra khi chặn người dùng')),
        );
      }
    }
  }

  /// **🔓 Bỏ chặn người dùng**
  Future<void> _unblockFriend(String friendId) async {
    try {
      if (currentUserId == null) return;

      // Xóa khỏi danh sách người bị chặn
      await _friendService.unblockUser(currentUserId!, friendId);

      // Hiển thị thông báo thành công
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã bỏ chặn người dùng')));
      }

      // Refresh UI
      setState(() {});
    } catch (e) {
      // print('Lỗi khi bỏ chặn người dùng: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Có lỗi xảy ra khi bỏ chặn người dùng')),
        );
      }
    }
  }

  /// **🔒 Kiểm tra xem người dùng có bị chặn không**
  Future<bool> _isUserBlocked(String friendId) async {
    if (currentUserId == null) return false;
    return await _friendService.isUserBlocked(currentUserId!, friendId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(80), // Chiều cao AppBar
        child: Material(
          elevation: 6, // Hiệu ứng nổi
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20), // Bo góc phía dưới
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue, // Màu xanh dương chủ đạo
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20), // Bo góc phía dưới
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Phần bên trái AppBar
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '👋, ${username ?? "User"}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Welcome back!',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                    // Phần bên phải AppBar
                    Row(
                      children: [
                        Stack(
                          children: [
                            IconButton(
                              icon: Icon(
                                hasNewFriendRequest
                                    ? Icons.notifications
                                    : Icons.notifications_none,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () {
                                setState(() {
                                  hasNewFriendRequest = false;
                                  friendRequestCount = 0;
                                });
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NotificationsScreen(),
                                  ),
                                );
                              },
                            ),
                            if (hasNewFriendRequest && friendRequestCount > 0)
                              Positioned(
                                right: 6,
                                top: 2,
                                child: Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$friendRequestCount',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _logout,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              // Thêm Row để chứa TextField và nút Hủy
              children: [
                Expanded(
                  // TextField sẽ chiếm phần còn lại của không gian
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode, // Thêm focusNode
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.blue[50],
                      labelText: "Tìm kiếm bạn bè",
                      labelStyle: TextStyle(color: Colors.blue),
                      prefixIcon: Icon(Icons.search, color: Colors.blue),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(Icons.clear, color: Colors.blue),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    showSearchResults = false;
                                    searchResults.clear();
                                  });
                                },
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        // Thêm border khi focus
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                      // Thêm hiệu ứng shadow khi focus
                      focusColor: Colors.blue.withOpacity(0.1),
                      hoverColor: Colors.blue.withOpacity(0.05),
                    ),
                    onChanged: (query) {
                      setState(() {
                        showSearchResults = query.isNotEmpty;
                        if (query.isNotEmpty) {
                          _searchUsers(query);
                        }
                      });
                    },
                  ),
                ),
                // Thêm nút Hủy khi đang hiển thị kết quả tìm kiếm
                if (showSearchResults) ...[
                  SizedBox(width: 8), // Khoảng cách giữa TextField và nút Hủy
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _searchController.clear(); // Xóa text trong ô tìm kiếm
                        showSearchResults = false; // Ẩn kết quả tìm kiếm
                        searchResults.clear(); // Xóa kết quả tìm kiếm
                      });
                    },
                    child: Text(
                      'Hủy',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child:
                showSearchResults
                    ? ListView.builder(
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchResults[index];
                        bool isFriend = friendIds.contains(user.uid);
                        bool isRequestSent = requestSent[user.email] ?? false;

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  user.avatarUrl != null
                                      ? NetworkImage(user.avatarUrl!)
                                      : AssetImage("assets/default_avatar.png")
                                          as ImageProvider,
                              radius: 25,
                            ),
                            title: Text(user.username),
                            subtitle: Text(user.email),
                            trailing:
                                isFriend
                                    ? ElevatedButton(
                                      onPressed: null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person,
                                            size: 20,
                                            color: const Color.fromARGB(
                                              255,
                                              59,
                                              241,
                                              192,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            "Bạn bè",
                                            style: TextStyle(
                                              color: const Color.fromARGB(
                                                255,
                                                59,
                                                241,
                                                192,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    : isRequestSent
                                    ? ElevatedButton(
                                      onPressed: null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.schedule_send,
                                            size: 20,
                                            color: const Color.fromARGB(
                                              255,
                                              59,
                                              241,
                                              192,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            "Đã gửi",
                                            style: TextStyle(
                                              color: const Color.fromARGB(
                                                255,
                                                59,
                                                241,
                                                192,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    : ElevatedButton(
                                      onPressed:
                                          () => _sendFriendRequest(user.email),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_add,
                                            size: 20,
                                            color: const Color.fromARGB(
                                              255,
                                              255,
                                              255,
                                              255,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            "Kết bạn",
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                          ),
                        );
                      },
                    )
                    : RefreshIndicator(
                      onRefresh: _refreshFriendsList,
                      child: StreamBuilder<List<UserModel>>(
                        stream: getFriendsStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.people_outline,
                                      size: 100,
                                      color: Colors.blue.withOpacity(0.5),
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  Text(
                                    "Chưa có bạn bè",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                    ),
                                    child: Text(
                                      "Hãy tìm kiếm và kết bạn với những người khác để bắt đầu cuộc trò chuyện!",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade600,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 32),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _scrollToSearch(); // Gọi method scroll với animation
                                    },
                                    icon: Icon(Icons.search),
                                    label: Text("Tìm kiếm bạn bè"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      elevation: 4, // Thêm đổ bóng
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final friends = snapshot.data!;
                          return ListView.builder(
                            itemCount: friends.length,
                            itemBuilder: (context, index) {
                              final friend = friends[index];
                              return StreamBuilder<bool>(
                                stream: Stream.fromFuture(
                                  _isUserBlocked(friend.uid),
                                ),
                                builder: (context, snapshot) {
                                  bool isBlocked = snapshot.data ?? false;

                                  return Card(
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Stack(
                                      children: [
                                        ListTile(
                                          leading: Stack(
                                            children: [
                                              CircleAvatar(
                                                backgroundImage:
                                                    friend.avatarUrl != null
                                                        ? NetworkImage(
                                                          friend.avatarUrl!,
                                                        )
                                                        : AssetImage(
                                                              "assets/default_avatar.png",
                                                            )
                                                            as ImageProvider,
                                                radius: 25,
                                              ),
                                              Positioned(
                                                bottom: 0,
                                                right: 0,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color:
                                                        friend.online
                                                            ? Colors.green
                                                            : Colors.grey,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          title: Text(
                                            friend.username,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  isBlocked
                                                      ? Colors.grey
                                                      : null, // Làm mờ tên nếu bị chặn
                                            ),
                                          ),
                                          subtitle: Row(
                                            children: [
                                              if (isBlocked)
                                                Icon(
                                                  Icons.block,
                                                  size: 16,
                                                  color: Colors.red,
                                                ),
                                              if (isBlocked) SizedBox(width: 4),
                                              Text(
                                                isBlocked
                                                    ? "Đã chặn"
                                                    : (friend.online
                                                        ? "Online"
                                                        : _getLastSeenText(
                                                          friend.lastOnline,
                                                        )),
                                                style: TextStyle(
                                                  color:
                                                      isBlocked
                                                          ? Colors.red
                                                          : (friend.online
                                                              ? Colors.green
                                                              : Colors.grey),
                                                ),
                                              ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Nút gọi điện sẽ bị disable nếu người dùng bị chặn
                                              IconButton(
                                                icon: Icon(
                                                  Icons.call,
                                                  color:
                                                      isBlocked
                                                          ? Colors.grey
                                                          : Colors.blue,
                                                ),
                                                onPressed:
                                                    isBlocked
                                                        ? null
                                                        : () => _startCall(
                                                          friend.uid,
                                                          friend.username,
                                                          friend.avatarUrl ??
                                                              '',
                                                        ),
                                              ),
                                              PopupMenuButton<String>(
                                                icon: Icon(Icons.more_vert),
                                                onSelected: (value) async {
                                                  if (value == "profile") {
                                                    _viewProfile(
                                                      context,
                                                      friend,
                                                      currentUserId!,
                                                    );
                                                  } else if (value ==
                                                      "remove") {
                                                    _removeFriend(friend.uid);
                                                  } else if (value == "block") {
                                                    await _blockFriend(
                                                      friend.uid,
                                                    );
                                                  } else if (value ==
                                                      "unblock") {
                                                    await _unblockFriend(
                                                      friend.uid,
                                                    );
                                                  }
                                                },
                                                itemBuilder:
                                                    (context) => [
                                                      PopupMenuItem(
                                                        value: "profile",
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons.person,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                            SizedBox(width: 10),
                                                            Text("Xem hồ sơ"),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: "remove",
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .person_remove,
                                                              color: Colors.red,
                                                            ),
                                                            SizedBox(width: 10),
                                                            Text("Hủy kết bạn"),
                                                          ],
                                                        ),
                                                      ),
                                                      // Hiển thị nút Block hoặc Unblock tùy thuộc vào trạng thái
                                                      if (!isBlocked)
                                                        PopupMenuItem(
                                                          value: "block",
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons.block,
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                              SizedBox(
                                                                width: 10,
                                                              ),
                                                              Text(
                                                                "Chặn bạn bè",
                                                              ),
                                                            ],
                                                          ),
                                                        )
                                                      else
                                                        PopupMenuItem(
                                                          value: "unblock",
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .person_add,
                                                                color:
                                                                    Colors.blue,
                                                              ),
                                                              SizedBox(
                                                                width: 10,
                                                              ),
                                                              Text("Bỏ chặn"),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isBlocked)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                borderRadius: BorderRadius.only(
                                                  topRight: Radius.circular(15),
                                                  bottomLeft: Radius.circular(
                                                    15,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                'Đã chặn',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
