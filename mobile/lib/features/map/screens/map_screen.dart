import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../providers/map_provider.dart';
import '../../../shared/models/landmark_model.dart';
import '../../../shared/models/route_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../proximity/providers/proximity_provider.dart';
import '../../../shared/models/event_model.dart';
import '../../../shared/models/comment_model.dart';
import '../../../core/services/local_data_service.dart';
import '../../../core/providers/visited_provider.dart';
import '../../federated/providers/fl_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sheetController = DraggableScrollableController();
  late final TabController _tabController;
  bool _centeredOnUser = false;
  List<LatLng> _streetPolyline = const [];   // teal: user → next route stop
  List<LatLng> _overviewPolyline = const []; // purple dashed: all route stops via streets
  List<LatLng> _navPolyline = const [];      // teal: standalone landmark navigation
  LandmarkModel? _navTarget;
  String _navMode = 'walking'; // 'walking' | 'driving' | 'transit'
  int? _navDurationSec;        // seconds from OSRM for current nav
  int? _routeDurationSec;      // seconds from OSRM for route overview
  int? _routeDistanceM;        // metres from OSRM for route overview
  bool _headingUp = false;
  StreamSubscription<CompassEvent>? _compassSub;
  double _lastCompassHeading = 0;
  // Location picker state
  bool _pickingLocation = false;
  LatLng? _pickedLocation;
  // Selected marker (highlighted when popup is open)
  String? _selectedLandmarkId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sheetController.addListener(() => setState(() {}));
    // Magnetometer compass - rotates map even when stationary
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted || !_headingUp) return;
      final heading = event.heading;
      if (heading == null) return;
      // Only rotate if heading changed by more than 2° to suppress sensor noise
      double diff = (heading - _lastCompassHeading).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < 2.0) return;
      _lastCompassHeading = heading;
      _mapController.rotate(-heading);
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _tabController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final theme = Theme.of(context);

    ref.listen<MapState>(mapProvider, (prev, next) {
      if (next.activeRoute != null && prev?.activeRoute != next.activeRoute) {
        setState(() { _navTarget = null; _navPolyline = const []; });
        _fetchStreetRoute(next.activeRoute!.stops, next.position);
        _fetchGeneratedRouteOverview(next.activeRoute!);
      }
      if (next.activeRoute == null && prev?.activeRoute != null) {
        setState(() { _streetPolyline = const []; _headingUp = false; });
        _mapController.rotate(0);
      }
      if (next.activeProgressRoute != null && prev?.activeProgressRoute != next.activeProgressRoute) {
        setState(() { _streetPolyline = const []; _navTarget = null; _navPolyline = const []; });
        _fetchRouteOverview(next.activeProgressRoute!);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached) {
            _sheetController.animateTo(0.45, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
        _animateToRoute(next.activeProgressRoute!);
      }
      if (next.activeProgressRoute == null && prev?.activeProgressRoute != null) {
        setState(() { _streetPolyline = const []; _overviewPolyline = const []; _routeDurationSec = null; _routeDistanceM = null; _headingUp = false; });
        _mapController.rotate(0);
      }
      // Heading-up: rotate map to GPS heading (cardinal direction of travel)
      if (_headingUp &&
          (_navTarget != null || next.activeProgressRoute != null || next.activeRoute != null) &&
          next.position != null) {
        _mapController.rotate(-(next.position!.heading));
      }
    });

    ref.listen(proximityProvider, (prev, next) {
      final landmark = next.nearbyLandmark;
      if (landmark != null && prev?.nearbyLandmark?.id != landmark.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showProximitySheet(landmark);
        });
      }
    });

    if (!_centeredOnUser && mapState.position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          LatLng(mapState.position!.latitude, mapState.position!.longitude),
          15,
        );
        _centeredOnUser = true;
      });
    }

    final initialCenter = mapState.position != null
        ? LatLng(mapState.position!.latitude, mapState.position!.longitude)
        : const LatLng(44.4268, 26.1025);

    final authState = ref.watch(authProvider);
    final displayName = authState.user?.name ?? 'Explorer';
    final initials = displayName.trim().split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join();

    // Decide which landmarks to show on map
    final mapLandmarks = mapState.allLandmarks.isNotEmpty
        ? mapState.allLandmarks
        : mapState.landmarks;

    // When a progress route is active, show only its stops
    final progressRoute = mapState.activeProgressRoute;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text(authState.user?.email ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Map'),
                selected: true,
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/profile');
                },
              ),
              ListTile(
                leading: const Icon(Icons.how_to_vote_outlined),
                title: const Text('Community Review'),
                onTap: () {
                  Navigator.pop(context);
                  _showCommunityReview();
                },
              ),
              if (authState.user?.isAdmin == true) ...[
                ListTile(
                  leading: const Icon(Icons.add_road),
                  title: const Text('Create Route'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateRouteSheet();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Pending Submissions'),
                  onTap: () {
                    Navigator.pop(context);
                    _showPendingSubmissions();
                  },
                ),
              ],
              const Spacer(),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text('Logout', style: TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(authProvider.notifier).logout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Perspective tilt when heading-up - map recedes toward horizon (navigation mode)
          Transform(
            alignment: Alignment.bottomCenter,
            transform: _headingUp
                ? (Matrix4.identity()
                    ..setEntry(3, 2, 0.0012) // perspective depth
                    ..rotateX(0.32))         // ~18° tilt backward
                : Matrix4.identity(),
            child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15,
              maxZoom: 17,
              interactionOptions: InteractionOptions(
                flags: _headingUp
                    ? InteractiveFlag.all  // allow rotation when heading-up so map follows bearing
                    : InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _pickingLocation ? (_, point) {
                setState(() => _pickedLocation = point);
              } : null,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.culture_quest',
                tileProvider: _CachedTileProvider(),
                panBuffer: 1,
                keepBuffer: 4,
                maxZoom: 17,
              ),
              // Generated route polyline — hidden while navigation is active
              if (mapState.activeRoute != null && progressRoute == null && _navTarget == null)
                PolylineLayer(polylines: [
                  _streetPolyline.isNotEmpty
                      ? Polyline(points: _streetPolyline, strokeWidth: 4, color: Colors.deepPurple)
                      : _buildRoutePolyline(mapState.activeRoute!.stops.map((s) => s.landmark).toList(), mapState.position),
                ]),
              // Progress route overview polyline — hidden while navigation is active
              if (progressRoute != null && _overviewPolyline.isNotEmpty && _navTarget == null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _overviewPolyline,
                    strokeWidth: 4,
                    color: Colors.deepPurple,
                  ),
                ]),
              // Navigation polyline — on top, shown whenever nav is active (including over routes)
              if (_navTarget != null && _navPolyline.isNotEmpty)
                PolylineLayer(polylines: [Polyline(points: _navPolyline, strokeWidth: 5, color: Colors.teal)]),
              // Landmark markers - numbered for generated route stops, normal otherwise
              if (progressRoute == null && mapLandmarks.isNotEmpty)
                MarkerLayer(
                  markers: mapState.activeRoute != null
                      ? mapState.activeRoute!.stops.asMap().entries
                          .map((e) => _buildGeneratedStopMarker(e.value.landmark, e.key + 1))
                          .toList()
                      : mapLandmarks.map((l) => _buildLandmarkMarker(l)).toList(),
                ),
              // Progress route stop markers
              if (progressRoute != null)
                MarkerLayer(
                  markers: progressRoute.stops.asMap().entries.map((e) =>
                    _buildProgressStopMarker(e.value, e.key + 1)).toList(),
                ),
              if (mapState.position != null)
                MarkerLayer(markers: [_buildUserMarker(mapState.position!)]),
              // Picked location marker
              if (_pickedLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _pickedLocation!,
                    width: 44, height: 52,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_pin, color: Colors.deepOrange, size: 44),
                      ],
                    ),
                  ),
                ]),
            ],
          ),  // closes FlutterMap
          ),  // closes Transform

          // Picker instruction banner - at the very bottom when picking
          if (_pickingLocation)
            Positioned(
              left: 16, right: 80,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: Material(
                borderRadius: BorderRadius.circular(14),
                color: theme.colorScheme.inverseSurface,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.touch_app, color: theme.colorScheme.onInverseSurface, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pickedLocation == null
                            ? 'Tap on the map to place the pin'
                            : 'Pin placed - tap again to move it',
                        style: TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() { _pickingLocation = false; _pickedLocation = null; }),
                      style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onInverseSurface,
                          padding: EdgeInsets.zero),
                      child: const Text('Cancel'),
                    ),
                    if (_pickedLocation != null)
                      FilledButton(
                        onPressed: () {
                          setState(() => _pickingLocation = false);
                          _restoreSheet();
                          _showSuggestSheet(_pickedLocation);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.onInverseSurface,
                          foregroundColor: theme.colorScheme.inverseSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Confirm'),
                      ),
                  ]),
                ),
              ),
            ),

          // Menu button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.menu, size: 24),
                ),
              ),
            ),
          ),

          // Error banner
          if (mapState.error != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 68, right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(mapState.error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
            ),

          // Navigation banner - takes priority over route display when active
          if (_navTarget != null)
            Positioned(
              left: 16, right: 16,
              bottom: MediaQuery.of(context).size.height *
                      (_sheetController.isAttached ? _sheetController.size : 0.28) +
                  12,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.teal.shade700,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.navigation, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('To: ${_navTarget!.name}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          if (_navMode == 'transit')
                            const Text('Tap "Open in Google Maps" for routes',
                                style: TextStyle(color: Colors.white70, fontSize: 11))
                          else if (_navDurationSec != null) ...[
                            Text(
                              '~${(_navDurationSec! / 60).ceil()} min ${_navMode == "driving" ? "drive" : "walk"}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              'Arriving ~${DateFormat('HH:mm').format(DateTime.now().add(Duration(seconds: _navDurationSec!)))}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Heading-up toggle
                    GestureDetector(
                      onTap: () {
                        setState(() => _headingUp = !_headingUp);
                        if (_headingUp) _applyHeadingNow(); else _mapController.rotate(0);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _headingUp ? Colors.white.withOpacity(0.25) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.explore, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final stoppedTarget = _navTarget;
                        final hadRoute = mapState.activeRoute != null || progressRoute != null;
                        setState(() { _navTarget = null; _navPolyline = const []; _navMode = 'walking'; _headingUp = false; });
                        _mapController.rotate(0);
                        _restoreSheet();
                        // Only reopen landmark sheet if there was no route — if there was
                        // a route, closing nav simply returns to route display.
                        if (stoppedTarget != null && !hadRoute) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _showLandmarkSheet(stoppedTarget);
                          });
                        }
                      },
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ]),
                ),
              ),
            ),

          // FABs - above the nav banner when navigating, aligned with sheet otherwise
          Positioned(
            right: 16,
            bottom: _pickingLocation
                ? MediaQuery.of(context).padding.bottom + 16
                : (_navTarget != null)
                    // Nav banner is ~90px tall; raise FABs above it
                    ? MediaQuery.of(context).size.height *
                          (_sheetController.isAttached ? _sheetController.size : 0.28) +
                      104
                    : MediaQuery.of(context).size.height *
                          (_sheetController.isAttached ? _sheetController.size : 0.28) +
                      8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nearby events
                FloatingActionButton.small(
                  heroTag: 'nearbyEvents',
                  tooltip: 'Nearby events',
                  onPressed: () => _showNearbyEventsSheet(),
                  child: const Icon(Icons.event_outlined),
                ),
                const SizedBox(height: 8),
                // Suggest a location
                FloatingActionButton.small(
                  heroTag: 'suggest',
                  tooltip: 'Suggest a location',
                  backgroundColor: _pickingLocation ? theme.colorScheme.primary : null,
                  onPressed: () {
                    final nowPicking = !_pickingLocation;
                    setState(() {
                      _pickingLocation = nowPicking;
                      if (!nowPicking) _pickedLocation = null;
                    });
                    if (!nowPicking) _restoreSheet();
                  },
                  child: Icon(_pickingLocation ? Icons.close : Icons.add_location_alt_outlined),
                ),
                const SizedBox(height: 8),
                // Centre on me
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: () {
                    if (mapState.position != null) {
                      _mapController.move(LatLng(mapState.position!.latitude, mapState.position!.longitude), 15);
                    }
                  },
                  child: mapState.position == null
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // Bottom sheet
          if (!_pickingLocation)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.28,
              minChildSize: 0.15,
              maxChildSize: 0.75,
              builder: (context, scrollController) => _BottomPanel(
                scrollController: scrollController,
                mapState: mapState,
                tabController: _tabController,
                onLandmarkTap: _showLandmarkSheet,
                navTarget: _navTarget,
                navMode: _navMode,
                onNavModeChanged: (mode) {
                  setState(() => _navMode = mode);
                  if (_navTarget != null) _fetchNavPolylineOnly(_navTarget!, mode);
                  // Re-fetch progress route overview
                  final pr = ref.read(mapProvider).activeProgressRoute;
                  if (pr != null) _fetchRouteOverview(pr);
                  // Re-fetch generated route polyline + overview
                  final ar = ref.read(mapProvider).activeRoute;
                  if (ar != null) {
                    _fetchStreetRoute(ar.stops, ref.read(mapProvider).position);
                    _fetchGeneratedRouteOverview(ar);
                  }
                },
                onStopNav: () {
                  // Closing nav inside a route returns to route — no landmark sheet
                  setState(() { _navTarget = null; _navPolyline = const []; _headingUp = false; });
                  _mapController.rotate(0);
                },
                routeDurationSec: _routeDurationSec,
                routeDistanceM: _routeDistanceM,
                openInMaps: _openGoogleMaps,
                headingUp: _headingUp,
                onHeadingUpToggle: () {
                  setState(() => _headingUp = !_headingUp);
                  if (_headingUp) _applyHeadingNow(); else _mapController.rotate(0);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Path-bearing helpers ──────────────────────────────────────────────────────

  double _distM(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * 6371000 * math.asin(math.sqrt(s));
  }

  double _bearingTo(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Finds a lookahead point ~80 m ahead of the user on the active polyline.
  /// Apply heading-up rotation immediately.
  /// Compass events will keep it updated; this just triggers the initial zoom.
  void _applyHeadingNow() {
    final pos = ref.read(mapProvider).position;
    if (pos == null) return;
    // Compass subscription handles rotation; just zoom to current position
    _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
  }

  LatLng? _lookaheadOnPath(Position pos) {
    // Priority: progress-route overview → generated-route street line → standalone nav
    final polyline = _overviewPolyline.isNotEmpty
        ? _overviewPolyline
        : _streetPolyline.isNotEmpty
            ? _streetPolyline
            : _navPolyline.isNotEmpty
                ? _navPolyline
                : <LatLng>[];
    if (polyline.length < 2) return null;
    final user = LatLng(pos.latitude, pos.longitude);
    // Find the closest index
    int closest = 0;
    double minD = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final d = _distM(user, polyline[i]);
      if (d < minD) { minD = d; closest = i; }
    }
    // Walk forward ~80 m from that point
    double cum = 0;
    for (int i = closest; i < polyline.length - 1; i++) {
      cum += _distM(polyline[i], polyline[i + 1]);
      if (cum >= 80) return polyline[i + 1];
    }
    return polyline.last;
  }

  /// Returns the correct OSRM endpoint for the given profile.
  /// router.project-osrm.org only serves driving; foot/bike need routing.openstreetmap.de.
  String _osrmUrl(String mode, String waypoints) {
    if (mode == 'driving') {
      return 'https://router.project-osrm.org/route/v1/driving/$waypoints';
    }
    // foot / walking
    return 'https://routing.openstreetmap.de/routed-foot/route/v1/foot/$waypoints';
  }

  void _collapseSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(0.15,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _restoreSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(0.28,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _animateToLandmark(LandmarkModel landmark) {
    _mapController.move(LatLng(landmark.location.lat, landmark.location.lng), 14);
  }

  void _animateToRoute(RouteWithProgress route) {
    if (route.stops.isEmpty) return;
    final lats = route.stops.map((s) => s.landmark.location.lat).toList();
    final lngs = route.stops.map((s) => s.landmark.location.lng).toList();
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48), maxZoom: 15.5));
  }

  Marker _buildUserMarker(dynamic position) => Marker(
        point: LatLng(position.latitude, position.longitude),
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      );

  Marker _buildLandmarkMarker(LandmarkModel l) {
    final isNav = _navTarget?.id == l.id;
    final isSelected = _selectedLandmarkId == l.id;
    final size = isNav ? 44.0 : isSelected ? 46.0 : 36.0;
    final color = isNav ? Colors.green.shade600 : _colorForType(l.type);
    return Marker(
      point: LatLng(l.location.lat, l.location.lng),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _showLandmarkSheet(l),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white,
              width: isSelected ? 3.5 : (isNav ? 3 : 2),
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withOpacity(0.6)
                    : isNav ? Colors.green.withOpacity(0.45) : Colors.black26,
                blurRadius: isSelected ? 14 : (isNav ? 10 : 4),
                spreadRadius: isSelected ? 4 : (isNav ? 3 : 0),
              ),
            ],
          ),
          child: Icon(_iconForType(l.type), color: Colors.white,
              size: isNav ? 22 : isSelected ? 24 : 18),
        ),
      ),
    );
  }

  Marker _buildGeneratedStopMarker(LandmarkModel l, int index) => Marker(
        point: LatLng(l.location.lat, l.location.lng),
        width: 40, height: 40,
        child: GestureDetector(
          onTap: () => _showLandmarkSheet(l),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Center(
              child: Text('$index', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
      );

  Marker _buildProgressStopMarker(RouteStopWithProgress stop, int index) {
    final visited = stop.visited;
    return Marker(
      point: LatLng(stop.landmark.location.lat, stop.landmark.location.lng),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _showLandmarkSheet(stop.landmark), // resolved inside _showLandmarkSheet
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: visited ? Colors.green.shade600 : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Center(
                child: visited
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text('$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Polyline _buildRoutePolyline(List<LandmarkModel> stops, dynamic position) {
    final points = <LatLng>[];
    if (position != null) points.add(LatLng(position.latitude, position.longitude));
    for (final l in stops) {
      points.add(LatLng(l.location.lat, l.location.lng));
    }
    return Polyline(points: points, strokeWidth: 4, color: Colors.deepPurple);
  }

  Future<void> _fetchStreetRoute(List<RouteStop> stops, dynamic origin) async {
    if (origin == null || stops.isEmpty || _navMode == 'transit') return;
    try {
      final waypoints = [
        '${origin.longitude},${origin.latitude}',
        ...stops.map((s) => '${s.landmark.location.lng},${s.landmark.location.lat}'),
      ].join(';');
      final res = await Dio().get(
        _osrmUrl(_navMode, waypoints),
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      final coords = res.data['routes'][0]['geometry']['coordinates'] as List;
      if (mounted) {
        setState(() {
          _streetPolyline = coords
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
        });
      }
    } catch (_) {}
  }

  /// Open Google Maps with the given travel mode (used for transit).
  Future<void> _openGoogleMaps(double destLat, double destLng, String mode) async {
    final pos = ref.read(mapProvider).position;
    final origin = pos != null ? '${pos.latitude},${pos.longitude}' : '';
    final gmMode = mode == 'transit' ? 'transit' : mode == 'driving' ? 'driving' : 'walking';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '${origin.isNotEmpty ? "&origin=$origin" : ""}'
      '&destination=$destLat,$destLng'
      '&travelmode=$gmMode',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _fetchNavPolylineOnly(LandmarkModel landmark, String mode) async {
    if (mode == 'transit') {
      // Transit: clear any existing polyline - direction is handled via Google Maps
      setState(() { _navPolyline = const []; _navDurationSec = null; });
      return;
    }
    final pos = ref.read(mapProvider).position;
    if (pos == null) return;
    try {
      final waypoints = '${pos.longitude},${pos.latitude};${landmark.location.lng},${landmark.location.lat}';
      final res = await Dio().get(
        _osrmUrl(mode, waypoints),
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      final route = res.data['routes'][0];
      final coords = route['geometry']['coordinates'] as List;
      final duration = (route['duration'] as num).toInt();
      if (!mounted) return;
      setState(() {
        _navPolyline = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        _navDurationSec = duration;
      });
    } catch (_) {}
  }

  Future<void> _navigateToLandmark(LandmarkModel landmark, {String? mode}) async {
    final navMode = mode ?? _navMode;
    setState(() { _navTarget = landmark; _navPolyline = const []; _navMode = navMode; });
    ref.read(flProvider.notifier).recordEngagement(landmark, flLabelNavigationStarted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(0.42, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
    final pos = ref.read(mapProvider).position;
    if (pos == null) return;
    await _fetchNavPolylineOnly(landmark, navMode);
    if (!mounted) return;
    // Keep map focused on user's location at a comfortable zoom - don't zoom out to fit the whole route
    _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
  }

  Future<void> _fetchGeneratedRouteOverview(RouteModel route) async {
    if (route.stops.isEmpty || _navMode == 'transit') return;
    final pos = ref.read(mapProvider).position;
    try {
      final stopPoints = route.stops
          .map((s) => '${s.landmark.location.lng},${s.landmark.location.lat}')
          .join(';');
      final waypoints = pos != null
          ? '${pos.longitude},${pos.latitude};$stopPoints'
          : stopPoints;
      final res = await Dio().get(
        _osrmUrl(_navMode, waypoints),
        queryParameters: {'overview': 'false'},
      );
      final osrmRoute = res.data['routes'][0];
      final duration = (osrmRoute['duration'] as num).toInt();
      final distM = (osrmRoute['distance'] as num).toInt();
      if (mounted) setState(() { _routeDurationSec = duration; _routeDistanceM = distM; });
    } catch (_) {}
  }

  Future<void> _fetchRouteOverview(RouteWithProgress route) async {
    if (route.stops.isEmpty || _navMode == 'transit') return;
    final pos = ref.read(mapProvider).position;
    try {
      final stopPoints = route.stops
          .map((s) => '${s.landmark.location.lng},${s.landmark.location.lat}')
          .join(';');
      // Prepend user's current location so the line starts from where they are
      final waypoints = pos != null
          ? '${pos.longitude},${pos.latitude};$stopPoints'
          : stopPoints;
      final res = await Dio().get(
        _osrmUrl(_navMode, waypoints), // respects current walk/drive mode
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      final osrmRoute = res.data['routes'][0];
      final coords = osrmRoute['geometry']['coordinates'] as List;
      final duration = (osrmRoute['duration'] as num).toInt();
      final distM = (osrmRoute['distance'] as num).toInt();
      if (mounted) {
        setState(() {
          _overviewPolyline = coords
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          _routeDurationSec = duration;
          _routeDistanceM = distM;
        });
      }
    } catch (_) {
      // Straight-line fallback from user position through all stops
      if (mounted) {
        setState(() {
          _overviewPolyline = [
            if (pos != null) LatLng(pos.latitude, pos.longitude),
            ...route.stops.map((s) => LatLng(s.landmark.location.lat, s.landmark.location.lng)),
          ];
        });
      }
    }
  }

  Future<void> _fetchStreetRouteToLandmark(LandmarkModel target, dynamic origin) async {
    if (origin == null) return;
    try {
      final waypoints = '${origin.longitude},${origin.latitude};${target.location.lng},${target.location.lat}';
      final res = await Dio().get(
        _osrmUrl('walking', waypoints),
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      final coords = res.data['routes'][0]['geometry']['coordinates'] as List;
      if (mounted) {
        setState(() {
          _streetPolyline = coords
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
        });
      }
    } catch (_) {}
  }

  void _showSuggestSheet(LatLng? picked) {
    final theme = Theme.of(context);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedType = 'monument';
    const types = ['monument', 'museum', 'park', 'gallery', 'restaurant', 'building', 'square'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Suggest a Location', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Your submission will be reviewed by an admin.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setSheetState(() => selectedType = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.location_pin, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        picked != null
                            ? '${picked.latitude.toStringAsFixed(5)}, ${picked.longitude.toStringAsFixed(5)}'
                            : 'No location selected',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked == null || nameCtrl.text.trim().isEmpty
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            setState(() => _pickedLocation = null);
                            try {
                              await ref.read(apiServiceProvider).post('/landmarks/submit', data: {
                                'name': nameCtrl.text.trim(),
                                'type': selectedType,
                                'location': {'lat': picked.latitude, 'lng': picked.longitude},
                                'description': descCtrl.text.trim(),
                              });
                              if (mounted) {
                                final m = ScaffoldMessenger.of(context);
                                m.clearSnackBars();
                                m.showSnackBar(SnackBar(
                                  content: const Text('Submitted! An admin will review your suggestion.'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.only(
                                    left: 16, right: 16,
                                    bottom: MediaQuery.of(context).size.height * 0.32,
                                  ),
                                ));
                              }
                            } catch (_) {
                              if (mounted) {
                                final m = ScaffoldMessenger.of(context);
                                m.clearSnackBars();
                                m.showSnackBar(SnackBar(
                                  content: const Text('Submission failed. Please try again.'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.only(
                                    left: 16, right: 16,
                                    bottom: MediaQuery.of(context).size.height * 0.32,
                                  ),
                                ));
                              }
                            }
                          },
                    child: const Text('Submit for Review'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _pickedLocation = null);
    });
  }

  void _showCreateRouteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateRouteSheet(
        allLandmarks: ref.read(mapProvider).allLandmarks,
        onCreated: () => ref.read(mapProvider.notifier).fetchGlobalRoutes(),
      ),
    );
  }

  void _showCommunityReview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CommunityReviewSheet(),
    );
  }

  void _showPendingSubmissions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminSubmissionsSheet(
        onOpenLandmark: _showLandmarkSheet,
        onMoveMap: (lat, lng) => _mapController.move(LatLng(lat, lng), 16),
      ),
    );
  }

  // ── Events ──────────────────────────────────────────────────────────────────

  Future<List<EventModel>> _fetchEvents(String landmarkId) async {
    try {
      final res = await ref.read(apiServiceProvider).get('/events/landmark/$landmarkId');
      return (res.data as List).map((j) => EventModel.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  void _showNearbyEventsSheet() {
    final pos = ref.read(mapProvider).position;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NearbyEventsSheet(pos: pos, onLandmarkTap: _showLandmarkSheet),
    );
  }

  void _showAddEventDialog(String landmarkId, String landmarkName) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    bool allDay = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Add Event - $landmarkName'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Event title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('All day'),
                value: allDay,
                onChanged: (v) => setD(() { allDay = v; if (v && startDate != null) { endDate = null; } }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(startDate == null
                    ? 'Pick start date${allDay ? '' : ' & time'}'
                    : allDay
                        ? DateFormat('dd MMM yyyy').format(startDate!)
                        : DateFormat('dd MMM yyyy HH:mm').format(startDate!)),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null) return;
                  if (allDay) {
                    setD(() { startDate = DateTime(d.year, d.month, d.day, 0, 0); endDate = DateTime(d.year, d.month, d.day, 23, 59); });
                  } else {
                    final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 18, minute: 0));
                    if (t == null) return;
                    setD(() => startDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(endDate == null
                    ? 'Pick end date (optional)'
                    : allDay
                        ? DateFormat('dd MMM yyyy').format(endDate!)
                        : DateFormat('dd MMM yyyy HH:mm').format(endDate!)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null) return;
                  if (allDay) {
                    setD(() => endDate = DateTime(d.year, d.month, d.day, 23, 59));
                  } else {
                    final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 20, minute: 0));
                    if (t == null) return;
                    setD(() => endDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  }
                },
                trailing: endDate != null
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setD(() => endDate = null))
                    : null,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty || startDate == null ? null : () async {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context); // close landmark sheet
                try {
                  await ref.read(apiServiceProvider).post(
                    '/events/?landmark_id=$landmarkId',
                    data: {
                      'title': titleCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'start_time': startDate!.toIso8601String(),
                      'end_time': endDate?.toIso8601String(),
                    },
                  );
                  if (mounted) {
                    final m = ScaffoldMessenger.of(context);
                    m.clearSnackBars();
                    m.showSnackBar(SnackBar(
                      content: const Text('Event added!'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).size.height * 0.32),
                    ));
                  }
                } catch (e) {
                  if (mounted) {
                    final msg = e is DioException ? (e.response?.data['detail'] ?? 'Failed') : 'Failed';
                    final m = ScaffoldMessenger.of(context); m.clearSnackBars();
                    m.showSnackBar(SnackBar(content: Text(msg.toString()),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        margin: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).size.height * 0.32)));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestQuestDialog(String landmarkId, String landmarkName) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String questType = 'mission';
    const types = ['educational', 'challenge', 'mission', 'virtual_note'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Suggest a Quest for $landmarkName'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                onChanged: (_) => setD(() {}),
                decoration: const InputDecoration(labelText: 'Quest title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: questType,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setD(() => questType = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                maxLength: 600,
                onChanged: (_) => setD(() {}),
                decoration: const InputDecoration(labelText: 'Description / challenge text', border: OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty || descCtrl.text.trim().isEmpty ? null : () async {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context); // close landmark sheet
                try {
                  final res = await ref.read(apiServiceProvider).post(
                    '/quests/submit/$landmarkId',
                    data: {
                      'type': questType,
                      'title': titleCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'points': 50,
                      'options': [],
                    },
                  );
                  if (mounted) {
                    final approved = (res.data as Map)['status'] == 'approved';
                    ref.read(authProvider.notifier).refreshUser();
                    final lm = ref.read(mapProvider).allLandmarks.where((x) => x.id == landmarkId).firstOrNull;
                    if (lm != null) ref.read(flProvider.notifier).recordEngagement(lm, flLabelQuestSuggested);
                    final m = ScaffoldMessenger.of(context);
                    m.clearSnackBars();
                    m.showSnackBar(SnackBar(
                      content: Text(approved ? 'Quest added successfully!' : 'Quest submitted for review!'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(left: 16, right: 16,
                          bottom: MediaQuery.of(context).size.height * 0.32),
                    ));
                  }
                } catch (e) {
                  if (mounted) {
                    final msg = e is DioException ? (e.response?.data['detail'] ?? 'Failed') : 'Failed';
                    final m = ScaffoldMessenger.of(context); m.clearSnackBars();
                    m.showSnackBar(SnackBar(content: Text(msg.toString()),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        margin: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).size.height * 0.32)));
                  }
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSetWebsiteDialog(String landmarkId, String landmarkName, String? current) {
    final ctrl = TextEditingController(text: current ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Website for $landmarkName'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL (e.g. https://example.com)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);           // close dialog
              if (mounted) Navigator.pop(context); // close landmark sheet
              try {
                await ref.read(apiServiceProvider).patch(
                  '/landmarks/$landmarkId/website',
                  data: {'website': ctrl.text.trim().isEmpty ? null : ctrl.text.trim()},
                );
                ref.read(mapProvider.notifier).fetchAllLandmarks();
                if (mounted) {
                  final m = ScaffoldMessenger.of(context);
                  m.clearSnackBars();
                  m.showSnackBar(SnackBar(
                    content: const Text('Website updated!'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(left: 16, right: 16,
                        bottom: MediaQuery.of(context).size.height * 0.32),
                  ));
                }
              } catch (_) {}
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSetInfoDialog(
    String landmarkId,
    String landmarkName,
    String? currentHours,
    double? currentPrice,
    String? currentDiscount,
  ) {
    final hoursCtrl    = TextEditingController(text: currentHours ?? '');
    final priceCtrl    = TextEditingController(
      text: currentPrice != null
          ? (currentPrice % 1 == 0 ? currentPrice.toInt().toString() : currentPrice.toStringAsFixed(2))
          : '',
    );
    final discountCtrl = TextEditingController(text: currentDiscount ?? '');
    final formKey      = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hours & Tickets\n$landmarkName', style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: hoursCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Opening hours',
                    hintText: 'e.g. Mon-Fri 09:00-18:00, Sat 10:00-16:00',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Ticket price (RON) - leave blank for free',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                    if (parsed == null || parsed < 0) return 'Enter a valid price or leave blank';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: discountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Discount / reduction info (optional)',
                    hintText: 'e.g. Free for children under 7',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_offer_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
              try {
                final priceRaw = priceCtrl.text.trim().replaceAll(',', '.');
                final price = priceRaw.isEmpty ? null : double.parse(priceRaw);
                await ref.read(apiServiceProvider).patch(
                  '/landmarks/$landmarkId/info',
                  data: {
                    'opening_hours': hoursCtrl.text.trim().isEmpty ? null : hoursCtrl.text.trim(),
                    'ticket_price': price,
                    'discount_info': discountCtrl.text.trim().isEmpty ? null : discountCtrl.text.trim(),
                  },
                );
                ref.read(mapProvider.notifier).fetchAllLandmarks();
                if (mounted) {
                  final m = ScaffoldMessenger.of(context);
                  m.clearSnackBars();
                  m.showSnackBar(SnackBar(
                    content: const Text('Hours & tickets updated!'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(
                      left: 16, right: 16,
                      bottom: MediaQuery.of(context).size.height * 0.32,
                    ),
                  ));
                }
              } catch (_) {}
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddStoryDialog(String landmarkId, String landmarkName) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
        title: Text('Story for $landmarkName'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          maxLength: 500,
          onChanged: (_) => setD(() {}),
          decoration: const InputDecoration(
            hintText: 'Share something memorable about this place…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: ctrl.text.trim().isEmpty ? null : () async {
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context); // close landmark sheet
              try {
                final res = await ref.read(apiServiceProvider).post(
                  '/landmarks/$landmarkId/stories',
                  data: {'text': ctrl.text.trim()},
                );
                if (mounted) {
                  final approved = (res.data as Map)['status'] == 'approved';
                  if (approved) ref.read(mapProvider.notifier).fetchAllLandmarks();
                  ref.read(authProvider.notifier).refreshUser();
                  // Story submission is strong engagement signal
                  final lm = ref.read(mapProvider).allLandmarks.where((x) => x.id == landmarkId).firstOrNull;
                  if (lm != null) ref.read(flProvider.notifier).recordEngagement(lm, flLabelStorySubmitted);
                  final m = ScaffoldMessenger.of(context);
                  m.clearSnackBars();
                  m.showSnackBar(SnackBar(
                    content: Text(approved ? 'Story added successfully!' : 'Story submitted for review!'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(left: 16, right: 16,
                        bottom: MediaQuery.of(context).size.height * 0.32),
                  ));
                }
              } catch (e) {
                if (mounted) {
                  final msg = e is DioException ? (e.response?.data['detail'] ?? 'Failed') : 'Failed';
                  final m = ScaffoldMessenger.of(context); m.clearSnackBars();
                  m.showSnackBar(SnackBar(content: Text(msg.toString()),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Theme.of(context).colorScheme.error,
                      margin: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).size.height * 0.32)));
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
      ),
    );
  }

  void _showNearbyLandmarksList() {
    final landmarks = ref.read(mapProvider).landmarks;
    final theme = Theme.of(context);
    if (landmarks.isEmpty) {
      final m = ScaffoldMessenger.of(context);
      m.clearSnackBars();
      m.showSnackBar(SnackBar(
        content: const Text('No landmarks within 1.5 km'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16,
            bottom: MediaQuery.of(context).size.height * 0.32),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, sc) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: theme.colorScheme.surface,
            child: Column(children: [
              const SizedBox(height: 10),
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Icon(Icons.radar, size: 18),
                  const SizedBox(width: 8),
                  Text('${landmarks.length} Nearby Landmarks',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView.separated(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: landmarks.length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (ctx, i) {
                    final l = landmarks[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: _colorForType(l.type).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconForType(l.type), color: _colorForType(l.type), size: 20),
                      ),
                      title: Text(l.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(l.type, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (l.rating > 0) ...[
                          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(l.rating.toStringAsFixed(1), style: theme.textTheme.labelSmall),
                          const SizedBox(width: 8),
                        ],
                        const Icon(Icons.chevron_right, size: 18),
                      ]),
                      onTap: () {
                        Navigator.pop(context);
                        _showLandmarkSheet(l);
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<List<CommentModel>> _fetchComments(String landmarkId) async {
    try {
      final res = await ref.read(apiServiceProvider).get('/comments/$landmarkId');
      return (res.data as List).map((j) => CommentModel.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  void _showAddCommentDialog(String landmarkId, String landmarkName) {
    final textCtrl = TextEditingController();
    int stars = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Review $landmarkName'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text('Rating:', style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(width: 8),
                ...List.generate(5, (i) => GestureDetector(
                  onTap: () => setD(() => stars = i + 1),
                  child: Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < stars ? Colors.amber.shade600 : Colors.grey,
                    size: 28,
                  ),
                )),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Share your experience…',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: stars == 0 ? null : () async {
                Navigator.pop(ctx); // close dialog; sheet stays open until API returns
                try {
                  final local = ref.read(localDataProvider);
                  final existingCommentId = local.getMyCommentId(landmarkId);
                  final payload = {'text': textCtrl.text.trim(), 'rating': stars};
                  final raw = existingCommentId != null
                      ? await ref.read(apiServiceProvider).patch('/comments/$existingCommentId', data: payload)
                      : await ref.read(apiServiceProvider).post('/comments/$landmarkId', data: payload);
                  final resp = raw.data as Map<String, dynamic>;
                  final commentId = resp['id'] as String?;
                  final flagged = resp['flagged'] as bool? ?? false;
                  // Save comment ID BEFORE closing the sheet so it's available when sheet reopens
                  if (commentId != null) await local.setMyCommentId(landmarkId, commentId);
                  // Rating always updated when reviewing
                  final prev = local.getMyRating(landmarkId);
                  await ref.read(apiServiceProvider).post(
                    '/landmarks/$landmarkId/rate',
                    data: {'rating': stars, 'previous_rating': prev?.round()},
                  );
                  final lm = ref.read(mapProvider).allLandmarks
                      .where((x) => x.id == landmarkId).firstOrNull;
                  if (lm != null) ref.read(flProvider.notifier).recordRating(lm, stars); // review stars override engagement
                  await local.setMyRating(landmarkId, stars.toDouble());
                  ref.read(mapProvider.notifier).fetchAllLandmarks();
                  if (mounted) Navigator.pop(context); // close sheet after ID is saved
                  if (mounted) {
                    final flagSource = resp['flag_source'] as String?;
                    final flagMsg = flagSource == 'openai'
                        ? 'Your review was flagged by AI moderation and won\'t be visible until an admin approves it.'
                        : 'Your review was flagged by our content filter and won\'t be visible until an admin approves it.';
                    final m = ScaffoldMessenger.of(context);
                    m.clearSnackBars();
                    m.showSnackBar(SnackBar(
                      content: Text(flagged ? flagMsg : 'Review submitted!'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(left: 16, right: 16,
                          bottom: MediaQuery.of(context).size.height * 0.32),
                    ));
                  }
                } catch (_) {}
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLandmarkSheet(LandmarkModel stale) {
    final all = ref.read(mapProvider).allLandmarks;
    final l = all.where((x) => x.id == stale.id).firstOrNull ?? stale;
    final theme = Theme.of(context);
    setState(() => _selectedLandmarkId = l.id);
    // Weakest positive signal — user was curious enough to open the sheet
    ref.read(flProvider.notifier).recordEngagement(l, flLabelSheetOpened);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _colorForType(l.type).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(_iconForType(l.type), color: _colorForType(l.type)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              if (l.visitCount > 0) ...[
                Icon(Icons.people_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${l.visitCount}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ]),
            const SizedBox(height: 12),
            Text(l.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (l.openingHours != null && l.openingHours!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.access_time, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(l.openingHours!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary))),
              ]),
            ],
            // Ticket price
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.confirmation_number_outlined, size: 14, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              Text(
                l.ticketPrice == null ? 'Free entry' : 'Ticket: ${l.ticketPrice!.toStringAsFixed(l.ticketPrice! % 1 == 0 ? 0 : 2)} RON',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: l.ticketPrice == null ? Colors.green.shade700 : theme.colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]),
            // Discount info
            if (l.discountInfo != null && l.discountInfo!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.local_offer_outlined, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l.discountInfo!, style: theme.textTheme.bodySmall?.copyWith(height: 1.4))),
                ]),
              ),
            ],
            if (l.stories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${l.stories.length == 1 ? "Story" : "Stories"} (${l.stories.length})',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 6),
              ...l.stories.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 2)),
                  ),
                  child: Text(s, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
                ),
              )),
            ],
            // Website
            if (l.website != null && l.website!.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _launchUrl(l.website!),
                child: Row(children: [
                  Icon(Icons.language, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.website!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ],
            // Set website (submitter or admin)
            if ((l.submittedBy == ref.read(authProvider).user?.id ||
                (ref.read(authProvider).user?.isAdmin ?? false)) &&
                (l.website == null || l.website!.isEmpty)) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showSetWebsiteDialog(l.id, l.name, l.website),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Add website'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            ] else if (l.submittedBy == ref.read(authProvider).user?.id ||
                (ref.read(authProvider).user?.isAdmin ?? false)) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => _showSetWebsiteDialog(l.id, l.name, l.website),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Edit website'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // Add/Edit opening hours & ticket info (submitter or admin)
            if (l.submittedBy == ref.read(authProvider).user?.id ||
                (ref.read(authProvider).user?.isAdmin ?? false)) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => _showSetInfoDialog(l.id, l.name, l.openingHours, l.ticketPrice, l.discountInfo),
                icon: Icon(
                  (l.openingHours == null || l.openingHours!.isEmpty) &&
                      l.ticketPrice == null &&
                      (l.discountInfo == null || l.discountInfo!.isEmpty)
                      ? Icons.add_circle_outline
                      : Icons.edit_outlined,
                  size: 16,
                ),
                label: Text(
                  (l.openingHours == null || l.openingHours!.isEmpty) &&
                      l.ticketPrice == null &&
                      (l.discountInfo == null || l.discountInfo!.isEmpty)
                      ? 'Add hours & tickets'
                      : 'Edit hours & tickets',
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              children: l.categories.map((c) => Chip(label: Text(c), visualDensity: VisualDensity.compact)).toList(),
            ),
            const SizedBox(height: 16),
            _EventsSection(
              landmarkId: l.id,
              submittedBy: l.submittedBy,
              onAdd: () => _showAddEventDialog(l.id, l.name),
              fetchEvents: () => _fetchEvents(l.id),
            ),
            const SizedBox(height: 16),
            // Overall rating always visible (read-only); review button gated by quest completion
            _StarRatingRow(
              averageRating: l.rating,
              myRating: l.myRating,
              canRate: false,
              onRate: null,
            ),
            const SizedBox(height: 16),
            _CommentsSection(
              landmarkId: l.id,
              fetchComments: () => _fetchComments(l.id),
              onAdd: () => _showAddCommentDialog(l.id, l.name),
              hasReview: ref.read(localDataProvider).getMyCommentId(l.id) != null,
            ),
            // Any authenticated user can suggest - submissions go to review
            if (ref.read(authProvider).user != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddStoryDialog(l.id, l.name),
                    icon: const Icon(Icons.auto_stories_outlined, size: 16),
                    label: const Text('Add story'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSuggestQuestDialog(l.id, l.name),
                    icon: const Icon(Icons.quiz_outlined, size: 16),
                    label: const Text('Suggest quest'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            // Walk / Drive / Transit navigation row
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(context); _navigateToLandmark(l, mode: 'walking'); },
                  icon: const Icon(Icons.directions_walk, size: 16),
                  label: const Text('Walk'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(context); _navigateToLandmark(l, mode: 'driving'); },
                  icon: const Icon(Icons.directions_car, size: 16),
                  label: const Text('Drive'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openGoogleMaps(l.location.lat, l.location.lng, 'transit');
                  },
                  icon: const Icon(Icons.directions_bus_outlined, size: 16),
                  label: const Text('Transit'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              // Quests button (full width here)
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final pos = ref.read(mapProvider).position;
                    final isNearby = pos != null &&
                        Geolocator.distanceBetween(
                              pos.latitude, pos.longitude,
                              l.location.lat, l.location.lng,
                            ) <=
                            100.0;
                    // Don't close sheet - quest route slides on top; sheet resurfaces on pop
                    await context.push('/quests/${l.id}',
                        extra: {'name': l.name, 'type': l.type, 'categories': l.categories, 'isNearby': isNearby});
                    // Refresh so visitedByMe updates in the sheet that's still open
                    if (mounted) await ref.read(mapProvider.notifier).fetchAllLandmarks();
                  },
                  icon: const Icon(Icons.task_alt_outlined, size: 18),
                  label: const Text('Quests'),
                ),
              ),
            ]),
            // spacer so the sheet doesn't end abruptly
            const SizedBox(height: 4),
          ],
          ),
        ),
      ),
    );
  }

  void _showProximitySheet(LandmarkModel l) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.near_me, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text('You are nearby!', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _colorForType(l.type).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconForType(l.type), color: _colorForType(l.type), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Text(l.type, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (l.visitCount > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.people_outline, size: 13, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text('${l.visitCount}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Text('About', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(l.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
            if (l.stories.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Local Stories', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...l.stories.map((story) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
                ),
                child: Text(story, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              )),
            ],
            if (l.categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: l.categories.map((c) => Chip(label: Text(c), visualDensity: VisualDensity.compact)).toList(),
              ),
            ],
            const SizedBox(height: 16),
            _EventsSection(
              landmarkId: l.id,
              submittedBy: l.submittedBy,
              onAdd: () => _showAddEventDialog(l.id, l.name),
              fetchEvents: () => _fetchEvents(l.id),
            ),
            const SizedBox(height: 20),
            _StarRatingRow(
              averageRating: l.rating,
              myRating: l.myRating,
              canRate: true,
              onRate: (stars) async {
                ref.read(flProvider.notifier).recordRating(l, stars);
                final prev = ref.read(localDataProvider).getMyRating(l.id);
                try {
                  await ref.read(apiServiceProvider).post(
                    '/landmarks/${l.id}/rate',
                    data: {'rating': stars, 'previous_rating': prev?.round()},
                  );
                  await ref.read(localDataProvider).setMyRating(l.id, stars.toDouble());
                  ref.read(mapProvider.notifier).fetchAllLandmarks();
                } catch (_) {}
              },
            ),
            const SizedBox(height: 16),
            // Contribute - always visible in proximity sheet (user is physically here)
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showAddStoryDialog(l.id, l.name),
                  icon: const Icon(Icons.auto_stories_outlined, size: 16),
                  label: const Text('Add story'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showSuggestQuestDialog(l.id, l.name),
                  icon: const Icon(Icons.quiz_outlined, size: 16),
                  label: const Text('Suggest quest'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Walk / Drive / Transit
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); ref.read(proximityProvider.notifier).dismiss(); _navigateToLandmark(l, mode: 'walking'); },
                icon: const Icon(Icons.directions_walk, size: 14),
                label: const Text('Walk'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
              )),
              const SizedBox(width: 4),
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); ref.read(proximityProvider.notifier).dismiss(); _navigateToLandmark(l, mode: 'driving'); },
                icon: const Icon(Icons.directions_car, size: 14),
                label: const Text('Drive'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
              )),
              const SizedBox(width: 4),
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); ref.read(proximityProvider.notifier).dismiss(); _openGoogleMaps(l.location.lat, l.location.lng, 'transit'); },
                icon: const Icon(Icons.directions_bus_outlined, size: 14),
                label: const Text('Transit'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ref.read(proximityProvider.notifier).dismiss();
                  },
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await context.push('/quests/${l.id}',
                        extra: {'name': l.name, 'type': l.type, 'isNearby': true});
                    if (mounted) await ref.read(mapProvider.notifier).fetchAllLandmarks();
                  },
                  icon: const Icon(Icons.task_alt_outlined, size: 18),
                  label: const Text('Start Quests'),
                ),
              ),
            ]),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedLandmarkId = null);
      ref.read(proximityProvider.notifier).dismiss();
    });
  }

  Color _colorForType(String type) => switch (type) {
        'museum' => Colors.blue,
        'monument' => Colors.orange,
        'park' => Colors.green,
        'gallery' => Colors.purple,
        'restaurant' => Colors.red,
        'square' => Colors.amber.shade700,
        _ => Colors.blueGrey,
      };

  IconData _iconForType(String type) => switch (type) {
        'museum' => Icons.museum_outlined,
        'monument' => Icons.account_balance_outlined,
        'park' => Icons.park_outlined,
        'gallery' => Icons.palette_outlined,
        'restaurant' => Icons.restaurant_outlined,
        'square' => Icons.location_city_outlined,
        'building' => Icons.domain_outlined,
        _ => Icons.place_outlined,
      };
}

