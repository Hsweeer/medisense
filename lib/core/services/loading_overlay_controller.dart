import 'package:get/get.dart';

/// UI-level GetX controller for MediSense's premium loading overlay.
///
/// This does **not** own or drive any business logic — Provider remains the
/// single source of truth for every loading flag in the app (auth,
/// reminders, profile, chat, etc). All existing screens keep deciding *when*
/// to show a loader exactly as before (e.g. `if (auth.isLoading) const
/// AppLoadingOverlay()`).
///
/// [LoadingOverlayController] simply mirrors "is a blocking overlay
/// currently on screen" into a small, context-free, reactive flag so other
/// UI-level code (e.g. the SOS floating overlay button, or a future route
/// guard) can check `LoadingOverlayController.to.isBusy` without needing a
/// `BuildContext` or threading a Provider lookup through the widget tree.
///
/// [AppLoadingOverlay] registers/unregisters itself here on mount/unmount —
/// no screen needs to call this controller directly.
class LoadingOverlayController extends GetxController {
  static LoadingOverlayController get to =>
      Get.isRegistered<LoadingOverlayController>()
          ? Get.find<LoadingOverlayController>()
          : Get.put(LoadingOverlayController(), permanent: true);

  final RxInt _activeOverlays = 0.obs;

  /// True while at least one [AppLoadingOverlay] is mounted anywhere in the
  /// widget tree.
  bool get isBusy => _activeOverlays.value > 0;

  /// Reactive count, exposed for widgets that want to `Obx` on it directly.
  RxInt get activeOverlays => _activeOverlays;

  void register() => _activeOverlays.value++;

  void unregister() {
    if (_activeOverlays.value > 0) _activeOverlays.value--;
  }
}