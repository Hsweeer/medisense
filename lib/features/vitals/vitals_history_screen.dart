import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../services/vitals_firestore_service.dart';

class VitalsHistoryScreen extends StatefulWidget {
  const VitalsHistoryScreen({super.key});

  @override
  State<VitalsHistoryScreen> createState() => _VitalsHistoryScreenState();
}

class _VitalsHistoryScreenState extends State<VitalsHistoryScreen> {
  List<VitalsRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await VitalsFirestoreService.instance.fetchScans();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = _records.take(7).toList();
    final average = recent.isEmpty
        ? null
        : recent.map((r) => r.bpm).reduce((a, b) => a + b) / recent.length;
    final chartValues = recent.isEmpty
        ? <double>[]
        : recent.reversed.map((r) => r.bpm).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart rate history'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last 7 days',
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          average == null ? 'No scans yet' : '${average.round()} BPM avg',
                          style: GoogleFonts.sora(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recent.isEmpty
                              ? 'Your recent heart-rate scans will appear here.'
                              : '${recent.length} readings tracked',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (recent.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trend',
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 150,
                            child: HeartRateTrendChart(values: chartValues),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (recent.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No heart-rate scans yet. Try a camera-based vitals scan.'),
                      ),
                    )
                  else ...[
                    Text(
                      'Recent readings',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: recent.length,
                        itemBuilder: (context, index) {
                          final scan = recent[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppColors.soft,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.favorite_rounded, color: AppColors.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${scan.bpm.round()} BPM',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatDate(scan.date),
                                        style: const TextStyle(color: AppColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class HeartRateTrendChart extends StatelessWidget {
  const HeartRateTrendChart({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(values: values),
      child: Container(),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      _drawPlaceholder(canvas, size);
      return;
    }

    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 1 ? 1.0 : (max - min).abs();

    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.primary.withValues(alpha: 0.35), AppColors.primary.withValues(alpha: 0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final area = Path();

    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final normalized = ((values[i] - min) / range).clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 14)) - 7;

      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }

    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(area, fillPaint);
    canvas.drawPath(path, paint);

    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final normalized = ((values[i] - min) / range).clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 14)) - 7;
      final dotPaint = Paint()..color = AppColors.primary;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height / 2);
    path.lineTo(size.width, size.height / 2);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}