// ── Tile cache ─────────────────────────────────────────────────────────────────

final _tileCacheManager = CacheManager(
  Config(
    'cq_map_tiles_v1',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 5000,
  ),
);

class _CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        headers: headers,
        cacheManager: _tileCacheManager,
      );
}

// ── Bottom panel ───────────────────────────────────────────────────────────────

// _BottomPanel is now a single CustomScrollView so dragging anywhere
// (including the handle and tab bar) expands/collapses the sheet.
class _BottomPanel extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final MapState mapState;
  final TabController tabController;
  final void Function(LandmarkModel) onLandmarkTap;
  final LandmarkModel? navTarget;
  final String navMode;
  final void Function(String) onNavModeChanged;
  final VoidCallback onStopNav;
  final int? routeDurationSec;
  final int? routeDistanceM;
  final Future<void> Function(double lat, double lng, String mode) openInMaps;
  final bool headingUp;
  final VoidCallback onHeadingUpToggle;

  const _BottomPanel({
    required this.scrollController,
    required this.mapState,
    required this.tabController,
    required this.onLandmarkTap,
    required this.navTarget,
    required this.navMode,
    required this.onNavModeChanged,
    required this.onStopNav,
    this.routeDurationSec,
    this.routeDistanceM,
    required this.openInMaps,
    required this.headingUp,
    required this.onHeadingUpToggle,
  });

  @override
  ConsumerState<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends ConsumerState<_BottomPanel> {
  bool _routesFetched = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onTabChanged() {
    if (!widget.tabController.indexIsChanging) setState(() {});
    if (widget.tabController.index == 1 && !_routesFetched) {
      _routesFetched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(mapProvider.notifier).fetchMyRoutes();
      });
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _searchQuery = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapState = widget.mapState;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            // ── Handle ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // ── Header area (depends on active mode) ────────────────────────
            if (mapState.activeProgressRoute != null) ...[
              SliverToBoxAdapter(
                child: _ProgressRouteHeader(
                  route: mapState.activeProgressRoute!,
                  navMode: widget.navMode,
                  onNavModeChanged: widget.onNavModeChanged,
                  onClose: () => ref.read(mapProvider.notifier).clearProgressRoute(),
                  durationSec: widget.routeDurationSec,
                  distanceM: widget.routeDistanceM,
                  headingUp: widget.headingUp,
                  onHeadingUpToggle: widget.onHeadingUpToggle,
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final route = mapState.activeProgressRoute!;
                      final nextIdx = route.stops.indexWhere((s) => !s.visited);
                      return _ProgressStopTile(
                        stop: route.stops[i],
                        index: i,
                        isNext: nextIdx == i,
                        onTap: () => widget.onLandmarkTap(route.stops[i].landmark),
                      );
                    },
                    childCount: mapState.activeProgressRoute!.stops.length,
                  ),
                ),
              ),
            ] else if (widget.navTarget != null && mapState.activeRoute == null) ...[
              ..._buildNavTargetSlivers(context, widget.navTarget!, theme, bottomInset),
            ] else if (mapState.activeRoute != null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _RouteHeader(
                    route: mapState.activeRoute!,
                    onClear: () => ref.read(mapProvider.notifier).clearRoute(),
                    headingUp: widget.headingUp,
                    onHeadingUpToggle: widget.onHeadingUpToggle,
                    navMode: widget.navMode,
                    onNavModeChanged: widget.onNavModeChanged,
                    durationSec: widget.routeDurationSec,
                    distanceM: widget.routeDistanceM,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 16)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomInset),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _RouteStopTile(
                      index: i + 1,
                      stop: mapState.activeRoute!.stops[i],
                    ),
                    childCount: mapState.activeRoute!.stops.length,
                  ),
                ),
              ),
            ] else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TabBar(
                    controller: widget.tabController,
                    tabs: const [Tab(text: 'Explore'), Tab(text: 'My Routes')],
                    labelStyle: theme.textTheme.labelLarge,
                  ),
                ),
              ),
              if (widget.tabController.index == 0) ...[
                // Search bar in its own sliver so the TextField is never recreated
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search landmarks…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
                _buildExploreSliver(context, mapState, bottomInset),
              ] else
                _buildRoutesSliver(context, mapState, bottomInset),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNavTargetSlivers(
      BuildContext context, LandmarkModel l, ThemeData theme, double bottomInset) {
    return [
      // Panel header - mode chips here too for when panel is expanded
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(children: [
            _ModeChip(label: 'Walk', icon: Icons.directions_walk,
                selected: widget.navMode == 'walking', onTap: () => widget.onNavModeChanged('walking')),
            const SizedBox(width: 8),
            _ModeChip(label: 'Drive', icon: Icons.directions_car,
                selected: widget.navMode == 'driving', onTap: () => widget.onNavModeChanged('driving')),
            const SizedBox(width: 8),
            _ModeChip(label: 'Transit', icon: Icons.directions_bus_outlined,
                selected: widget.navMode == 'transit', onTap: () => widget.onNavModeChanged('transit')),
          ]),
        ),
      ),
      const SliverToBoxAdapter(child: Divider(height: 16)),
      // Landmark info
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomInset),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade600.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.navigation, color: Colors.green.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(l.type, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              if (l.rating > 0) ...[
                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 2),
                Text(l.rating.toStringAsFixed(1), style: theme.textTheme.bodySmall),
              ],
            ]),
            const SizedBox(height: 12),
            Text(l.description, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
            if (l.stories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
                ),
                child: Text(l.stories.first, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              ),
            ],
            if (l.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 4,
                  children: l.categories.map((c) => Chip(label: Text(c), visualDensity: VisualDensity.compact)).toList()),
            ],
            const SizedBox(height: 14),
            _StarRatingRow(
              averageRating: l.rating,
              myRating: l.myRating,
              canRate: l.visitedByMe,
              onRate: l.visitedByMe ? (stars) async {
                ref.read(flProvider.notifier).recordRating(l, stars);
                final prev = ref.read(localDataProvider).getMyRating(l.id);
                try {
                  await ref.read(apiServiceProvider).post('/landmarks/${l.id}/rate',
                      data: {'rating': stars, 'previous_rating': prev?.round()});
                  await ref.read(localDataProvider).setMyRating(l.id, stars.toDouble());
                  ref.read(mapProvider.notifier).fetchAllLandmarks();
                } catch (_) {}
              } : null,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/quests/${l.id}',
                    extra: {'name': l.name, 'type': l.type, 'isNearby': false}),
                icon: const Icon(Icons.task_alt_outlined, size: 18),
                label: const Text('View Quests'),
              ),
            ),
            if (widget.navMode == 'transit') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => widget.openInMaps(l.location.lat, l.location.lng, 'transit'),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in Google Maps'),
                ),
              ),
            ],
          ]),
        ),
      ),
    ];
  }

  Widget _buildExploreSliver(BuildContext context, MapState mapState, double bottomInset) {
    final theme = Theme.of(context);

    // If searching, filter allLandmarks; otherwise show nearby list
    final isSearching = _searchQuery.isNotEmpty;
    final displayList = isSearching
        ? mapState.allLandmarks
            .where((l) => l.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList()
        : mapState.landmarks;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (!isSearching)
            Row(children: [
              Expanded(
                child: Text(
                  mapState.isLoadingLandmarks ? 'Loading…' : '${mapState.landmarks.length} landmarks nearby',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Reload landmarks',
                onPressed: mapState.isLoadingLandmarks
                    ? null
                    : () => ref.read(mapProvider.notifier).seedAndReload(),
                icon: mapState.isLoadingLandmarks
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: mapState.isGeneratingRoute || mapState.landmarks.isEmpty
                    ? null
                    : () => ref.read(mapProvider.notifier).generateRoute(),
                icon: mapState.isGeneratingRoute
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.route, size: 18),
                label: const Text('Generate Route'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ]),
          if (isSearching) ...[
            const SizedBox(height: 6),
            Text('${displayList.length} result${displayList.length == 1 ? "" : "s"}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 8),
          if (displayList.isEmpty && !mapState.isLoadingLandmarks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Column(children: [
                Icon(Icons.location_off_outlined, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text(isSearching ? 'No landmarks match "$_searchQuery"' : 'No landmarks nearby',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ])),
            )
          else
            ...displayList.map((l) => _LandmarkTile(
              landmark: l,
              onTap: () => widget.onLandmarkTap(l),
            )),
        ]),
      ),
    );
  }

  Widget _buildRoutesSliver(BuildContext context, MapState mapState, double bottomInset) {
    final theme = Theme.of(context);
    if (mapState.isLoadingRoutes) {
      return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
    }

    final items = <Widget>[];

    // ── My Routes (locally stored, user-generated) ─────────────────────────
    items.add(Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Row(children: [
        const Icon(Icons.person_outlined, size: 16),
        const SizedBox(width: 6),
        Text('My Routes', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ]),
    ));
    if (mapState.myRoutes.isEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('No generated routes yet - use Explore to generate one.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ));
    } else {
      for (final r in mapState.myRoutes) items.add(_RouteCard(route: r));
    }

    // ── Curated Routes (global, visible to all) ────────────────────────────
    if (mapState.globalRoutes.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
        child: Row(children: [
          Icon(Icons.public, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('Curated Routes',
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        ]),
      ));
      for (final r in mapState.globalRoutes) items.add(_RouteCard(route: r));
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomInset),
      sliver: SliverList(delegate: SliverChildListDelegate(items)),
    );
  }
}

class _RouteCard extends ConsumerWidget {
  final RouteWithProgress route;

  const _RouteCard({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = route.stops.length;
    final visited = route.visitedCount;
    final progress = total > 0 ? visited / total : 0.0;
    final isComplete = visited == total && total > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (route.isGlobal)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.public, size: 14, color: theme.colorScheme.primary),
                ),
              Expanded(
                child: Text(
                  route.name ?? 'Generated Route',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (!route.isGlobal)
                GestureDetector(
                  onTap: () {
                    final ctrl = TextEditingController(text: route.name ?? '');
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Name this route'),
                        content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Morning walk',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ref.read(mapProvider.notifier).renameRoute(route.id, ctrl.text);
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
              const SizedBox(width: 6),
              if (isComplete)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Text('Complete', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.place_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('$total stops', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${route.stops.fold<int>(0, (s, stop) => s + stop.dwellMinutes)} min at stops', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Icon(Icons.straighten_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${(route.totalDistanceM / 1000).toStringAsFixed(1)} km', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(
                      isComplete ? Colors.green : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$visited/$total', style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isComplete ? Colors.green.shade700 : theme.colorScheme.primary,
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => ref.read(mapProvider.notifier).viewRouteOnMap(route),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('View'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Progress route detail ──────────────────────────────────────────────────────

class _ProgressRouteHeader extends StatelessWidget {
  final RouteWithProgress route;
  final VoidCallback onClose;
  final String navMode;
  final void Function(String) onNavModeChanged;
  final int? durationSec;
  final int? distanceM;
  final bool headingUp;
  final VoidCallback onHeadingUpToggle;

  const _ProgressRouteHeader({
    required this.route,
    required this.onClose,
    required this.navMode,
    required this.onNavModeChanged,
    this.durationSec,
    this.distanceM,
    required this.headingUp,
    required this.onHeadingUpToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dwellTotal = route.stops.fold<int>(0, (s, stop) => s + stop.dwellMinutes);
    final travelLabel = durationSec != null
        ? '~${(durationSec! / 60).ceil()} min ${navMode == "driving" ? "drive" : "walk"} · '
        : '';
    final effectiveDistM = distanceM ?? route.totalDistanceM;
    final kmLabel = effectiveDistM > 0
        ? '${(effectiveDistM / 1000).toStringAsFixed(1)} km · '
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(route.name ?? 'Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text('$travelLabel${kmLabel}$dwellTotal min at stops · ${route.visitedCount}/${route.stops.length} visited',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          // Heading-up toggle
          GestureDetector(
            onTap: onHeadingUpToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: headingUp ? theme.colorScheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
              ),
              child: Icon(Icons.explore,
                  size: 18,
                  color: headingUp ? theme.colorScheme.primary : theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _ModeChip(label: 'Walk', icon: Icons.directions_walk,
              selected: navMode == 'walking', onTap: () => onNavModeChanged('walking')),
          const SizedBox(width: 8),
          _ModeChip(label: 'Drive', icon: Icons.directions_car,
              selected: navMode == 'driving', onTap: () => onNavModeChanged('driving')),
        ]),
      ]),
    );
  }
}

class _ProgressStopTile extends StatelessWidget {
  final RouteStopWithProgress stop;
  final int index;
  final bool isNext;
  final VoidCallback? onTap;
  const _ProgressStopTile({
    super.key,
    required this.stop,
    required this.index,
    required this.isNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: stop.visited ? Colors.green.shade600 : isNext ? theme.colorScheme.primary : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: stop.visited
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : isNext
                    ? const Icon(Icons.navigation, color: Colors.white, size: 14)
                    : Text('${index + 1}', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(stop.landmark.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: stop.visited ? theme.colorScheme.onSurfaceVariant : null,
                    )),
              ),
              if (isNext)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text('Next', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                ),
            ]),
            Text(stop.landmark.type, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        if (stop.visited) Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
        if (onTap != null)
          const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right, size: 16)),
      ]),
      ),  // closes Padding
    );   // closes InkWell
    return tile;
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _RouteHeader extends StatelessWidget {
  final RouteModel route;
  final VoidCallback onClear;
  final bool headingUp;
  final VoidCallback onHeadingUpToggle;
  final String navMode;
  final void Function(String) onNavModeChanged;
  final int? durationSec;
  final int? distanceM;

  const _RouteHeader({
    required this.route,
    required this.onClear,
    required this.headingUp,
    required this.onHeadingUpToggle,
    required this.navMode,
    required this.onNavModeChanged,
    this.durationSec,
    this.distanceM,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dwellTotal = route.stops.fold<int>(0, (s, stop) => s + stop.estimatedDurationMinutes);
    final travelLabel = durationSec != null
        ? '~${(durationSec! / 60).ceil()} min ${navMode == "driving" ? "drive" : "walk"} · '
        : '';
    final effectiveDistM = distanceM ?? route.totalDistanceM;
    final kmLabel = effectiveDistM > 0
        ? '${(effectiveDistM / 1000).toStringAsFixed(1)} km · '
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                '${route.stops.length} stops · $travelLabel${kmLabel}$dwellTotal min at stops',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          GestureDetector(
            onTap: onHeadingUpToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: headingUp ? theme.colorScheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
              ),
              child: Icon(Icons.explore, size: 18,
                  color: headingUp ? theme.colorScheme.primary : theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _ModeChip(label: 'Walk', icon: Icons.directions_walk,
              selected: navMode == 'walking', onTap: () => onNavModeChanged('walking')),
          const SizedBox(width: 8),
          _ModeChip(label: 'Drive', icon: Icons.directions_car,
              selected: navMode == 'driving', onTap: () => onNavModeChanged('driving')),
        ]),
      ],
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  final int index;
  final RouteStop stop;

  const _RouteStopTile({required this.index, required this.stop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: theme.colorScheme.primary, child: Text('$index', style: const TextStyle(color: Colors.white, fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stop.landmark.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text('~${stop.estimatedDurationMinutes} min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _LandmarkTile extends StatelessWidget {
  final LandmarkModel landmark;
  final VoidCallback? onTap;

  const _LandmarkTile({required this.landmark, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.place_outlined, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(landmark.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(landmark.type, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

// ── Admin: pending submissions ─────────────────────────────────────────────────

// ── Community review sheet ─────────────────────────────────────────────────────

// ── Admin: create global route ─────────────────────────────────────────────────

class _CreateRouteSheet extends ConsumerStatefulWidget {
  final List<LandmarkModel> allLandmarks;
  final VoidCallback onCreated;
  const _CreateRouteSheet({required this.allLandmarks, required this.onCreated});
  @override
  ConsumerState<_CreateRouteSheet> createState() => _CreateRouteSheetState();
}

class _CreateRouteSheetState extends ConsumerState<_CreateRouteSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _search = '';
  final List<LandmarkModel> _stops = [];
  final Map<String, int> _dwellMinutes = {}; // landmarkId → minutes
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LandmarkModel> get _filtered {
    final q = _search.toLowerCase();
    return q.isEmpty
        ? widget.allLandmarks
        : widget.allLandmarks.where((l) =>
            l.name.toLowerCase().contains(q) || l.type.toLowerCase().contains(q)).toList();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _stops.length < 2) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).post('/routes/admin', data: {
        'name': _nameCtrl.text.trim(),
        'stop_ids': _stops.map((l) => l.id).toList(),
        'dwell_minutes': _stops.map((l) => _dwellMinutes[l.id] ?? 25).toList(),
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final msg = e is DioException ? (e.response?.data['detail'] ?? 'Failed') : 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(children: [
            const SizedBox(height: 10),
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.add_road, size: 20),
                const SizedBox(width: 8),
                Text('Create Global Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Route name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                // Selected stops
                if (_stops.isNotEmpty) ...[
                  Text('Stops (${_stops.length}/10)', style: theme.textTheme.labelLarge?.copyWith(
                      color: _stops.length >= 10 ? theme.colorScheme.error : theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(_stops.length, (i) {
                    final l = _stops[i];
                    final dwell = _dwellMinutes[l.id] ?? 30;
                    return ListTile(
                      key: ValueKey(l.id),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      minVerticalPadding: 0,
                      leading: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                        child: Center(child: Text('${i+1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      ),
                      title: Text(l.name, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: dwell > 5 ? () => setState(() => _dwellMinutes[l.id] = dwell - 5) : null,
                          child: const Icon(Icons.remove_circle_outline, size: 16),
                        ),
                        const SizedBox(width: 2),
                        SizedBox(width: 30, child: Text('${dwell}m', textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: dwell < 180 ? () => setState(() => _dwellMinutes[l.id] = dwell + 5) : null,
                          child: const Icon(Icons.add_circle_outline, size: 16),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() { _stops.removeAt(i); _dwellMinutes.remove(l.id); }),
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ]),
                    );
                  }),    // closes List.generate itemBuilder
                      ),   // closes Column
                    ),     // closes SingleChildScrollView
                  ),       // closes ConstrainedBox
                  const SizedBox(height: 8),
                ],
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search landmarks to add…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 16),
                            onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ]),
            ),
            const Divider(height: 8),
            Expanded(
              child: ListView.builder(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final l = _filtered[i];
                  final added = _stops.any((s) => s.id == l.id);
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined,
                        color: added ? theme.colorScheme.primary : theme.colorScheme.outline, size: 20),
                    title: Text(l.name, style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: added ? theme.colorScheme.primary : null)),
                    subtitle: Text(l.type, style: theme.textTheme.bodySmall),
                    trailing: added
                        ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
                        : const Icon(Icons.add_circle_outline, size: 20),
                    onTap: () {
                      if (!added && _stops.length < 10) {
                        setState(() {
                          _stops.add(l);
                          _dwellMinutes[l.id] = 25;
                        });
                        ref.read(flProvider.notifier).recordEngagement(l, flLabelAddedToRoute);
                      }
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_stops.length >= 2 && _nameCtrl.text.isNotEmpty && !_saving)
                      ? _save : null,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save route (${_stops.length} stops)'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CommunityReviewSheet extends ConsumerStatefulWidget {
  const _CommunityReviewSheet();
  @override
  ConsumerState<_CommunityReviewSheet> createState() => _CommunityReviewSheetState();
}

class _CommunityReviewSheetState extends ConsumerState<_CommunityReviewSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic> _data = {'landmarks': [], 'stories': [], 'quests': []};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(apiServiceProvider).get('/community/pending');
      setState(() { _data = Map<String, dynamic>.from(res.data as Map); _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _vote(String type, String id) async {
    final key = type == 'story' ? 'stories' : '${type}s';
    final list = (_data[key] as List?) ?? [];
    final idx = list.indexWhere((x) => x['id'] == id);
    if (idx < 0) return;

    final snapshot = Map.from(list[idx] as Map); // keep for rollback
    final currentVotes = (list[idx]['votes'] as int? ?? 0);
    final newVotes = currentVotes + 1;
    final needed = (list[idx]['needed'] as int? ?? 5);
    final approved = newVotes >= needed;

    // Optimistic update
    ref.read(localDataProvider).markVoted(id);
    setState(() {
      if (approved) list.removeAt(idx);
      else list[idx] = Map.from(list[idx] as Map)..['votes'] = newVotes;
    });

    try {
      final res = await ref.read(apiServiceProvider).post('/community/vote/$type/$id');
      if ((res.data as Map)['approved'] == true) {
        ref.read(mapProvider.notifier).fetchAllLandmarks();
      }
    } on DioException catch (e) {
      // Rollback optimistic update on error
      setState(() => list.insert(idx, snapshot));
      if (!mounted) return;
      final detail = (e.response?.data as Map?)?['detail'] as String? ?? 'Vote failed';
      final msg = detail == 'You cannot validate your own submission'
          ? 'This is your own submission - others must validate it.'
          : detail;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stories = (_data['stories'] as List?) ?? [];
    final quests = (_data['quests'] as List?) ?? [];
    final visitedIds = ref.read(localDataProvider).getVisitedIds();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(children: [
            const SizedBox(height: 10),
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.how_to_vote_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Community Review',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('5 = approved', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load, padding: EdgeInsets.zero),
              ]),
            ),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: stories.isEmpty ? 'Stories' : 'Stories (${stories.length})'),
                Tab(text: quests.isEmpty ? 'Quests' : 'Quests (${quests.length})'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _buildVoteList(sc, stories, 'story', theme, visitedIds),
                        _buildVoteList(sc, quests, 'quest', theme, visitedIds),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildVoteList(ScrollController sc, List items, String type, ThemeData theme, Set<String> visitedIds) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
        const SizedBox(height: 8),
        Text('Nothing pending', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
      ]));
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 12),
      itemBuilder: (ctx, i) {
        final p = Map<String, dynamic>.from(items[i] as Map);
        final votes = (p['votes'] as int?) ?? 0;
        final needed = (p['needed'] as int?) ?? 5;
        final userVoted = ref.read(localDataProvider).hasVoted(p['id'] as String? ?? '');
        final isOwn = (p['is_own'] as bool?) ?? false;
        final landmarkId = p['landmark_id'] as String? ?? '';
        final hasVisited = visitedIds.contains(landmarkId);
        final title = p['name'] ?? p['title'] ?? p['text'] ?? '';
        final sub = p['landmark_name'] ?? p['type'] ?? '';

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sub.isNotEmpty)
            Text('📍 $sub', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 3),
          Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: votes / needed,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation(
                    votes >= needed ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$votes/$needed', style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            )),
          ]),
          const SizedBox(height: 8),
          if (isOwn)
            Text('You submitted this - others must validate it',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))
          else if (!hasVisited)
            Text('Complete a quest at this location to validate',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))
          else
            FilledButton.icon(
              onPressed: userVoted ? null : () => _vote(type, p['id']),
              icon: Icon(userVoted ? Icons.check : Icons.thumb_up_outlined, size: 15),
              label: Text(userVoted ? 'Voted' : 'Validate'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                backgroundColor: userVoted ? Colors.grey.shade300 : null,
                foregroundColor: userVoted ? Colors.grey.shade600 : null,
              ),
            ),
        ]);
      },
    );
  }
}

class _AdminSubmissionsSheet extends ConsumerStatefulWidget {
  final void Function(LandmarkModel) onOpenLandmark;
  final void Function(double lat, double lng) onMoveMap;
  const _AdminSubmissionsSheet({required this.onOpenLandmark, required this.onMoveMap});

  @override
  ConsumerState<_AdminSubmissionsSheet> createState() => _AdminSubmissionsSheetState();
}

class _AdminSubmissionsSheetState extends ConsumerState<_AdminSubmissionsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _stories = [];
  List<Map<String, dynamic>> _quests = [];
  List<Map<String, dynamic>> _flaggedComments = [];
  bool _loading = true;
  final _locationSearchCtrl = TextEditingController();
  String _locationSearch = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _locationSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Fetch each independently so one failure doesn't hide the others
      List<Map<String, dynamic>> all = [], stories = [], quests = [];
      try {
        final r = await ref.read(apiServiceProvider).get('/landmarks/admin/submissions');
        all = List<Map<String, dynamic>>.from(r.data as List);
      } catch (_) {}
      try {
        final r = await ref.read(apiServiceProvider).get('/landmarks/admin/pending-stories');
        stories = List<Map<String, dynamic>>.from(r.data as List);
      } catch (_) {}
      try {
        final r = await ref.read(apiServiceProvider).get('/quests/admin/pending');
        quests = List<Map<String, dynamic>>.from(r.data as List);
      } catch (_) {}
      List<Map<String, dynamic>> flagged = [];
      try {
        final r = await ref.read(apiServiceProvider).get('/comments/admin/flagged');
        flagged = List<Map<String, dynamic>>.from(r.data as List);
      } catch (_) {}
      setState(() {
        _all = all; _stories = stories; _quests = quests; _flaggedComments = flagged;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _approveStory(String id) async {
    await ref.read(apiServiceProvider).post('/landmarks/admin/stories/$id/approve');
    ref.read(mapProvider.notifier).fetchAllLandmarks();
    setState(() => _stories.removeWhere((s) => s['id'] == id));
  }

  Future<void> _rejectStory(String id) async {
    await ref.read(apiServiceProvider).post('/landmarks/admin/stories/$id/reject');
    setState(() => _stories.removeWhere((s) => s['id'] == id));
  }

  Future<void> _approveQuest(String id) async {
    await ref.read(apiServiceProvider).post('/quests/admin/$id/approve');
    setState(() => _quests.removeWhere((q) => q['id'] == id));
  }

  Future<void> _rejectQuest(String id) async {
    await ref.read(apiServiceProvider).post('/quests/admin/$id/reject');
    setState(() => _quests.removeWhere((q) => q['id'] == id));
  }


  List<Map<String, dynamic>> get _pending => _all.where((p) => p['status'] == 'pending').toList();
  List<Map<String, dynamic>> get _reviewed => _all.where((p) => p['status'] != 'pending').toList();

  Future<void> _approve(String id) async {
    await ref.read(apiServiceProvider).post('/landmarks/admin/$id/approve');
    // Refresh map so the newly approved landmark appears
    ref.read(mapProvider.notifier).fetchAllLandmarks();
    setState(() {
      final idx = _all.indexWhere((p) => p['id'] == id);
      if (idx != -1) _all[idx] = Map.from(_all[idx])..['status'] = 'approved';
    });
  }

  Future<void> _reject(String id) async {
    await ref.read(apiServiceProvider).post('/landmarks/admin/$id/reject');
    setState(() {
      final idx = _all.indexWhere((p) => p['id'] == id);
      if (idx != -1) _all[idx] = Map.from(_all[idx])..['status'] = 'rejected';
    });
  }

  Future<void> _delete(String id) async {
    await ref.read(apiServiceProvider).delete('/landmarks/admin/$id');
    ref.read(mapProvider.notifier).fetchAllLandmarks();
    setState(() => _all.removeWhere((p) => p['id'] == id));
  }

  void _showEditDialog(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final nameCtrl    = TextEditingController(text: p['name'] ?? '');
    final descCtrl    = TextEditingController(text: p['description'] ?? '');
    final websiteCtrl = TextEditingController(text: p['website'] ?? '');
    String type = p['type'] ?? 'monument';
    const types = ['monument', 'museum', 'park', 'gallery', 'restaurant', 'building', 'square'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Edit Submission'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setD(() => type = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: websiteCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Website URL (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(apiServiceProvider).patch('/landmarks/admin/${p['id']}', data: {
                    'name': nameCtrl.text.trim(),
                    'type': type,
                    'description': descCtrl.text.trim(),
                    'website': websiteCtrl.text.trim().isEmpty ? null : websiteCtrl.text.trim(),
                  });
                  ref.read(mapProvider.notifier).fetchAllLandmarks();
                  setState(() {
                    final idx = _all.indexWhere((x) => x['id'] == p['id']);
                    if (idx != -1) {
                      _all[idx] = Map.from(_all[idx])
                        ..['name'] = nameCtrl.text.trim()
                        ..['type'] = type
                        ..['description'] = descCtrl.text.trim();
                    }
                  });
                } catch (_) {}
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('Submissions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
                ]),
              ),
              TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: _pending.isEmpty
                      ? 'Pending Locations'
                      : 'Pending Locations (${_pending.length})'),
                  Tab(text: _reviewed.isEmpty ? 'Existing Locations' : 'Existing Locations (${_reviewed.length})'),
                  Tab(text: _stories.isEmpty ? 'Stories' : 'Stories (${_stories.length})'),
                  Tab(text: _quests.isEmpty ? 'Quests' : 'Quests (${_quests.length})'),
                  Tab(text: _flaggedComments.isEmpty ? 'Flagged Reviews' : 'Flagged Reviews (${_flaggedComments.length})'),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tab,
                        children: [
                          _buildLocationList(sc, _pending, isPending: true, theme: theme),
                          _buildLocationList(sc, _all, isPending: false, theme: theme),
                          _buildStoriesList(sc, theme),
                          _buildQuestsList(sc, theme),
                          _buildFlaggedCommentsList(sc, theme),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationList(ScrollController sc, List<Map<String, dynamic>> items,
      {required bool isPending, required ThemeData theme}) {
    final query = _locationSearch.toLowerCase();
    final filtered = query.isEmpty
        ? items
        : items.where((p) =>
            (p['name'] as String? ?? '').toLowerCase().contains(query) ||
            (p['type'] as String? ?? '').toLowerCase().contains(query) ||
            (p['description'] as String? ?? '').toLowerCase().contains(query)).toList();

    return Column(children: [
      // Persistent search bar - outside ListView so it doesn't scroll away
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          controller: _locationSearchCtrl,
          decoration: InputDecoration(
            hintText: 'Search locations…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _locationSearch.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _locationSearchCtrl.clear();
                      setState(() => _locationSearch = '');
                    },
                  )
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => setState(() => _locationSearch = v.trim()),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text(
                query.isNotEmpty ? 'No locations match "$query"'
                    : isPending ? 'No pending locations' : 'No locations yet',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)))
            : ListView.separated(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (ctx, i) => _buildLocationItem(filtered[i], theme),
              ),
      ),
    ]);
  }

  Widget _buildLocationItem(Map<String, dynamic> p, ThemeData theme) {
    final st = p['status'] as String? ?? 'pending';
    final statusColor = st == 'approved' ? Colors.green : st == 'rejected' ? Colors.red : Colors.orange;
    final lmId = p['id'] as String?;
    final lm = lmId != null
        ? ref.read(mapProvider).allLandmarks.where((l) => l.id == lmId).firstOrNull
        : null;
    return InkWell(
      onTap: st == 'approved' && lm != null
          ? () { Navigator.pop(context); widget.onMoveMap(lm.location.lat, lm.location.lng); widget.onOpenLandmark(lm); }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(p['name'] ?? '',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.4))),
          child: Text(st, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
          child: Text(p['type'] ?? '', style: theme.textTheme.bodySmall),
        ),
      ]),
      if ((p['description'] as String?)?.isNotEmpty == true) ...[
        const SizedBox(height: 4),
        Text(p['description'], style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
      if (p['location'] != null) ...[
        const SizedBox(height: 4),
        Text(
          '${(p['location']['lat'] as num?)?.toStringAsFixed(5) ?? '?'}, ${(p['location']['lng'] as num?)?.toStringAsFixed(5) ?? '?'}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontFamily: 'monospace'),
        ),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (st == 'pending') ...[
          OutlinedButton.icon(
            onPressed: () => _reject(p['id']),
            icon: const Icon(Icons.close, size: 15),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          ),
          FilledButton.icon(
            onPressed: () => _approve(p['id']),
            icon: const Icon(Icons.check, size: 15),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => _showEditDialog(p),
          icon: const Icon(Icons.edit_outlined, size: 15),
          label: const Text('Edit'),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
        ),
        OutlinedButton.icon(
          onPressed: () => _delete(p['id']),
          icon: const Icon(Icons.delete_outline, size: 15),
          label: const Text('Delete'),
          style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
        ),
      ]),
      ]),
    );
  }

  Widget _buildList(ScrollController sc, List<Map<String, dynamic>> items, {required bool isPending, required ThemeData theme}) {
    if (items.isEmpty) {
      return Center(child: Text(isPending ? 'No pending submissions' : 'No submissions yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)));
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final p = items[i];
        final st = p['status'] as String? ?? 'pending';
        final statusColor = st == 'approved' ? Colors.green : st == 'rejected' ? Colors.red : Colors.orange;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p['name'] ?? '', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: statusColor.withOpacity(0.4))),
              child: Text(st, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
              child: Text(p['type'] ?? '', style: theme.textTheme.bodySmall),
            ),
          ]),
          if ((p['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(p['description'], style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (st == 'pending') ...[
              OutlinedButton.icon(
                onPressed: () => _reject(p['id']),
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error), visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              ),
              FilledButton.icon(
                onPressed: () => _approve(p['id']),
                icon: const Icon(Icons.check, size: 15),
                label: const Text('Approve'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              ),
            ],
            OutlinedButton.icon(
              onPressed: () => _showEditDialog(p),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(p['id']),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error), visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ]),
        ]);
      },
    );
  }

  Widget _buildFlaggedCommentsList(ScrollController sc, ThemeData theme) {
    if (_flaggedComments.isEmpty) {
      return Center(child: Text('No flagged reviews', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)));
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _flaggedComments.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final c = _flaggedComments[i];
        final lmId = c['landmark_id'] as String?;
        final lm = lmId != null
            ? ref.read(mapProvider).allLandmarks.where((l) => l.id == lmId).firstOrNull
            : null;
        return InkWell(
          onTap: lm != null ? () { Navigator.pop(context); widget.onMoveMap(lm.location.lat, lm.location.lng); widget.onOpenLandmark(lm); } : null,
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (lm != null) ...[
            Text(lm.name, style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
          ],
          Text(c['text'] ?? '', style: theme.textTheme.bodySmall?.copyWith(height: 1.4), maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            ...List.generate(5, (j) => Icon(
              j < (c['rating'] as int? ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
              color: Colors.amber.shade500, size: 14,
            )),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(apiServiceProvider).post('/comments/admin/${c['id']}/approve');
                setState(() => _flaggedComments.removeWhere((x) => x['id'] == c['id']));
              },
              icon: const Icon(Icons.check, size: 14),
              label: const Text('Approve'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade400),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(apiServiceProvider).delete('/comments/admin/${c['id']}');
                setState(() => _flaggedComments.removeWhere((x) => x['id'] == c['id']));
              },
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ]),
        ]),
        );
      },
    );
  }

  Widget _buildQuestsList(ScrollController sc, ThemeData theme) {
    if (_quests.isEmpty) {
      return Center(child: Text('No pending quests',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)));
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _quests.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final q = _quests[i];
        final lmId = q['landmark_id'] as String?;
        final lm = lmId != null ? ref.read(mapProvider).allLandmarks.where((l) => l.id == lmId).firstOrNull : null;
        return InkWell(
          onTap: lm != null ? () { Navigator.pop(context); widget.onMoveMap(lm.location.lat, lm.location.lng); widget.onOpenLandmark(lm); } : null,
          borderRadius: BorderRadius.circular(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(q['title'] ?? '', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
              child: Text(q['type'] ?? '', style: theme.textTheme.bodySmall),
            ),
          ]),
          if ((q['landmark_name'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text('📍 ${q['landmark_name']}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
          ],
          if ((q['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(q['description'], style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _rejectQuest(q['id']),
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _approveQuest(q['id']),
              icon: const Icon(Icons.check, size: 15),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ]),
        ]),
        );
      },
    );
  }


  Widget _buildStoriesList(ScrollController sc, ThemeData theme) {
    if (_stories.isEmpty) {
      return Center(child: Text('No pending stories',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)));
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _stories.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final s = _stories[i];
        final lmId = s['landmark_id'] as String?;
        final lm = lmId != null ? ref.read(mapProvider).allLandmarks.where((l) => l.id == lmId).firstOrNull : null;
        return InkWell(
          onTap: lm != null ? () { Navigator.pop(context); widget.onMoveMap(lm.location.lat, lm.location.lng); widget.onOpenLandmark(lm); } : null,
          borderRadius: BorderRadius.circular(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['landmark_name'] ?? 'Unknown landmark',
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
            ),
            child: Text(s['text'] ?? '', style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _rejectStory(s['id']),
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _approveStory(s['id']),
              icon: const Icon(Icons.check, size: 15),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ]),
        ]),
        );
      },
    );
  }
}

