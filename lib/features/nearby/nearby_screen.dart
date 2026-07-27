import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';

/// Nearby care — Google-Maps-style basemap (free CARTO Voyager raster
/// tiles), every hospital + pharmacy pinned at once, and turn-by-turn
/// directions deep-linked into the Google Maps app (no API key, no cost).
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, this.initialType = 0, this.showBack = false});

  /// 0 = all, 1 = hospitals only, 2 = pharmacies only.
  final int initialType;
  final bool showBack;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late int _filter = widget.initialType;
  final _map = MapController();
  Facility? _selected;

  List<Facility> get _facilities => switch (_filter) {
        1 => MockData.hospitals,
        2 => MockData.pharmacies,
        _ => [...MockData.hospitals, ...MockData.pharmacies],
      };

  static Color _accentOf(Facility f) =>
      f.type == FacilityType.hospital ? AppColors.danger : AppColors.primary;

  static IconData _iconOf(Facility f) => f.type == FacilityType.hospital
      ? Icons.local_hospital_rounded
      : Icons.local_pharmacy_rounded;

  Future<void> _openDirections(Facility f) async {
    final dest = '${f.position.latitude},${f.position.longitude}';
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$dest'
        '&travelmode=driving');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showToast(context, 'Could not open Google Maps',
          color: AppColors.danger);
    }
  }

  Future<void> _call(Facility f) async {
    final uri = Uri.parse('tel:${f.phone.replaceAll(RegExp(r'[^\d+]'), '')}');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._facilities]
      ..sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby care'),
        automaticallyImplyLeading: widget.showBack,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: MChip(MockData.userLocationLabel,
                icon: Icons.my_location_rounded,
                background: AppColors.soft,
                foreground: AppColors.onSoft),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips: All · Hospitals · Pharmacies
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                _FilterChip(
                    label: 'All',
                    selected: _filter == 0,
                    onTap: () => _setFilter(0)),
                const SizedBox(width: 8),
                _FilterChip(
                    label: 'Hospitals',
                    icon: Icons.local_hospital_rounded,
                    selected: _filter == 1,
                    onTap: () => _setFilter(1)),
                const SizedBox(width: 8),
                _FilterChip(
                    label: 'Pharmacies',
                    icon: Icons.local_pharmacy_rounded,
                    selected: _filter == 2,
                    onTap: () => _setFilter(2)),
              ],
            ),
          ),
          // Google-style basemap with every facility pinned.
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: MockData.userLocation,
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
                        const Marker(
                          point: MockData.userLocation,
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
                                  selected: _selected == f),
                            ),
                          ),
                      ],
                    ),
                    const SimpleAttributionWidget(
                        source: Text('© OpenStreetMap · © CARTO')),
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
                    onDirections: () => _openDirections(_selected!),
                    onCall: () => _call(_selected!),
                    onClose: () => setState(() => _selected = null),
                  )
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
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: f.type == FacilityType.hospital
                                      ? AppColors.dangerSoft
                                      : AppColors.soft,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child:
                                    Icon(_iconOf(f), color: accent, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(f.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${f.distanceMiles} mi · '
                                        '★ ${f.rating} · ${f.openLabel}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted)),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openDirections(f),
                                icon: Icon(Icons.directions_rounded,
                                    color: accent),
                                tooltip: 'Directions',
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
          border:
              Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.muted),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.inkSoft)),
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
              blurRadius: 10),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(
      {required this.color, required this.icon, required this.selected});

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
                color: Colors.black.withValues(alpha: .25), blurRadius: 8),
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
    required this.onDirections,
    required this.onCall,
    required this.onClose,
  });

  final Facility facility;
  final Color accent;
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
                  child: Text(facility.name,
                      style: GoogleFonts.sora(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.muted, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(facility.address,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MChip('${facility.distanceMiles} mi away',
                    icon: Icons.near_me_rounded,
                    background: AppColors.paper,
                    foreground: AppColors.inkSoft),
                MChip('★ ${facility.rating}',
                    background: AppColors.warningSoft,
                    foreground: AppColors.warning),
                MChip(facility.openLabel,
                    background: AppColors.successSoft,
                    foreground: AppColors.success),
                for (final t in facility.tags)
                  MChip(t,
                      background: AppColors.paper,
                      foreground: AppColors.muted),
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
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('Call',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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
