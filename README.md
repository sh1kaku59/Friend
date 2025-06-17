# Friend

Friend là một ứng dụng kết bạn, chat và gọi video/audio đa nền tảng, được phát triển bằng Flutter và Firebase. Dự án có đầy đủ các chức năng giao tiếp thời gian thực, quản lý bạn bè, xác thực đăng nhập, và hỗ trợ đa thiết bị.

## 🏆 Chức năng chính

- **Đăng ký/Đăng nhập tài khoản** (qua email & password)
- **Quản lý danh sách bạn bè**: gửi, nhận, chấp nhận/từ chối lời mời kết bạn, xóa bạn
- **Trạng thái online/offline, thời gian online gần nhất**
- **Chat, nhắn tin tức thời** (Realtime Database)
- **Gọi video và gọi audio** (WebRTC, hỗ trợ kiểm tra thiết bị đầu vào/ra, chuyển đổi camera, mute mic, chọn loa ngoài)
- **Quản lý thông tin cá nhân**: cập nhật avatar, email, username
- **Thông báo cuộc gọi, tin nhắn**
- **Kiểm tra & hiển thị chất lượng kết nối khi gọi**
- **Bảo mật: kiểm tra quyền camera, micro, xác thực Firebase**

## 🛠️ Công nghệ & Thư viện sử dụng

- **Flutter**: framework phát triển đa nền tảng
- **Firebase** (core, auth, realtime database, firestore, storage): xác thực, lưu trữ dữ liệu, trạng thái thời gian thực
- **flutter_webrtc**: truyền tải video/audio trực tiếp giữa người dùng
- **permission_handler**: xin và kiểm tra quyền truy cập thiết bị (camera, micro)
- **image_picker**: chọn ảnh đại diện
- **just_audio**: phát âm thanh thông báo
- **uuid**: tạo mã định danh duy nhất
- **rxdart**: xử lý bất đồng bộ nâng cao
- **cupertino_icons**: bộ icon cho giao diện iOS

## 🚀 Hướng dẫn cài đặt & chạy dự án

### 1. Cài đặt Flutter

Nếu bạn chưa cài đặt Flutter, làm theo hướng dẫn chính thức:  
https://docs.flutter.dev/get-started/install

### 2. Clone dự án

```bash
git clone https://github.com/sh1kaku59/Friend.git
cd Friend
```

### 3. Cài đặt các package/phụ thuộc

```bash
flutter pub get
```

### 4. Thiết lập Firebase

- Tạo project Firebase (https://console.firebase.google.com/)
- Kích hoạt Authentication (Email/Password)
- Kích hoạt Realtime Database và Cloud Firestore
- Tải file cấu hình `google-services.json` (Android) và `GoogleService-Info.plist` (iOS) về đặt vào thư mục tương ứng theo hướng dẫn:  
  https://firebase.google.com/docs/flutter/setup?platform=android

### 5. Chạy ứng dụng

```bash
flutter run
```

## 📦 Cấu trúc dự án

- `lib/`
  - `main.dart`: khởi tạo ứng dụng, cấu hình Firebase
  - `screens/`: giao diện các màn hình (đăng nhập, bạn bè, chat, gọi)
  - `models/`: định nghĩa dữ liệu người dùng, bạn bè
  - `services/`: xử lý logic (signaling WebRTC, tương tác Firebase)
- `pubspec.yaml`: khai báo các package sử dụng

## 📋 Một số lệnh hữu ích

- Build release: `flutter build apk` (Android), `flutter build ios` (iOS)
- Kiểm tra lỗi code: `flutter analyze`
- Chạy unit test: `flutter test`

## 📝 Đóng góp

Mọi đóng góp, báo lỗi hoặc ý tưởng cải tiến đều hoan nghênh thông qua Issues hoặc Pull request tại:  
https://github.com/sh1kaku59/Friend

---

**© 2025 sh1kaku59**  