// ── Comments section ───────────────────────────────────────────────────────────

class _CommentsSection extends ConsumerStatefulWidget {
  final String landmarkId;
  final Future<List<CommentModel>> Function() fetchComments;
  final VoidCallback onAdd;
  final bool hasReview;
  const _CommentsSection({
    required this.landmarkId,
    required this.fetchComments,
    required this.onAdd,
    required this.hasReview,
  });
  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  late Future<List<CommentModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchComments();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ref.watch re-evaluates on every build - catches re-activation after offstage
    final canAdd = ref.watch(visitedProvider).contains(widget.landmarkId);
    final label = widget.hasReview ? 'Edit' : 'Add';
    return FutureBuilder<List<CommentModel>>(
      future: _future,
      builder: (ctx, snap) {
        // Filter out star-only reviews with no text
        final comments = (snap.data ?? []).where((c) => c.text.trim().isNotEmpty).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.reviews_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('Reviews${comments.isNotEmpty ? " (${comments.length})" : ""}',
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (canAdd)
              TextButton.icon(
                onPressed: () { widget.onAdd(); setState(() { _future = widget.fetchComments(); }); },
                icon: Icon(widget.hasReview ? Icons.edit_outlined : Icons.add, size: 16),
                label: Text(label),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              ),
          ]),
          if (!canAdd)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text('Complete a quest here to leave a review',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
            ),
          if (comments.isEmpty && snap.connectionState == ConnectionState.done)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No reviews yet', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            )
          else
            ...comments.take(3).map((c) {
              final myCommentId = ref.read(localDataProvider).getMyCommentId(widget.landmarkId);
              final isOwn = myCommentId != null && myCommentId == c.id;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isOwn
                        ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                        : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: isOwn
                        ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3))
                        : null,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      ...List.generate(5, (i) => Icon(
                        i < c.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: i < c.rating ? Colors.amber.shade500 : theme.colorScheme.outline,
                        size: 14,
                      )),
                      if (isOwn) ...[
                        const Spacer(),
                        Text('Your review',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(c.text, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                  ]),
                ),
              );
            }),
          if (comments.length > 3)
            TextButton(
              onPressed: () { /* TODO: show all */ },
              child: Text('See all ${comments.length} reviews'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            ),
        ]);
      },
    );
  }
}

