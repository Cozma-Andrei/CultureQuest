import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  List<LatLng> _streetPolyline = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sheetController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
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
        _fetchStreetRoute(next.activeRoute!.stops, next.position);
      }
      if (next.activeRoute == null && prev?.activeRoute != null) {
        setState(() => _streetPolyline = const []);
      }
      if (next.activeProgressRoute != null && prev?.activeProgressRoute != next.activeProgressRoute) {
        setState(() => _streetPolyline = const []);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached) {
            _sheetController.animateTo(0.45, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
        if (next.resumeTarget != null) {
          _animateToLandmark(next.resumeTarget!);
          _fetchStreetRouteToLandmark(next.resumeTarget!, next.position);
          ref.read(mapProvider.notifier).consumeResumeTarget();
        } else {
          _animateToRoute(next.activeProgressRoute!);
        }
      }
      // Resume target set while route already active (same route re-resumed)
      if (next.resumeTarget != null && prev?.resumeTarget != next.resumeTarget) {
        _animateToLandmark(next.resumeTarget!);
        _fetchStreetRouteToLandmark(next.resumeTarget!, next.position);
        ref.read(mapProvider.notifier).consumeResumeTarget();
      }
      if (next.activeProgressRoute == null && prev?.activeProgressRoute != null) {
        setState(() => _streetPolyline = const []);
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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.culture_quest',
                tileProvider: _CachedTileProvider(),
                panBuffer: 1,
                keepBuffer: 4,
                maxZoom: 19,
              ),
              // Generated route polyline
              if (mapState.activeRoute != null && progressRoute == null)
                PolylineLayer(polylines: [
                  _streetPolyline.isNotEmpty
                      ? Polyline(points: _streetPolyline, strokeWidth: 4, color: Colors.deepPurple)
                      : _buildRoutePolyline(mapState.activeRoute!.stops.map((s) => s.landmark).toList(), mapState.position),
                ]),
              // Progress route: dashed overview between all stops
              if (progressRoute != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: progressRoute.stops.map((s) => LatLng(s.landmark.location.lat, s.landmark.location.lng)).toList(),
                    strokeWidth: 3,
                    color: Colors.deepPurple.withOpacity(0.4),
                    isDotted: true,
                  ),
                ]),
              // Navigation line: street route from user → next stop
              if (progressRoute != null && _streetPolyline.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(points: _streetPolyline, strokeWidth: 4, color: Colors.teal),
                ]),
              // All landmarks layer (dimmed when a progress route is active)
              if (progressRoute == null && mapLandmarks.isNotEmpty)
                MarkerLayer(markers: mapLandmarks.map((l) => _buildLandmarkMarker(l)).toList()),
              // Progress route stop markers
              if (progressRoute != null)
                MarkerLayer(
                  markers: progressRoute.stops.asMap().entries.map((e) =>
                    _buildProgressStopMarker(e.value, e.key + 1)).toList(),
                ),
              if (mapState.position != null)
                MarkerLayer(markers: [_buildUserMarker(mapState.position!)]),
            ],
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

          // Centre-on-me FAB
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height *
                    (_sheetController.isAttached ? _sheetController.size : 0.28) +
                8,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              onPressed: () {
                if (mapState.position != null) {
                  _mapController.move(LatLng(mapState.position!.latitude, mapState.position!.longitude), 15);
                }
              },
              child: mapState.isLocating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),

          // Bottom sheet
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.28,
            minChildSize: 0.15,
            maxChildSize: 0.75,
            builder: (context, scrollController) => _BottomPanel(
              scrollController: scrollController,
              mapState: mapState,
              tabController: _tabController,
            ),
          ),
        ],
      ),
    );
  }

  void _animateToLandmark(LandmarkModel landmark) {
    _mapController.move(LatLng(landmark.location.lat, landmark.location.lng), 16);
  }

  void _animateToRoute(RouteWithProgress route) {
    if (route.stops.isEmpty) return;
    final lats = route.stops.map((s) => s.landmark.location.lat).toList();
    final lngs = route.stops.map((s) => s.landmark.location.lng).toList();
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
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

  Marker _buildLandmarkMarker(LandmarkModel l) => Marker(
        point: LatLng(l.location.lat, l.location.lng),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _showLandmarkSheet(l),
          child: Container(
            decoration: BoxDecoration(
              color: _colorForType(l.type),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Icon(_iconForType(l.type), color: Colors.white, size: 18),
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
        onTap: () => _showLandmarkSheet(stop.landmark),
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
    if (origin == null || stops.isEmpty) return;
    try {
      final waypoints = [
        '${origin.longitude},${origin.latitude}',
        ...stops.map((s) => '${s.landmark.location.lng},${s.landmark.location.lat}'),
      ].join(';');
      final res = await Dio().get(
        'https://router.project-osrm.org/route/v1/walking/$waypoints',
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

  Future<void> _fetchStreetRouteToLandmark(LandmarkModel target, dynamic origin) async {
    if (origin == null) return;
    try {
      final waypoints = '${origin.longitude},${origin.latitude};${target.location.lng},${target.location.lat}';
      final res = await Dio().get(
        'https://router.project-osrm.org/route/v1/walking/$waypoints',
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

  void _showLandmarkSheet(LandmarkModel l) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
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
            if (l.stories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Story', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 4),
              Text(l.stories.first, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              children: l.categories.map((c) => Chip(label: Text(c), visualDensity: VisualDensity.compact)).toList(),
            ),
            const SizedBox(height: 16),
            if (l.visitedByMe)
              _StarRatingRow(
                currentRating: l.rating,
                onRate: (stars) async {
                  ref.read(flProvider.notifier).recordInteraction(l, stars / 5.0);
                  try {
                    await ref.read(apiServiceProvider).post(
                      '/landmarks/${l.id}/rate',
                      data: {'rating': stars},
                    );
                  } catch (_) {}
                },
              ),
            if (l.visitedByMe) const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final pos = ref.read(mapProvider).position;
                  final isNearby = pos != null &&
                      Geolocator.distanceBetween(
                            pos.latitude, pos.longitude,
                            l.location.lat, l.location.lng,
                          ) <=
                          100.0;
                  Navigator.pop(context);
                  context.push('/quests/${l.id}',
                      extra: {'name': l.name, 'type': l.type, 'isNearby': isNearby});
                },
                icon: const Icon(Icons.task_alt_outlined, size: 18),
                label: const Text('View Quests'),
              ),
            ),
          ],
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
            const SizedBox(height: 20),
            _StarRatingRow(
              currentRating: l.rating,
              onRate: (stars) async {
                ref.read(flProvider.notifier).recordInteraction(l, stars / 5.0);
                try {
                  await ref.read(apiServiceProvider).post(
                    '/landmarks/${l.id}/rate',
                    data: {'rating': stars},
                  );
                } catch (_) {}
              },
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(flProvider.notifier).recordInteraction(l, 0.0);
                    Navigator.pop(context);
                    ref.read(proximityProvider.notifier).dismiss();
                  },
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(flProvider.notifier).recordInteraction(l, 0.5);
                    Navigator.pop(context);
                    context.push('/quests/${l.id}',
                        extra: {'name': l.name, 'type': l.type, 'isNearby': true});
                  },
                  icon: const Icon(Icons.task_alt_outlined, size: 18),
                  label: const Text('Start Quests'),
                ),
              ),
            ]),
          ],
        ),
      ),
    ).then((_) => ref.read(proximityProvider.notifier).dismiss());
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

