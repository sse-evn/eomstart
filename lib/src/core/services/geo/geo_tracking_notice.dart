import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/shift_provider.dart';
import '../geo_tracking_service.dart';

/// A non-blocking notice. GPS trouble does not end shifts or change worked time.
class GeoTrackingNotice extends StatefulWidget {
  final Widget child;
  const GeoTrackingNotice({super.key, required this.child});
  @override
  State<GeoTrackingNotice> createState() => _GeoTrackingNoticeState();
}

class _GeoTrackingNoticeState extends State<GeoTrackingNotice>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  String? _warning;
  String _state = 'ok';
  DateTime? _shiftObserved;
  int? _observedShift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => unawaited(_check()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted || _checking || !supportsGeoTracking) return;
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
      return;
    _checking = true;
    try {
      final provider = context.read<ShiftProvider>();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final shiftId = prefs.getInt(geoShiftKey) ?? provider.activeShift?.id;
      if (shiftId == null) {
        _observedShift = null;
        _show('ok');
        return;
      }
      if (prefs.getInt(geoClosedShiftKey) == shiftId) {
        await provider.loadShifts();
        _show('ok');
        return;
      }
      if (_observedShift != shiftId) {
        _observedShift = shiftId;
        _shiftObserved = DateTime.now();
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!enabled) {
        _show('gps_disabled');
        await reportForegroundGeoStatus(shiftId, 'gps_disabled');
        return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _show('permission_denied');
        await reportForegroundGeoStatus(shiftId, 'permission_denied');
        return;
      }
      // Resume after process death or revoked/regranted permission. No permission
      // dialogs are requested by this periodic check.
      final started = await startBackgroundTracking(shiftId: shiftId);
      if (!started) {
        _show('stopped');
        return;
      }
      await prefs.reload();
      final now = DateTime.now();
      final grace =
          now.difference(_shiftObserved!) < const Duration(seconds: 60);
      final checked = prefs.getInt(geoCheckedKey);
      final uploaded = prefs.getInt(geoLastUploadKey);
      String state = prefs.getString(geoStateKey) ?? 'no_fix';
      final deliveryState = prefs.getString(geoDeliveryStateKey) ?? 'ok';
      if (!grace &&
          (checked == null || now.millisecondsSinceEpoch - checked > 90000)) {
        state = 'stopped';
      } else if (state == 'ok' && deliveryState != 'ok') {
        state = deliveryState;
      } else if (state == 'ok' &&
          !grace &&
          (uploaded == null || now.millisecondsSinceEpoch - uploaded > 90000)) {
        state = 'offline';
      } else if (state == 'ok' && permission != LocationPermission.always) {
        state = 'background_permission';
      } else if (state == 'ok' &&
          defaultTargetPlatform == TargetPlatform.android &&
          !await permissions.Permission.ignoreBatteryOptimizations.isGranted) {
        state = 'battery_optimization';
      }
      _show(grace && state == 'no_fix' ? 'ok' : state);
    } catch (_) {
      if (mounted) _show('stopped');
    } finally {
      _checking = false;
    }
  }

  void _show(String state) {
    if (!mounted) return;
    final warning = geoWarningText(state);
    if (_warning != warning)
      setState(() {
        _warning = warning;
        _state = state;
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_warning != null)
          Material(
              color: Colors.amber.shade100,
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(children: [
                        const Icon(Icons.location_off_outlined,
                            color: Colors.brown),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_warning!,
                                style: const TextStyle(
                                    color: Colors.black87, fontSize: 13))),
                        TextButton(
                            onPressed: () async {
                              try {
                                if (_state == 'gps_disabled') {
                                  await Geolocator.openLocationSettings();
                                } else if (_state == 'battery_optimization') {
                                  await permissions
                                      .Permission.ignoreBatteryOptimizations
                                      .request();
                                  await _check();
                                } else if (_state == 'permission_denied' ||
                                    _state == 'background_permission') {
                                  await Geolocator.openAppSettings();
                                } else {
                                  await _check();
                                }
                              } catch (_) {
                                /* A settings launcher failure must not crash the app. */
                              }
                            },
                            child: Text(_state == 'gps_disabled' ||
                                    _state == 'battery_optimization' ||
                                    _state == 'permission_denied' ||
                                    _state == 'background_permission'
                                ? 'Настройки'
                                : 'Проверить')),
                      ])))),
        Expanded(child: widget.child),
      ]);
}
