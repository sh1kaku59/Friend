import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/auth/register_screen.dart'; // Import màn hình đăng ký
import 'screens/auth/login_screen.dart'; // Import màn hình đăng nhập
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Thêm dòng này
  ); // Đảm bảo Firebase được khởi tạo

  // Kiểm tra kết nối Firestore
  try {
    await FirebaseFirestore.instance.collection('test').get();
    print("Firestore kết nối thành công!");
  } catch (e) {
    print("Lỗi kết nối Firestore: $e");
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Meeting App',
      initialRoute: '/login', // Màn hình mặc định
      routes: {
        '/register': (context) => RegisterScreen(),
        '/login': (context) => LoginScreen(),
      },
    );
  }
}
