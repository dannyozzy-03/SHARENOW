import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoLogoutService {
  static AutoLogoutService? _instance;
  static AutoLogoutService get instance => _instance ??= AutoLogoutService._();
  
  AutoLogoutService._();

  // Configurable timeouts (in minutes)
  static const int _idleTimeoutMinutes = 3; // minutes of inactivity
  static const int _backgroundTimeoutMinutes = 5; // minutes in background

  Timer? _idleTimer;
  Timer? _backgroundTimer;
  DateTime? _backgroundTimestamp;
  bool _isAppInBackground = false;
  bool _isLogoutInProgress = false;

  static const String _lastActivityKey = 'last_activity_timestamp';
  static const String _backgroundTimeKey = 'background_timestamp';

  /// Initialize the auto-logout service
  void initialize() {
    print('🔐 AutoLogoutService: Initializing...');
    _resetIdleTimer();
    _checkForPreviousBackgroundLogout();
  }

  /// Dispose timers and cleanup
  void dispose() {
    print('🔐 AutoLogoutService: Disposing...');
    _idleTimer?.cancel();
    _backgroundTimer?.cancel();
    _idleTimer = null;
    _backgroundTimer = null;
  }

  /// Call this when user interacts with the app
  void resetUserActivity() {
    if (_isLogoutInProgress) return;
    
    _resetIdleTimer();
    _saveLastActivity();
  }

  /// Call this when app goes to background
  void onAppPaused() {
    if (_isLogoutInProgress) return;
    
    print('🔐 AutoLogoutService: App paused');
    _isAppInBackground = true;
    _backgroundTimestamp = DateTime.now();
    _saveBackgroundTime();
    _startBackgroundTimer();
  }

  /// Call this when app comes to foreground
  void onAppResumed() {
    if (_isLogoutInProgress) return;
    
    print('🔐 AutoLogoutService: App resumed');
    _isAppInBackground = false;
    _backgroundTimer?.cancel();
    
    // Check if we were in background too long
    if (_backgroundTimestamp != null) {
      final backgroundDuration = DateTime.now().difference(_backgroundTimestamp!);
      print('🔐 AutoLogoutService: Was in background for ${backgroundDuration.inMinutes} minutes');
      
      if (backgroundDuration.inMinutes >= _backgroundTimeoutMinutes) {
        _performLogout('App was in background for too long');
        return;
      }
    }
    
    // Reset idle timer when resuming
    _resetIdleTimer();
  }

  /// Reset the idle timer
  void _resetIdleTimer() {
    if (_isLogoutInProgress) return;
    
    _idleTimer?.cancel();
    _idleTimer = Timer(
      Duration(minutes: _idleTimeoutMinutes),
      () => _performLogout('User idle for too long'),
    );
  }

  /// Start background timer
  void _startBackgroundTimer() {
    if (_isLogoutInProgress) return;
    
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(
      Duration(minutes: _backgroundTimeoutMinutes),
      () => _performLogout('App in background for too long'),
    );
  }

  /// Perform the actual logout
  Future<void> _performLogout(String reason) async {
    if (_isLogoutInProgress) return;
    
    _isLogoutInProgress = true;
    print('🔐 AutoLogoutService: Performing logout - $reason');
    
    try {
      // Cancel all timers
      _idleTimer?.cancel();
      _backgroundTimer?.cancel();
      
      // Clear stored timestamps
      await _clearStoredTimes();
      
      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();
      
      print('🔐 AutoLogoutService: User signed out successfully');
    } catch (e) {
      print('🔐 AutoLogoutService: Error during logout - $e');
    } finally {
      _isLogoutInProgress = false;
    }
  }

  /// Save last activity timestamp
  Future<void> _saveLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('🔐 AutoLogoutService: Error saving last activity - $e');
    }
  }

  /// Save background timestamp
  Future<void> _saveBackgroundTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_backgroundTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('🔐 AutoLogoutService: Error saving background time - $e');
    }
  }

  /// Clear stored timestamps
  Future<void> _clearStoredTimes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastActivityKey);
      await prefs.remove(_backgroundTimeKey);
    } catch (e) {
      print('🔐 AutoLogoutService: Error clearing stored times - $e');
    }
  }

  /// Check if user should be logged out based on previous background time
  Future<void> _checkForPreviousBackgroundLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backgroundTimeMs = prefs.getInt(_backgroundTimeKey);
      
      if (backgroundTimeMs != null) {
        final backgroundTime = DateTime.fromMillisecondsSinceEpoch(backgroundTimeMs);
        final backgroundDuration = DateTime.now().difference(backgroundTime);
        
        print('🔐 AutoLogoutService: Previous background duration: ${backgroundDuration.inMinutes} minutes');
        
        if (backgroundDuration.inMinutes >= _backgroundTimeoutMinutes) {
          _performLogout('App was closed for too long');
          return;
        }
      }
    } catch (e) {
      print('🔐 AutoLogoutService: Error checking previous background logout - $e');
    }
  }

  /// Get current timeout settings
  Map<String, int> getTimeoutSettings() {
    return {
      'idleTimeoutMinutes': _idleTimeoutMinutes,
      'backgroundTimeoutMinutes': _backgroundTimeoutMinutes,
    };
  }

  /// Check if logout is in progress
  bool get isLogoutInProgress => _isLogoutInProgress;
}

/// Widget wrapper that tracks user interactions
class AutoLogoutWrapper extends StatefulWidget {
  final Widget child;
  
  const AutoLogoutWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<AutoLogoutWrapper> createState() => _AutoLogoutWrapperState();
}

class _AutoLogoutWrapperState extends State<AutoLogoutWrapper>
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AutoLogoutService.instance.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AutoLogoutService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        AutoLogoutService.instance.onAppResumed();
        break;
      case AppLifecycleState.paused:
        AutoLogoutService.instance.onAppPaused();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App is being closed or minimized
        AutoLogoutService.instance.onAppPaused();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => AutoLogoutService.instance.resetUserActivity(),
      onPointerMove: (_) => AutoLogoutService.instance.resetUserActivity(),
      onPointerUp: (_) => AutoLogoutService.instance.resetUserActivity(),
      child: GestureDetector(
        onTap: () => AutoLogoutService.instance.resetUserActivity(),
        onPanDown: (_) => AutoLogoutService.instance.resetUserActivity(),
        onScaleStart: (_) => AutoLogoutService.instance.resetUserActivity(),
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }
} 