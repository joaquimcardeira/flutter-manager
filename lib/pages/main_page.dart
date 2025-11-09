import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import '../screens/devices_list_screen.dart';
import '../services/traccar_socket_service.dart';
import '../services/traccar_api_service.dart';
import '../models/device.dart';
import '../models/position.dart';
import '../widgets/map_widget.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.title});
  final String title;
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final TraccarSocketService _socketService = TraccarSocketService();
  final TraccarApiService _apiService = TraccarApiService();
  StreamSubscription? _wsSub;

  final Map<int, Device> _devices = {};
  final Map<int, Position> _positions = {};

  // Icons for bottom navigation
  final List<IconData> _iconList = [
    Icons.map_outlined,
    Icons.devices,
    Icons.favorite_outline,
    Icons.person_outline,
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  /// Update devices state and trigger map refresh
  void _updateDevices(Map<int, Device> newDevices) {
    setState(() {
      _devices.addAll(newDevices);
    });
  }

  /// Update positions state
  void _updatePositions(Map<int, Position> newPositions) {
    setState(() {
      _positions.addAll(newPositions);
    });
  }

  /// Fetch initial data from API, then connect to websocket for real-time updates
  Future<void> _initializeData() async {
    dev.log('[Init] Fetching initial devices and positions', name: 'TraccarInit');
    final devices = await _apiService.fetchDevices();

    if (!mounted) return;

    // Update devices using wrapper method
    final devicesMap = <int, Device>{};
    for (var device in devices) {
      devicesMap[device.id] = device;
    }
    _updateDevices(devicesMap);

    await _connectSocket();
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildMapView();
      case 1:
        return DevicesListScreen(
          devices: _devices,
          positions: _positions,
        );
      case 2:
        return const Center(child: Text('Favorites - Coming Soon'));
      case 3:
        return const Center(child: Text('Profile - Coming Soon'));
      default:
        return _buildMapView();
    }
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        MapWidget(
          devices: _devices,
          positions: _positions,
        ),
        Positioned(
          bottom: 80,
          right: 16,
          child: SpeedDial(
            icon: Icons.add,
            activeIcon: Icons.close,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            activeBackgroundColor: Theme.of(context).colorScheme.primary,
            activeForegroundColor: Colors.white,
            buttonSize: const Size(56, 56),
            visible: true,
            closeManually: false,
            elevation: 8.0,
            animationCurve: Curves.elasticInOut,
            isOpenOnStart: false,
            shape: const CircleBorder(),
            children: [
              SpeedDialChild(
                child: const Icon(Icons.add_location_alt),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                label: 'Add Location',
                labelStyle: const TextStyle(fontSize: 14),
                onTap: () {},
              ),
              SpeedDialChild(
                child: const Icon(Icons.route),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                label: 'Add Route',
                labelStyle: const TextStyle(fontSize: 14),
                onTap: () {},
              ),
              SpeedDialChild(
                child: const Icon(Icons.local_shipping),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                label: 'Add Vehicle',
                labelStyle: const TextStyle(fontSize: 14),
                onTap: () {},
              ),
              SpeedDialChild(
                child: const Icon(Icons.camera_alt),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                label: 'Take Photo',
                labelStyle: const TextStyle(fontSize: 14),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _connectSocket() async {
    final ok = await _socketService.connect();
    if (!mounted) return;
    if (ok && _socketService.stream != null) {
      _wsSub = _socketService.stream!.listen(
        (event) {
          _handleWebSocketMessage(event);
        },
        onError: (e) => dev.log('[WS] Stream error: $e', name: 'TraccarWS'),
        onDone: () => dev.log('[WS] Closed', name: 'TraccarWS'),
      );
    } else {
      dev.log('[WS] Failed to connect', name: 'TraccarWS');
    }
  }

  void _handleWebSocketMessage(dynamic event) {
    try {
      if (event is! String) return;

      final data = jsonDecode(event) as Map<String, dynamic>;
      dev.log('[WS] Received: ${data.keys.join(", ")}', name: 'TraccarWS');

      bool updated = false;

      // Parse devices and positions outside setState
      final Map<int, Device> newDevices = {};
      final Map<int, Position> newPositions = {};

      // Handle devices
      if (data['devices'] != null) {
        final devicesList = data['devices'] as List;
        for (var deviceJson in devicesList) {
          final device = Device.fromJson(deviceJson as Map<String, dynamic>);
          newDevices[device.id] = device;
        }
        dev.log('[WS] Received ${devicesList.length} device(s)', name: 'TraccarWS');
        updated = true;
      }

      // Handle positions
      if (data['positions'] != null) {
        final positionsList = data['positions'] as List;
        for (var positionJson in positionsList) {
          final position = Position.fromJson(positionJson as Map<String, dynamic>);
          newPositions[position.deviceId] = position;
        }
        dev.log('[WS] Received ${positionsList.length} position(s)', name: 'TraccarWS');
        updated = true;
      }

      // Update state using wrapper methods
      if (updated && mounted) {
        // Update devices if any
        if (newDevices.isNotEmpty) {
          _updateDevices(newDevices);
        }

        // Update positions if any (automatically updates map)
        if (newPositions.isNotEmpty) {
          _updatePositions(newPositions);
        }

        dev.log('[WS] State updated - Devices: ${_devices.length}, Positions: ${_positions.length}', name: 'TraccarWS');
      }
    } catch (e, stack) {
      dev.log('[WS] Error parsing message: $e', name: 'TraccarWS', error: e, stackTrace: stack);
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _socketService.close();
    super.dispose();
  }

  void _onMenuItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Handle menu item selection here
    switch (index) {
      case 0:
        dev.log('Map selected', name: 'Navigation');
        break;
      case 1:
        dev.log('Devices selected', name: 'Navigation');
        break;
      case 2:
        dev.log('Favorites selected', name: 'Navigation');
        break;
      case 3:
        dev.log('Profile selected', name: 'Navigation');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Current screen content
          _buildCurrentScreen(),

          // Curved Navigation Bar Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CurvedNavigationBar(
              index: _selectedIndex,
              height: 60,
              items: <Widget>[
                Icon(_iconList[0], size: 30, color: Colors.white),
                Icon(_iconList[1], size: 30, color: Colors.white),
                Icon(_iconList[2], size: 30, color: Colors.white),
                Icon(_iconList[3], size: 30, color: Colors.white),
              ],
              color: Theme.of(context).colorScheme.primary,
              buttonBackgroundColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.transparent,
              animationCurve: Curves.easeInOut,
              animationDuration: const Duration(milliseconds: 300),
              onTap: _onMenuItemTapped,
            ),
          ),
        ],
      ),
    );
  }
}
