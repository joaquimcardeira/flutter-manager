import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'devices_list_page.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/device.dart';
import '../models/position.dart';
import '../widgets/map_widget.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  StreamSubscription? _wsSub;

  final Map<int, Device> _devices = {};
  final Map<int, Position> _positions = {};

  // Icons for bottom navigation
  final List<IconData> _iconList = [
    Icons.map_outlined,
    Icons.list,
    Icons.person_outline,
  ];

  @override
  void initState() {
    super.initState();
    _init();
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
  Future<void> _init() async {
    final devices = await _apiService.fetchDevices();
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
        return DevicesListPage(
          devices: _devices,
          positions: _positions,
        );
      case 2:
        return const Center(child: Text('Favorites - Coming Soon'));
      case 3:
        return _buildProfileView();
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

  Widget _buildProfileView() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _authService.getUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        return Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: ListView(
            children: [
              const SizedBox(height: 20),
              // User Info Card
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user?['name'] ?? 'User',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?['email'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Stats Card
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Statistics',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            icon: Icons.devices,
                            label: 'Devices',
                            value: '${_devices.length}',
                          ),
                          _buildStatItem(
                            icon: Icons.location_on,
                            label: 'Active',
                            value: '${_positions.length}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Logout Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
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
      if (event is! String) return;

      final data = jsonDecode(event) as Map<String, dynamic>;

      final Map<int, Device> newDevices = {};
      final Map<int, Position> newPositions = {};

      if (data['devices'] != null) {
        final devicesList = data['devices'] as List;
        for (var deviceJson in devicesList) {
          final device = Device.fromJson(deviceJson as Map<String, dynamic>);
          newDevices[device.id] = device;
        }
        dev.log('Received ${devicesList.length} device(s)', name: 'WS');
      }

      // Handle positions
      if (data['positions'] != null) {
        final positionsList = data['positions'] as List;
        for (var positionJson in positionsList) {
          final position = Position.fromJson(positionJson as Map<String, dynamic>);
          newPositions[position.deviceId] = position;
        }
        dev.log('Received ${positionsList.length} position(s)', name: 'WS');
      }

      if (newDevices.isNotEmpty) {
        _updateDevices(newDevices);
      }

      if (newPositions.isNotEmpty) {
        _updatePositions(newPositions);
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