class _BottomPanel extends ConsumerWidget {
  final ScrollController scrollController;
  final MapState mapState;
  final TabController tabController;

  const _BottomPanel({
    required this.scrollController,
    required this.mapState,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),

            if (mapState.activeProgressRoute != null) ...[
              _ProgressRouteHeader(route: mapState.activeProgressRoute!, onClose: () {
                ref.read(mapProvider.notifier).clearProgressRoute();
              }),
              const Divider(height: 1),
              Expanded(
                child: _ProgressRouteStopList(
                  route: mapState.activeProgressRoute!,
                  scrollController: scrollController,
                  bottomInset: bottomInset,
                ),
              ),
            ] else if (mapState.activeRoute != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RouteHeader(route: mapState.activeRoute!, onClear: () => ref.read(mapProvider.notifier).clearRoute()),
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomInset),
                  children: [
                    ...mapState.activeRoute!.stops.asMap().entries.map((e) =>
                      _RouteStopTile(index: e.key + 1, stop: e.value)),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TabBar(
                  controller: tabController,
                  tabs: const [Tab(text: 'Explore'), Tab(text: 'My Routes')],
                  labelStyle: theme.textTheme.labelLarge,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    _ExploreTab(scrollController: scrollController, mapState: mapState, bottomInset: bottomInset),
                    _RoutesTab(scrollController: scrollController, mapState: mapState, bottomInset: bottomInset),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Explore tab ────────────────────────────────────────────────────────────────

class _ExploreTab extends ConsumerWidget {
  final ScrollController scrollController;
  final MapState mapState;
  final double bottomInset;

  const _ExploreTab({required this.scrollController, required this.mapState, required this.bottomInset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomInset),
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                mapState.isLoadingLandmarks
                    ? 'Loading...'
                    : '${mapState.landmarks.length} landmarks nearby',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Load landmarks',
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
          ],
        ),
        const SizedBox(height: 12),
        if (mapState.landmarks.isEmpty && !mapState.isLoadingLandmarks)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Icon(Icons.location_off_outlined, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text('No landmarks nearby', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ]),
            ),
          )
        else
          ...mapState.landmarks.map((l) => _LandmarkTile(landmark: l)),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── My Routes tab ──────────────────────────────────────────────────────────────

class _RoutesTab extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final MapState mapState;
  final double bottomInset;

  const _RoutesTab({required this.scrollController, required this.mapState, required this.bottomInset});

  @override
  ConsumerState<_RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends ConsumerState<_RoutesTab> {
  @override
  void initState() {
    super.initState();
    // Fetch once when the tab is first mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapProvider.notifier).fetchMyRoutes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapState = widget.mapState;

    if (mapState.isLoadingRoutes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mapState.myRoutes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('No routes yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text('Generate a route from the Explore tab', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + widget.bottomInset),
      children: [
        for (final route in mapState.myRoutes)
          _RouteCard(route: route),
      ],
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
              Expanded(
                child: Text(
                  route.name ?? 'Generated Route',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
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
              Text('${route.totalDurationMinutes} min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              const SizedBox(width: 10),
              if (!isComplete)
                FilledButton.icon(
                  onPressed: () => ref.read(mapProvider.notifier).resumeRoute(route),
                  icon: const Icon(Icons.navigation_outlined, size: 16),
                  label: const Text('Resume'),
                  style: FilledButton.styleFrom(
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

  const _ProgressRouteHeader({required this.route, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(route.name ?? 'Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('${route.visitedCount}/${route.stops.length} stops visited',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ]),
    );
  }
}

class _ProgressRouteStopList extends StatelessWidget {
  final RouteWithProgress route;
  final ScrollController scrollController;
  final double bottomInset;

  const _ProgressRouteStopList({required this.route, required this.scrollController, required this.bottomInset});

  @override
  Widget build(BuildContext context) {
    final nextIndex = route.stops.indexWhere((s) => !s.visited);
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
      itemCount: route.stops.length,
      itemBuilder: (context, index) {
        final stop = route.stops[index];
        final isNext = index == nextIndex;
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: stop.visited
                    ? Colors.green.shade600
                    : isNext
                        ? theme.colorScheme.primary
                        : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: stop.visited
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : isNext
                        ? const Icon(Icons.navigation, color: Colors.white, size: 14)
                        : Text('${index + 1}', style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          )),
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
                          color: stop.visited
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        )),
                  ),
                  if (isNext)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Next', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                ]),
                Text(stop.landmark.type,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            if (stop.visited)
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
          ]),
        );
      },
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _RouteHeader extends StatelessWidget {
  final RouteModel route;
  final VoidCallback onClear;

  const _RouteHeader({required this.route, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Route', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('${route.stops.length} stops · ${route.totalDurationMinutes} min · ${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear')),
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

  const _LandmarkTile({required this.landmark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
        ],
      ),
    );
  }
}

class _StarRatingRow extends StatefulWidget {
  final double currentRating;
  final Future<void> Function(int stars) onRate;

  const _StarRatingRow({required this.currentRating, required this.onRate});

  @override
  State<_StarRatingRow> createState() => _StarRatingRowState();
}

class _StarRatingRowState extends State<_StarRatingRow> {
  late int _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentRating.round().clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Rate:', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        ...List.generate(5, (i) {
          final star = i + 1;
          return GestureDetector(
            onTap: _submitting
                ? null
                : () async {
                    setState(() {
                      _selected = star;
                      _submitting = true;
                    });
                    await widget.onRate(star);
                    if (mounted) setState(() => _submitting = false);
                  },
            child: Icon(
              star <= _selected ? Icons.star_rounded : Icons.star_outline_rounded,
              color: star <= _selected ? Colors.amber.shade600 : theme.colorScheme.outline,
              size: 28,
            ),
          );
        }),
        if (_selected > 0) ...[
          const SizedBox(width: 8),
          Text(
            _selected.toStringAsFixed(0),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