// ── Events section ─────────────────────────────────────────────────────────────

class _EventsSection extends ConsumerStatefulWidget {
  final String landmarkId;
  final String? submittedBy;
  final VoidCallback onAdd;
  final Future<List<EventModel>> Function() fetchEvents;

  const _EventsSection({
    required this.landmarkId,
    required this.submittedBy,
    required this.onAdd,
    required this.fetchEvents,
  });

  @override
  ConsumerState<_EventsSection> createState() => _EventsSectionState();
}

class _EventsSectionState extends ConsumerState<_EventsSection> {
  late Future<List<EventModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchEvents();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final canAdd = user?.isAdmin == true || user?.id == widget.submittedBy;
    return FutureBuilder<List<EventModel>>(
      future: _future,
      builder: (ctx, snap) {
        final events = snap.data ?? [];
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 4);
        }
        // Always visible - non-admins see events list (or "No upcoming events")
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('Events', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (canAdd)
              TextButton.icon(
                onPressed: () {
                  widget.onAdd();
                  setState(() { _future = widget.fetchEvents(); });
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              ),
          ]),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text('No upcoming events', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            )
          else
            ...events.map((e) => _EventTile(event: e, theme: theme)),
        ]);
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  final EventModel event;
  final ThemeData theme;
  const _EventTile({required this.event, required this.theme});

  @override
  Widget build(BuildContext context) {
    final color = event.isOngoing ? Colors.green.shade700 : Colors.orange.shade700;
    final badge = event.isOngoing ? 'Happening now' : 'Upcoming';
    final dateStr = DateFormat('dd MMM, HH:mm').format(event.startTime.toLocal());
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(badge, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(event.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        if (event.description.isNotEmpty)
          Text(event.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.access_time, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(dateStr, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (event.endTime != null) ...[
            Text(' – ${DateFormat('HH:mm').format(event.endTime!.toLocal())}',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ]),
      ]),
    );
  }
}

