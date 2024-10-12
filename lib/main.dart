import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart'; // Added this import
import 'functions/functions.dart';
import 'functions/notifications.dart';
import 'pages/loadingPage/loadingpage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:overlay_support/overlay_support.dart';
import 'dart:io';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['push_type'].toString() == 'meta-request') {
    openApp('com.bennebos.driversuser');
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp();
      var val = await Geolocator.getCurrentPosition();
      dynamic id;
      if (inputData != null) {
        id = inputData['id'];
      }
      FirebaseDatabase.instance.ref().child('drivers/driver_$id').update(
        {
          'lat-lng': val.latitude.toString(),
          'l': {'0': val.latitude, '1': val.longitude},
          'updated_at': ServerValue.timestamp
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print("$e");
      }
    }
    return Future.value(true);
  });
}

// Method to open apps using url_launcher
Future<void> openApp(String packageName) async {
  var androidUrl = 'intent://$packageName/#Intent;scheme=package;end';
  var uri = Uri.parse(androidUrl); // Create a Uri object
  if (await canLaunchUrl(uri)) {
    // Use launchUrl instead
    await launchUrl(uri);
  } else {
    debugPrint('Could not launch $packageName');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await Firebase.initializeApp();
  initMessaging();
  checkInternetConnection();

  currentPositionUpdate();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final platforms = const MethodChannel('flutter.app/awake');

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    Workmanager().cancelAll();
    super.initState();
  }

  Future<void> showOverlayNotification() async {
    try {
      showSimpleNotification(
        const Text("Location tracking is active in the background"),
        background: Colors.green,
        duration: const Duration(minutes: 15),
      );
    } on PlatformException {
      debugPrint('Failed to show overlay notification');
    }
  }

  Future<void> hideOverlayNotification() async {
    try {
      OverlaySupportEntry.of(context)?.dismiss();
    } on PlatformException {
      debugPrint('Failed to hide overlay notification');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      if (Platform.isAndroid &&
          userDetails.isNotEmpty &&
          userDetails['role'] == 'driver' &&
          userDetails['active'] == true) {
        updateLocation(10);
        showOverlayNotification(); // Start overlay when app goes to background
      }
    }
    if (Platform.isAndroid && state == AppLifecycleState.resumed) {
      hideOverlayNotification(); // Stop overlay when app comes to foreground
      Workmanager().cancelAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    platform = Theme.of(context).platform;

    return OverlaySupport.global(
      // Add OverlaySupport wrapper
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Bennebos Driver',
        theme: ThemeData(),
        home: const LoadingPage(),
      ),
    );
  }
}

void updateLocation(int duration) {
  for (var i = 0; i < 15; i++) {
    Workmanager().registerPeriodicTask(
      'locs_$i',
      'update_locs_$i',
      initialDelay: Duration(minutes: i),
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      inputData: {'id': userDetails['id'].toString()},
    );
  }
}
