import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return window;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyAo-fk7wpGP0KpOpge2RS9vdUJ4Up4EKGo",
    authDomain: "meeting-app-77c2d.firebaseapp.com",
    databaseURL:
        "https://meeting-app-77c2d-default-rtdb.asia-southeast1.firebasedatabase.app",
    projectId: "meeting-app-77c2d",
    storageBucket: "meeting-app-77c2d.firebasestorage.app",
    messagingSenderId: "766824097142",
    appId: "1:766824097142:web:d4a85679f3dbcadffc4657",
    measurementId: "G-FY9Z646W9B",
  );

  static const FirebaseOptions window = FirebaseOptions(
    apiKey: "AIzaSyAo-fk7wpGP0KpOpge2RS9vdUJ4Up4EKGo",
    authDomain: "meeting-app-77c2d.firebaseapp.com",
    databaseURL:
        "https://meeting-app-77c2d-default-rtdb.asia-southeast1.firebasedatabase.app",
    projectId: "meeting-app-77c2d",
    storageBucket: "meeting-app-77c2d.firebasestorage.app",
    messagingSenderId: "766824097142",
    appId: "1:766824097142:web:94987661f51eec06fc4657",
    measurementId: "G-DZRKYX8FNQ",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCat-F9d9hXC97LLXqFJJFGsEe8ubgOq64',
    appId: '1:766824097142:android:6ea9dada3d1dfb63fc4657',
    messagingSenderId: '766824097142',
    projectId: 'meeting-app-77c2d',
    databaseURL:
        'https://meeting-app-77c2d-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'meeting-app-77c2d.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCpWy5g7bz9DHsmWHzsgOcab5qUnK0TB78',
    appId: '1:766824097142:ios:16f7532ad9c83ec7fc4657',
    messagingSenderId: '766824097142',
    projectId: 'meeting-app-77c2d',
    databaseURL:
        'https://meeting-app-77c2d-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'meeting-app-77c2d.firebasestorage.app',
    iosBundleId: 'com.example.meetingApp',
  );
}
