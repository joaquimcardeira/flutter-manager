import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'screens/login_page.dart';
import 'screens/devices_list_screen.dart';
import 'services/traccar_auth_service.dart';
import 'services/traccar_socket_service.dart';
import 'services/traccar_api_service.dart';
import 'models/device.dart';
import 'models/position.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
        useMaterial3: true,
      ),
      routes: {
        '/login': (_) => const LoginPage(),
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = TraccarAuthService();
    return FutureBuilder<bool>(
      future: auth.sessionExists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final loggedIn = snapshot.data == true;
        if (loggedIn) {
          return const HomePage(title: 'Manager');
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapLibreMapController? mapController;
  int _selectedIndex = 0;
  String? _mapStyle;
  final TraccarSocketService _socketService = TraccarSocketService();
  final TraccarApiService _apiService = TraccarApiService();
  StreamSubscription? _wsSub;

  // Traccar data state
  final Map<int, Device> _devices = {};
  final Map<int, Position> _positions = {};
  final Map<int, Symbol> _mapSymbols = {};

  // Default location (San Francisco)
  final LatLng _center = const LatLng(37.7749, -122.4194);

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
    _loadMapStyle();
    _initializeData();
  }

  /// Fetch initial data from API, then connect to websocket for real-time updates
  Future<void> _initializeData() async {
    dev.log('[Init] Fetching initial devices and positions', name: 'TraccarInit');

    try {
      final devices = await _apiService.fetchDevices();

      if (!mounted) return;

      // Update state with initial data
      setState(() {
        for (var device in devices) {
          _devices[device.id] = device;
        }
      });

      dev.log('[Init] Loaded ${_devices.length} devices, ${_positions.length} positions',
          name: 'TraccarInit');

      // Update map symbols after initial data is loaded
      await _updateMapSymbols();

      // Now connect to websocket for real-time updates
      await _connectSocket();
    } catch (e, stack) {
      dev.log('[Init] Error loading initial data: $e',
          name: 'TraccarInit', error: e, stackTrace: stack);
      // Still try to connect to websocket even if initial fetch fails
      await _connectSocket();
    }
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
    if (_mapStyle == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        MapLibreMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(
            target: _center,
            zoom: 11.0,
          ),
          styleString: _mapStyle!,
          myLocationEnabled: true,
          myLocationTrackingMode: MyLocationTrackingMode.tracking,
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

      // Update state if data changed
      if (updated && mounted) {
        setState(() {
          _devices.addAll(newDevices);
          _positions.addAll(newPositions);
        });
        _updateMapSymbols();
        dev.log('[WS] State updated - Devices: ${_devices.length}, Positions: ${_positions.length}', name: 'TraccarWS');
      }
    } catch (e, stack) {
      dev.log('[WS] Error parsing message: $e', name: 'TraccarWS', error: e, stackTrace: stack);
    }
  }

  Future<void> _updateMapSymbols() async {
    if (mapController == null) return;

    try {
      // Remove symbols for devices that no longer have positions
      final symbolsToRemove = <int>[];
      for (var deviceId in _mapSymbols.keys) {
        if (!_positions.containsKey(deviceId)) {
          symbolsToRemove.add(deviceId);
        }
      }
      for (var deviceId in symbolsToRemove) {
        final symbol = _mapSymbols.remove(deviceId);
        if (symbol != null) {
          await mapController!.removeSymbol(symbol);
        }
      }

      // Add or update symbols for devices with positions
      for (var entry in _positions.entries) {
        final deviceId = entry.key;
        final position = entry.value;
        final device = _devices[deviceId];

        if (device == null) continue;

        final latLng = LatLng(position.latitude, position.longitude);

        // Remove old symbol if exists
        final oldSymbol = _mapSymbols[deviceId];
        if (oldSymbol != null) {
          await mapController!.removeSymbol(oldSymbol);
        }

        // Add new symbol
        final symbol = await mapController!.addSymbol(
          SymbolOptions(
            geometry: latLng,
            iconImage: 'marker-15', // Default marker
            iconSize: 1.5,
            textField: device.name,
            textSize: 12,
            textOffset: const Offset(0, 1.5),
            textColor: '#000000',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
          ),
        );
        _mapSymbols[deviceId] = symbol;
      }

      dev.log('[Map] Updated ${_mapSymbols.length} symbol(s)', name: 'TraccarWS');
    } catch (e, stack) {
      dev.log('[Map] Error updating symbols: $e', name: 'TraccarWS', error: e, stackTrace: stack);
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _socketService.close();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString('assets/google_maps_style.json');
    setState(() {
      _mapStyle = style;
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
  }

  void _onMenuItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Handle menu item selection here
    switch (index) {
      case 0:
        print('Map selected');
        break;
      case 1:
        print('Search selected');
        break;
      case 2:
        print('Saved selected');
        break;
      case 3:
        print('Profile selected');
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