// ── Nearby events sheet ────────────────────────────────────────────────────────

class _NearbyEventsSheet extends ConsumerStatefulWidget {
  final dynamic pos;
  final void Function(LandmarkModel)? onLandmarkTap;

  const _NearbyEventsSheet({required this.pos, this.onLandmarkTap});

  @override
  ConsumerState<_NearbyEventsSheet> createState() => _NearbyEventsSheetState();
}

class _NearbyEventsSheetState extends ConsumerState<_NearbyEventsSheet> {
  List<EventModel> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pos = widget.pos ?? ref.read(mapProvider).position;
    if (pos == null) { setState(() => _loading = false); return; }
    try {
      final res = await ref.read(apiServiceProvider).get(
        '/events/nearby',
        params: {'lat': pos.latitude, 'lng': pos.longitude, 'radius_m': 3000},
      );
      setState(() {
        _events = (res.data as List).map((j) => EventModel.fromJson(j as Map<String, dynamic>)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(children: [
            const SizedBox(height: 10),
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.event_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Events Nearby', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
              ]),
            ),
            const Divider(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _events.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.event_busy_outlined, size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          Text('No events within 3 km', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                        ]))
                      : ListView.separated(
                          controller: sc,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          itemCount: _events.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final e = _events[i];
                            // Find matching landmark for the tap handler
                            final allLandmarks = ref.read(mapProvider).allLandmarks;
                            final landmark = allLandmarks.where((l) => l.id == e.landmarkId).firstOrNull;
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (e.landmarkName != null)
                                GestureDetector(
                                  onTap: landmark != null && widget.onLandmarkTap != null
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onLandmarkTap!(landmark);
                                        }
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(children: [
                                      Icon(Icons.place_outlined, size: 13,
                                          color: landmark != null ? theme.colorScheme.primary : theme.colorScheme.outline),
                                      const SizedBox(width: 4),
                                      Text(
                                        e.landmarkName!,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: landmark != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                                          fontWeight: FontWeight.w600,
                                          decoration: landmark != null ? TextDecoration.underline : null,
                                        ),
                                      ),
                                      if (landmark != null) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.chevron_right, size: 13, color: theme.colorScheme.primary),
                                      ],
                                    ]),
                                  ),
                                ),
                              _EventTile(event: e, theme: theme),
                            ]);
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withOpacity(0.25) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: Text(label, style: TextStyle(
        color: Colors.white,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      )),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
          )),
        ]),
      ),
    );
  }
}

