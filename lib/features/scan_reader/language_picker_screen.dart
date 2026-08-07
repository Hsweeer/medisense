import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/services/language_pack_manager.dart';
import '../../core/services/tesseract_languages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';

/// Pick which language OCR should read. English works instantly (bundled
/// with the app). Every other language downloads once — over the internet,
/// a few MB — the first time it's picked, then stays cached on-device for
/// every scan after that, with no further network calls.
class LanguagePickerScreen extends StatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _activeCode = 'eng';
  final Set<String> _installed = {'eng'};

  /// code -> 0.0-1.0 while a download is in flight; absent otherwise.
  final Map<String, double> _downloading = {};
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await LanguagePackManager.instance.activeLanguage();
    final installed = <String>{'eng'};
    for (final lang in kTesseractLanguages) {
      if (lang.code == 'eng') continue;
      if (await LanguagePackManager.instance.isInstalled(lang.code)) {
        installed.add(lang.code);
      }
    }
    if (!mounted) return;
    setState(() {
      _activeCode = active;
      _installed
        ..clear()
        ..addAll(installed);
    });
  }

  Future<void> _select(TesseractLanguage lang) async {
    setState(() => _errorCode = null);

    if (!_installed.contains(lang.code)) {
      setState(() => _downloading[lang.code] = 0);
      try {
        await LanguagePackManager.instance.download(
          lang.code,
          onProgress: (p) {
            if (mounted) setState(() => _downloading[lang.code] = p);
          },
        );
        if (!mounted) return;
        setState(() {
          _installed.add(lang.code);
          _downloading.remove(lang.code);
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _downloading.remove(lang.code);
          _errorCode = lang.code;
        });
        showToast(
            context, 'Could not download ${lang.name} — check your connection',
            color: AppColors.danger);
        return;
      }
    }

    await LanguagePackManager.instance.setActiveLanguage(lang.code);
    if (!mounted) return;
    Navigator.of(context).pop(lang);
  }

  Future<void> _delete(TesseractLanguage lang) async {
    await LanguagePackManager.instance.delete(lang.code);
    if (!mounted) return;
    setState(() {
      _installed.remove(lang.code);
      if (_activeCode == lang.code) _activeCode = 'eng';
    });
    showToast(context, '${lang.name} removed');
  }

  List<TesseractLanguage> get _filtered {
    if (_query.trim().isEmpty) return kTesseractLanguages;
    final q = _query.trim().toLowerCase();
    return kTesseractLanguages
        .where((l) =>
            l.name.toLowerCase().contains(q) || l.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.ink,
        title: Text('OCR language',
            style: TextStyle(fontSize: 16.5.sp, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 10.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(fontSize: 14.sp),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search language',
                        hintStyle: TextStyle(color: AppColors.muted, fontSize: 14.sp),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AppColors.muted, size: 20.sp),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    'English works offline instantly. Other languages '
                    'download once (a few MB) the first time you pick '
                    'them, then work offline from then on.',
                    style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted, height: 1.4),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
                itemCount: list.length,
                separatorBuilder: (_, __) => SizedBox(height: 8.h),
                itemBuilder: (context, i) {
                  final lang = list[i];
                  return _LanguageRow(
                    lang: lang,
                    isActive: _activeCode == lang.code,
                    isInstalled: _installed.contains(lang.code),
                    downloadProgress: _downloading[lang.code],
                    hasError: _errorCode == lang.code,
                    onTap: () => _select(lang),
                    onDelete: lang.code != 'eng' && _installed.contains(lang.code)
                        ? () => _delete(lang)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.lang,
    required this.isActive,
    required this.isInstalled,
    required this.downloadProgress,
    required this.hasError,
    required this.onTap,
    required this.onDelete,
  });

  final TesseractLanguage lang;
  final bool isActive;
  final bool isInstalled;
  final double? downloadProgress;
  final bool hasError;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final downloading = downloadProgress != null;
    return MCard(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      border: isActive
          ? Border.all(color: AppColors.primary, width: 1.4.w)
          : Border.all(color: AppColors.line, width: 1.w),
      onTap: downloading ? null : onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lang.name,
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 2.h),
                Text(lang.code,
                    style: TextStyle(fontSize: 11.sp, color: AppColors.muted)),
                if (downloading) ...[
                  SizedBox(height: 8.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: downloadProgress! > 0 ? downloadProgress : null,
                      minHeight: 5.h,
                      backgroundColor: AppColors.line,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!downloading) ...[
            if (isActive)
              Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22.sp)
            else if (isInstalled) ...[
              Icon(Icons.check_rounded, color: AppColors.muted, size: 18.sp),
              SizedBox(width: 6.w),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(16.r),
                  child: Padding(
                    padding: EdgeInsets.all(4.r),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 18.sp, color: AppColors.muted),
                  ),
                ),
            ] else
              Icon(
                hasError ? Icons.error_outline_rounded : Icons.download_rounded,
                color: hasError ? AppColors.danger : AppColors.muted,
                size: 20.sp,
              ),
          ],
        ],
      ),
    );
  }
}