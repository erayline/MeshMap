import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'location_service.dart';
import 'mesh_service.dart';
import 'routing_service.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const MeshApp());
}

class MeshApp extends StatelessWidget {
  const MeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const PermissionGate(),
    );
  }
}

class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _loading = true;
  bool _granted = false;
  String _statusMessage = 'Requesting permissions...';

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  Future<void> _requestPermissionsAndInit() async {
    // Request permissions needed by Nearby Connections.
    // Bluetooth: Android 12+ requires SCAN, ADVERTISE, CONNECT.
    // Location: Required for BLE discovery.
    // Nearby WiFi: Android 13+ for mesh awareness.
    final Map<Permission, PermissionStatus> statuses = {};

    for (final perm in [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      if (Platform.isAndroid) Permission.nearbyWifiDevices,
    ]) {
      try {
        statuses[perm] = await perm.request();
      } catch (_) {
        // Permission might not exist on this device/Android version.
      }
    }

    final criticalPerms = [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final denied = statuses.entries
        .where((e) =>
            criticalPerms.contains(e.key) &&
            (e.value.isDenied || e.value.isPermanentlyDenied))
        .toList();

    if (statuses.isNotEmpty && denied.isEmpty) {
      try {
        await MeshService().init();
        await MeshService().start();
        await LocationService().start();
        await RoutingService().init();
        if (mounted) setState(() { _loading = false; _granted = true; });
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _granted = false;
            _statusMessage = 'Error initializing mesh:\n$e';
          });
        }
      }
    } else {
      final names = denied.map((e) => e.key.toString().split('.').last).join('\n  • ');
      if (mounted) {
        setState(() {
          _loading = false;
          _granted = false;
          _statusMessage = 'Permissions needed:\n  • $names\n\nTap "Open Settings" to grant them.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Requesting permissions...'),
            ],
          ),
        ),
      );
    }
    if (!_granted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bluetooth_disabled, size: 72, color: Colors.red),
                const SizedBox(height: 24),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() { _loading = true; _statusMessage = 'Requesting permissions...'; });
                    _requestPermissionsAndInit();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}
