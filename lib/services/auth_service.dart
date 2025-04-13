import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref("users");

  Future<User?> signUp(String email, String password, String username) async {
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);
      User? user = userCredential.user;

      if (user != null) {
        await _db.child(user.uid).set({
          "email": email,
          "username": username,
          "status": "offline",
          "friends": {},
          "requests_sent": {},
          "requests_received": {},
        });
      }
      return user;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;
      if (user != null) {
        // Cập nhật trạng thái online
        await _db.child(user.uid).update({"status": "online"});
        return user.uid; // Trả về UID của user nếu thành công
      }
      return "Đăng nhập thất bại";
    } catch (e) {
      print("Lỗi đăng nhập: $e");
      return e.toString(); // Trả về lỗi nếu có
    }
  }

  Future<String?> register(
    String email,
    String password,
    String username,
  ) async {
    try {
      // Đăng ký tài khoản trên Firebase Authentication
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;

      if (user != null) {
        // Lưu thông tin user vào Firebase Realtime Database
        await _db.child(user.uid).set({
          "uid": user.uid, // Lưu UID của user
          "email": email,
          "username": username,
          "status": "offline",
          "friends": {}, // Danh sách bạn bè
          "requests_sent": {},
          "requests_received": {},
        });

        print("✅ Đăng ký thành công! UID: ${user.uid}");
        return null; // Trả về null nếu thành công
      }

      return "Đăng ký thất bại, vui lòng thử lại";
    } catch (e) {
      print("❌ Lỗi đăng ký: $e");
      return e.toString(); // Trả về lỗi để hiển thị lên UI
    }
  }
}
