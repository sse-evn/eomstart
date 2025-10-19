// package com.example.eomstart

// import io.flutter.embedding.android.FlutterActivity

// class MainActivity: FlutterActivity() {
//     private val CHANNEL = "com.example/native_tracking"

//     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//         super.configureFlutterEngine(flutterEngine)
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "startTracking" -> {
//                         val token = call.argument<String>("token") ?: ""
//                         val intent = Intent(this, TrackingService::class.java)
//                         intent.putExtra("token", token)
//                         ContextCompat.startForegroundService(this, intent)
//                         result.success(null)
//                     }
//                     "stopTracking" -> {
//                         stopService(Intent(this, TrackingService::class.java))
//                         result.success(null)
//                     }
//                     else -> result.notImplemented()
//                 }
//             }
//     }
// }