/// Shows the community average rating always.
/// When [canRate] is true (user visited the place), stars are interactive.
/// [myRating] pre-fills the user's existing rating if they already rated.
class _StarRatingRow extends StatefulWidget {
  final double averageRating;
  final double? myRating;
  final bool canRate;
  final Future<void> Function(int stars)? onRate;

  const _StarRatingRow({
    required this.averageRating,
    this.myRating,
    this.canRate = false,
    this.onRate,
  });

  @override
  State<_StarRatingRow> createState() => _StarRatingRowState();
}

class _StarRatingRowState extends State<_StarRatingRow> {
  // 0 = no new selection yet; user always starts fresh so re-rating is always possible
  int _selected = 0;
  bool _submitting = false;
  bool _rated = false; // true after a successful submission this session

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avgStars = widget.averageRating.round().clamp(0, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Overall community rating (always shown, read-only) ──────────────
        Row(children: [
          Text('Overall rating:',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          ...List.generate(5, (i) => Icon(
            i < avgStars ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < avgStars ? Colors.amber.shade300 : theme.colorScheme.outlineVariant,
            size: 22,
          )),
          const SizedBox(width: 6),
          Text(
            widget.averageRating > 0 ? widget.averageRating.toStringAsFixed(1) : '-',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),

        // ── Previous personal rating ──────────────────────────────────────
        if (widget.myRating != null && widget.myRating! > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Your previous rating: ${widget.myRating!.toStringAsFixed(0)} ★',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],

        // ── Interactive rating row (only when canRate) ────────────────────
        if (widget.canRate) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text(
              _rated ? 'Rated!' : 'Rate:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _rated ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant,
                fontWeight: _rated ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            ...List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: _submitting
                    ? null
                    : () async {
                        setState(() { _selected = star; _submitting = true; });
                        await widget.onRate?.call(star);
                        if (mounted) setState(() { _submitting = false; _rated = true; });
                      },
                child: Icon(
                  star <= _selected ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: star <= _selected ? Colors.amber.shade600 : theme.colorScheme.outline,
                  size: 28,
                ),
              );
            }),
            if (_submitting) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ]),
        ],
      ],
    );
  }
}
