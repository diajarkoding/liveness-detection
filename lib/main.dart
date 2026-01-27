import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/utils/responsive.dart';
import 'features/liveness/liveness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const LivenessDetectionApp());
}

class LivenessDetectionApp extends StatelessWidget {
  const LivenessDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liveness Detection',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

/// Home screen with button to start liveness verification
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasPermission = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    setState(() {
      _hasPermission = status.isGranted;
      _checkingPermission = false;
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasPermission = status.isGranted;
    });

    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Izin kamera diperlukan untuk verifikasi wajah'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startLiveness() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => LivenessBloc(),
          child: const InstructionScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Initialize responsive utility
    Responsive.init(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F23), Color(0xFF1A1A3E), Color(0xFF2D1B4E)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: Responsive.padding(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Icon
                    Container(
                      width: Responsive.wp(35).clamp(100, 160),
                      height: Responsive.wp(35).clamp(100, 160),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade400,
                            Colors.purple.shade400,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.face_retouching_natural,
                        size: Responsive.wp(18).clamp(50, 80),
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: Responsive.space(40)),

                    // Title
                    Text(
                      'Liveness Detection',
                      style: TextStyle(
                        fontSize: Responsive.sp(28).clamp(24, 36),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: Responsive.space(12)),

                    // Subtitle
                    Text(
                      'Verifikasi identitas dengan deteksi wajah\nreal-time dan anti-spoofing',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: Responsive.sp(15).clamp(13, 18),
                        color: Colors.white.withOpacity(0.7),
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: Responsive.space(50)),

                    // Features list
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFeatureItem(
                          Icons.offline_bolt,
                          'Offline & On-device',
                        ),
                        SizedBox(height: Responsive.space(14)),
                        _buildFeatureItem(
                          Icons.security,
                          'Anti-spoofing Protection',
                        ),
                        SizedBox(height: Responsive.space(14)),
                        _buildFeatureItem(Icons.speed, 'Real-time Analysis'),
                      ],
                    ),
                    SizedBox(height: Responsive.space(50)),

                    // Start Button
                    if (_checkingPermission)
                      const CircularProgressIndicator(color: Colors.white)
                    else if (!_hasPermission)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _requestCameraPermission,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(
                            'Izinkan Akses Kamera',
                            style: TextStyle(
                              fontSize: Responsive.sp(16).clamp(14.0, 18.0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                Responsive.radius(12),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startLiveness,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            'Mulai Verifikasi',
                            style: TextStyle(
                              fontSize: Responsive.sp(16).clamp(14.0, 18.0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                Responsive.radius(12),
                              ),
                            ),
                            elevation: 8,
                            shadowColor: Colors.blue.withOpacity(0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Responsive.space(36),
          height: Responsive.space(36),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(Responsive.radius(8)),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade300,
            size: Responsive.iconSize(20),
          ),
        ),
        SizedBox(width: Responsive.space(12)),
        Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: Responsive.sp(14).clamp(12, 16),
          ),
        ),
      ],
    );
  }
}
