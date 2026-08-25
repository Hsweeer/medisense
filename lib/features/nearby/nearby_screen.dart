import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/overpass_service.dart';
import '../../core/services/facility_cache_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/location_provider.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, this.initialType = 0, this.showBack = false});

  final int initialType;
  final bool showBack;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late int _filter = widget.initialType;
  final _map = MapController();
  Facility? _selected;
  String? _lastCenteredLocation;

  List<Facility> _all = [];
  bool _loading = false;
  String? _error;
  bool _didInitialFetch = false;
  bool _didLiveFetch = false;

  List<Facility> get _facilities => switch (_filter) {
    1 => _all.where((f) => f.type == FacilityType.hospital).toList(),
    2 => _all.where((f) => f.type == FacilityType.pharmacy).toList(),
    _ => _all,
  };

  static Color _accentOf(Facility f) =>
      f.type == FacilityType.hospital ? AppColors.danger : AppColors.primary;

  static IconData _iconOf(Facility f) => f.type == FacilityType.hospital
      ? Icons.local_hospital_rounded
      : Icons.local_pharmacy_rounded;

  double _distanceFor(Facility facility, LocationProvider location) {
    final position = location.position;
    return position == null
        ? facility.distanceMiles
        : facility.milesFrom(position);
  }

  String _distanceLabel(Facility facility, LocationProvider location) =>
      '${_distanceFor(facility, location).toStringAsFixed(1)} mi';

  Future<void> _load(LatLng center) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await OverpassService.instance.fetchNearby(
        latitude: center.latitude,
        longitude: center.longitude,
        userPosition: center,
        radiusMeters: 5000,
      );

      if (results.isNotEmpty) {
        await FacilityCacheService.instance.save(
          latitude: center.latitude,
          longitude: center.longitude,
          facilities: results,
        );
      }

      if (!mounted) return;
      setState(() {
        _all = results;
        _loading = false;
      });
    } on OverpassAllEndpointsFailedException {
      final cached = await FacilityCacheService.instance.load(
        latitude: center.latitude,
        longitude: center.longitude,
      );
      if (!mounted) return;
      final hasCache = cached != null && cached.facilities.isNotEmpty;
      setState(() {
        if (hasCache) _all = cached.facilities;
        // Don't claim "showing saved list" when there isn't one — a
        // fresh install/location with no cache yet needs an honest
        // "couldn't reach live data, try again" message instead of a
        // misleading label with an empty result below it.
        _error = hasCache
            ? 'Showing saved list — live results unavailable.'
            : "Couldn't reach live results. Check your connection and tap refresh to try again.";
        _loading = false;
      });
    } catch (e) {
      debugPrint('[NearbyScreen] _load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach live results. Check your connection and tap refresh to try again.";
        _loading = false;
      });
    }
  }

  Future<void> _openDirections(Facility f) async {
    final dest = '${f.position.latitude},${f.position.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$dest'
          '&travelmode=driving',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showToast(context, 'Could not open Google Maps', color: AppColors.danger);
    }
  }

  Future<void> _call(Facility f) async {
    final uri = Uri.parse('tel:${f.phone.replaceAll(RegExp(r'[^\d+]'), '')}');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationProvider>();
    final userPosition = location.positionOrFallback;

    if (!_didInitialFetch) {
      _didInitialFetch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(userPosition));
    }
    if (!_didLiveFetch && location.position != null) {
      _didLiveFetch = true;
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => _load(location.position!),
      );
    }

    final sorted = [..._facilities]
      ..sort(
            (a, b) =>
            _distanceFor(a, location).compareTo(_distanceFor(b, location)),
      );

    final locationKey = '${userPosition.latitude},${userPosition.longitude}';
    if (location.position != null && _lastCenteredLocation != locationKey) {
      _lastCenteredLocation = locationKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(userPosition, 13.2);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby care'),
        automaticallyImplyLeading: widget.showBack,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(userPosition),
            icon: _loading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.refresh_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: MChip(
              location.displayLabel,
              icon: Icons.my_location_rounded,
              background: AppColors.soft,
              foreground: AppColors.onSoft,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.warningSoft,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == 0,
                  onTap: () => _setFilter(0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Hospitals',
                  icon: Icons.local_hospital_rounded,
                  selected: _filter == 1,
                  onTap: () => _setFilter(1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pharmacies',
                  icon: Icons.local_pharmacy_rounded,
                  selected: _filter == 2,
                  onTap: () => _setFilter(2),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: userPosition,
                    initialZoom: 13.2,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.medisense.medisense_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userPosition,
                          width: 26,
                          height: 26,
                          child: _UserDot(),
                        ),
                        for (final f in _facilities)
                          Marker(
                            point: f.position,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _selected = f);
                                _map.move(f.position, 14);
                              },
                              child: _Pin(
                                color: _accentOf(f),
                                icon: _iconOf(f),
                                selected: _selected == f,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap · © CARTO'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: _selected != null
                ? _FacilityDetail(
              facility: _selected!,
              accent: _accentOf(_selected!),
              distanceLabel: _distanceLabel(_selected!, location),
              onDirections: () => _openDirections(_selected!),
              onCall: () => _call(_selected!),
              onClose: () => setState(() => _selected = null),
            )
                : _facilities.isEmpty && _loading
                ? const Center(child: CircularProgressIndicator())
                : _facilities.isEmpty
                ? _NoResultsView(filter: _filter)
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              itemCount: sorted.length,
              itemBuilder: (_, i) {
                final f = sorted[i];
                final accent = _accentOf(f);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: MCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () {
                      setState(() => _selected = f);
                      _map.move(f.position, 14);
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: f.type == FacilityType.hospital
                                ? AppColors.dangerSoft
                                : AppColors.soft,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            _iconOf(f),
                            color: accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.near_me_rounded,
                                    size: 12,
                                    color: AppColors.muted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _distanceLabel(f, location),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (f.rating > 0) ...[
                                    const SizedBox(width: 8),
                                    const Text(
                                      '★',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      f.rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    f.isOpen
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 12,
                                    color: f.isOpen
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      f.openLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: f.isOpen
                                            ? AppColors.success
                                            : AppColors.danger,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (f.phone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.call_rounded,
                                      size: 12,
                                      color: AppColors.muted,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        f.phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (f.phone.isNotEmpty)
                              IconButton(
                                onPressed: () => _call(f),
                                icon: Icon(
                                  Icons.call_rounded,
                                  color: accent,
                                  size: 20,
                                ),
                                tooltip: 'Call',
                                visualDensity: VisualDensity.compact,
                              ),
                            IconButton(
                              onPressed: () => _openDirections(f),
                              icon: Icon(
                                Icons.directions_rounded,
                                color: accent,
                              ),
                              tooltip: 'Directions',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _setFilter(int f) => setState(() {
    _filter = f;
    _selected = null;
  });
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppColors.muted,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A6DF4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A6DF4).withValues(alpha: .4),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icon, required this.selected});

  final Color color;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.2 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .25),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _FacilityDetail extends StatelessWidget {
  const _FacilityDetail({
    required this.facility,
    required this.accent,
    required this.distanceLabel,
    required this.onDirections,
    required this.onCall,
    required this.onClose,
  });

  final Facility facility;
  final Color accent;
  final String distanceLabel;
  final VoidCallback onDirections;
  final VoidCallback onCall;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: MCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    facility.name,
                    style: GoogleFonts.sora(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              facility.address,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MChip(
                  '$distanceLabel away',
                  icon: Icons.near_me_rounded,
                  background: AppColors.paper,
                  foreground: AppColors.inkSoft,
                ),
                if (facility.rating > 0)
                  MChip(
                    '★ ${facility.rating.toStringAsFixed(1)}',
                    background: AppColors.warningSoft,
                    foreground: AppColors.warning,
                  ),
                MChip(
                  facility.openLabel,
                  background: facility.isOpen
                      ? AppColors.successSoft
                      : AppColors.dangerSoft,
                  foreground: facility.isOpen
                      ? AppColors.success
                      : AppColors.danger,
                ),
                for (final t in facility.tags)
                  MChip(
                    t,
                    background: AppColors.paper,
                    foreground: AppColors.muted,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PrimaryButton(
                    label: 'Directions',
                    icon: Icons.directions_rounded,
                    color: accent,
                    subLabel: 'Opens Google Maps',
                    onPressed: onDirections,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 58,
                    child: OutlinedButton.icon(
                      onPressed: onCall,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accent, width: 1.4),
                        foregroundColor: accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text(
                        'Call',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsView extends StatelessWidget {
  const _NoResultsView({required this.filter});

  final int filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      1 => 'hospitals',
      2 => 'pharmacies',
      _ => 'hospitals or pharmacies',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              'No $label found within 5 km',
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'This area may not have this data mapped on OpenStreetMap yet. '
                  'Try refreshing, or check a different filter.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}