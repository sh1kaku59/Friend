import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/friend_service.dart';

class ViewProfileDialog extends StatefulWidget {
  final UserModel friend;
  final String currentUserId;

  const ViewProfileDialog({
    super.key,
    required this.friend,
    required this.currentUserId,
  });

  @override
  _ViewProfileDialogState createState() => _ViewProfileDialogState();
}

class _ViewProfileDialogState extends State<ViewProfileDialog> {
  final FriendService _friendService = FriendService();
  List<String> mutualFriends = [];

  @override
  void initState() {
    super.initState();
    _loadMutualFriends();
  }

  /// 🔄 **Lấy danh sách bạn chung**
  void _loadMutualFriends() async {
    List<String> userFriends = await _friendService.getFriends(
      widget.currentUserId,
    );
    List<String> friendFriends = await _friendService.getFriends(
      widget.friend.uid,
    );

    setState(() {
      mutualFriends =
          userFriends.where((id) => friendFriends.contains(id)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: EdgeInsets.all(16),
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
            // Ảnh đại diện
            CircleAvatar(
              radius: 60,
              backgroundImage:
                  widget.friend.avatarUrl != null &&
                          widget.friend.avatarUrl!.startsWith("http")
                      ? NetworkImage(widget.friend.avatarUrl!)
                      : AssetImage("assets/default_avatar.png")
                          as ImageProvider,
            ),
            SizedBox(height: 16),

            // Tên và email
            Text(
              widget.friend.username,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            Text(
              widget.friend.email,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 16),

            // Trạng thái bạn bè
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person, color: Colors.green),
                SizedBox(width: 5),
                Text(
                  "Đang là bạn bè",
                  style: TextStyle(color: Colors.green, fontSize: 16),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Danh sách bạn chung
            Text(
              "Bạn chung (${mutualFriends.length})",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 10),

            mutualFriends.isEmpty
                ? Text(
                  "Không có bạn chung",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                )
                : SizedBox(
                  height: 100,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: mutualFriends.length,
                    itemBuilder: (context, index) {
                      return FutureBuilder<UserModel?>(
                        future: _friendService
                            .getUserData(mutualFriends[index])
                            .then((data) {
                              if (data != null) {
                                return UserModel.fromMap(
                                  mutualFriends[index],
                                  data,
                                );
                              }
                              return null;
                            }),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return SizedBox();
                          UserModel mutualFriend = snapshot.data!;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: NetworkImage(
                                mutualFriend.avatarUrl!,
                              ),
                            ),
                            title: Text(mutualFriend.username),
                          );
                        },
                      );
                    },
                  ),
                ),
            SizedBox(height: 20),

            // Nút đóng
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              ),
              child: Text(
                "Đóng",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
