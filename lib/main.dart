// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const kPreviewMode = bool.fromEnvironment('ASTROFIELD_PREVIEW');
var kBridgeBaseUrl = 'http://10.42.0.1:8765/api/v1';
const kBridgeToken = String.fromEnvironment('ASTROFIELD_TOKEN');
const kPreviewTab = int.fromEnvironment(
  'ASTROFIELD_PREVIEW_TAB',
  defaultValue: 2,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kPreviewMode) await _discoverAstroberry();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AstroFieldApp());
}

Future<void> _discoverAstroberry() async {
  const candidates = [
    'http://astroberry.local:8765/api/v1',
    'http://10.42.0.1:8765/api/v1',
  ];
  for (final candidate in candidates) {
    try {
      final response = await http
          .get(Uri.parse('$candidate/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        kBridgeBaseUrl = candidate;
        return;
      }
    } catch (_) {
      // Try the next known local connection route.
    }
  }
}

class AstroFieldApp extends StatelessWidget {
  const AstroFieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AstroField',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF67D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07111F),
        cardTheme: const CardThemeData(
          color: Color(0xFF101D2E),
          margin: EdgeInsets.zero,
        ),
        useMaterial3: true,
      ),
      home: kPreviewMode ? const ObservatoryShell() : const AstroFieldSplash(),
    );
  }
}

class AstroFieldSplash extends StatefulWidget {
  const AstroFieldSplash({super.key});

  @override
  State<AstroFieldSplash> createState() => _AstroFieldSplashState();
}

class _AstroFieldSplashState extends State<AstroFieldSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const ObservatoryShell(),
            transitionDuration: const Duration(milliseconds: 450),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/astrofield-splash.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xE607111F), Color(0x3307111F)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          const Align(
            alignment: Alignment(-0.58, 0.05),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 58, color: Color(0xFF67D4FF)),
                SizedBox(height: 10),
                Text(
                  'ASTROFIELD',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 5,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'YOUR OBSERVATORY · ANYWHERE',
                  style: TextStyle(
                    color: Color(0xFFAFC7DC),
                    fontSize: 11,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NightSkyBackground extends StatelessWidget {
  const _NightSkyBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/night-sky-background.png'),
          fit: BoxFit.cover,
          opacity: 0.24,
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xA607111F)),
        child: child,
      ),
    );
  }
}

class ObservatoryShell extends StatefulWidget {
  const ObservatoryShell({super.key});

  @override
  State<ObservatoryShell> createState() => _ObservatoryShellState();
}

class _ObservatoryShellState extends State<ObservatoryShell> {
  late int _index = kPreviewMode ? kPreviewTab.clamp(0, 8) : 0;

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _index,
      children: const [
        RigDashboard(),
        _SkyPage(),
        _CameraPage(),
        _FocusPage(),
        _GuidePage(),
        _EquipmentPage(),
        _PolarAlignmentPage(),
        _SystemPage(),
        _SessionPage(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: LayoutBuilder(
                    builder: (context, railConstraints) {
                      final railHeight = railConstraints.maxHeight < 700
                          ? 700.0
                          : railConstraints.maxHeight;
                      return SingleChildScrollView(
                        child: SizedBox(
                          height: railHeight,
                          child: NavigationRail(
                            selectedIndex: _index,
                            onDestinationSelected: (index) {
                              setState(() => _index = index);
                            },
                            backgroundColor: const Color(0xFF0B1727),
                            indicatorColor: const Color(0xFF173A50),
                            labelType: NavigationRailLabelType.all,
                            leading: const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 8),
                              child: Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF67D4FF),
                              ),
                            ),
                            destinations: const [
                              NavigationRailDestination(
                                icon: Icon(Icons.hub_outlined),
                                label: Text('Rig'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.travel_explore),
                                label: Text('Sky'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.camera_alt_outlined),
                                label: Text('Camera', key: Key('nav-camera')),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.center_focus_strong),
                                label: Text('Focus', key: Key('nav-focus')),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.show_chart),
                                label: Text('Guide', key: Key('nav-guide')),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.settings_input_component),
                                label: Text('Gear'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.explore),
                                label: Text('Polar'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.memory),
                                label: Text('System'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.event_note_outlined),
                                label: Text('Session'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _NightSkyBackground(child: pages)),
              ],
            ),
          );
        }
        return Scaffold(
          body: _NightSkyBackground(child: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            backgroundColor: const Color(0xFF0B1727),
            indicatorColor: const Color(0xFF173A50),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                label: 'Rig',
              ),
              NavigationDestination(
                icon: Icon(Icons.travel_explore),
                label: 'Sky',
              ),
              NavigationDestination(
                icon: Icon(Icons.camera_alt_outlined),
                label: 'Camera',
              ),
              NavigationDestination(
                icon: Icon(Icons.center_focus_strong),
                label: 'Focus',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart),
                label: 'Guide',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_input_component),
                label: 'Gear',
              ),
              NavigationDestination(icon: Icon(Icons.explore), label: 'Polar'),
              NavigationDestination(icon: Icon(Icons.memory), label: 'System'),
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                label: 'Session',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.title, required this.subtitle, this.icon});

  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: const Color(0xFF67D4FF)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF93A8BF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF46DBA7).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFF46DBA7)),
                SizedBox(width: 6),
                Text(
                  'Astroberry',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPage extends StatelessWidget {
  const _CameraPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'Camera',
            subtitle: 'Main camera - preview, exposure and capture controls',
            icon: Icons.camera_alt_outlined,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 760) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(child: Center(child: _ImageCanvas())),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 360,
                          child: Card(
                            child: ListView(
                              padding: EdgeInsets.all(12),
                              children: [_DetailedCameraControls()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    const _ImageCanvas(),
                    const SizedBox(height: 12),
                    const _PreviewControls(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onModeChanged});

  final int mode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          label: Text('Capture'),
          icon: Icon(Icons.camera_alt_outlined),
        ),
        ButtonSegment(
          value: 1,
          label: Text('Focus'),
          icon: Icon(Icons.center_focus_strong),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onModeChanged(selection.first),
    );
  }
}

// Legacy combined inspector retained while capture controls are migrated.
// ignore: unused_element
class _CameraInspector extends StatelessWidget {
  const _CameraInspector({required this.mode, required this.onModeChanged});

  final int mode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ModeSelector(mode: mode, onModeChanged: onModeChanged),
          const SizedBox(height: 12),
          if (mode == 0)
            const _DetailedCameraControls()
          else
            const _DetailedFocusControls(),
        ],
      ),
    );
  }
}

class _DetailedCameraControls extends StatelessWidget {
  const _DetailedCameraControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorTitle(
          title: 'Main camera',
          subtitle: 'Select an Ekos profile to load device values',
          icon: Icons.camera_outlined,
        ),
        SizedBox(height: 12),
        _InspectorSectionLabel('EXPOSURE'),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Exposure', value: '5.0 s'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Count', value: '1'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Delay', value: '0 s'),
            ),
          ],
        ),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Gain', value: '100'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Offset', value: '10'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Binning', value: '1 × 1'),
            ),
          ],
        ),
        SizedBox(height: 12),
        _InspectorSectionLabel('FRAME & STORAGE'),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Frame', value: 'Light'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Filter', value: 'Luminance'),
            ),
          ],
        ),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Format', value: 'FITS'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Upload', value: 'Local + client'),
            ),
          ],
        ),
        SizedBox(height: 7),
        _InspectorField(label: 'ROI / Subframe', value: 'Full sensor'),
        SizedBox(height: 12),
        _InspectorSectionLabel('COOLING'),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Target', value: '−10.0 °C'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Current', value: '— °C'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Cooler', value: 'Off'),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.loop),
                label: Text('Loop'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: null,
                icon: Icon(Icons.camera_alt),
                label: Text('Capture preview'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailedFocusControls extends StatelessWidget {
  const _DetailedFocusControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorTitle(
          title: 'Electronic focuser',
          subtitle: 'Manual movement and Ekos autofocus',
          icon: Icons.center_focus_strong,
        ),
        SizedBox(height: 12),
        _InspectorSectionLabel('MANUAL CONTROL'),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Position', value: '12,840'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Step', value: '100'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Backlash', value: '0'),
            ),
          ],
        ),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.remove),
                label: Text('In'),
              ),
            ),
            SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.add),
                label: Text('Out'),
              ),
            ),
            SizedBox(width: 7),
            IconButton.filledTonal(onPressed: null, icon: Icon(Icons.stop)),
          ],
        ),
        SizedBox(height: 12),
        _InspectorSectionLabel('AUTOFOCUS'),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(
                label: 'Algorithm',
                value: 'Linear 1 Pass',
              ),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Measure', value: 'HFR'),
            ),
          ],
        ),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _InspectorField(label: 'Exposure', value: '2.0 s'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Filter', value: 'Luminance'),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _InspectorField(label: 'Field', value: 'Full'),
            ),
          ],
        ),
        SizedBox(height: 10),
        SizedBox(height: 100, child: _FocusCurve()),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.repeat),
                label: Text('Frame'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: null,
                icon: Icon(Icons.center_focus_strong),
                label: Text('Run autofocus'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InspectorTitle extends StatelessWidget {
  const _InspectorTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF67D4FF)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF93A8BF), fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InspectorSectionLabel extends StatelessWidget {
  const _InspectorSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF7189A2),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  const _InspectorField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1727),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF213247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF7189A2), fontSize: 9),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FocusCurve extends StatelessWidget {
  const _FocusCurve();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FocusCurvePainter());
  }
}

class _FocusCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF213247);
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), grid);
    }
    final curve = Paint()
      ..color = const Color(0xFF67D4FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(0, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.95,
        size.width,
        size.height * 0.15,
      );
    canvas.drawPath(path, curve);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ImageCanvas extends StatelessWidget {
  const _ImageCanvas();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _StarFieldPainter()),
            const Center(
              child: Icon(Icons.add, color: Color(0x6679DFFF), size: 42),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _OverlayLabel(icon: Icons.camera, text: 'PREVIEW · READY'),
            ),
            Positioned(
              right: 10,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Fullscreen',
                onPressed: null,
                icon: const Icon(Icons.fullscreen),
              ),
            ),
            const Positioned(
              left: 12,
              bottom: 12,
              child: Row(
                children: [
                  _CanvasTool(icon: Icons.auto_graph, label: 'Histogram'),
                  SizedBox(width: 8),
                  _CanvasTool(icon: Icons.gps_fixed, label: 'Solve'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF020914), Color(0xFF071B2B), Color(0xFF030A13)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    const stars = [
      (0.08, 0.17, 1.2),
      (0.19, 0.63, 1.8),
      (0.27, 0.28, 1.0),
      (0.35, 0.78, 1.4),
      (0.43, 0.44, 2.3),
      (0.54, 0.16, 1.1),
      (0.59, 0.69, 1.6),
      (0.67, 0.34, 1.3),
      (0.75, 0.82, 2.0),
      (0.82, 0.23, 1.5),
      (0.91, 0.55, 1.0),
      (0.14, 0.87, 0.9),
      (0.71, 0.57, 0.8),
      (0.47, 0.91, 1.0),
    ];
    final star = Paint()..color = const Color(0xFFD9F3FF);
    for (final point in stars) {
      canvas.drawCircle(
        Offset(size.width * point.$1, size.height * point.$2),
        point.$3,
        star,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC07111F),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: const Color(0xFF67D4FF)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CanvasTool extends StatelessWidget {
  const _CanvasTool({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC07111F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF93A8BF)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _SettingTile(label: 'Exposure', value: '5.0 s'),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _SettingTile(label: 'Gain', value: '100'),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _SettingTile(label: 'Filter', value: 'L'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capture preview'),
          ),
        ),
      ],
    );
  }
}

// Legacy compact focus controls retained for narrow-layout migration.
// ignore: unused_element
class _FocusControls extends StatelessWidget {
  const _FocusControls();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Focuser position'),
                Text('12,840', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: null,
                  icon: const Icon(Icons.remove),
                ),
                const Expanded(child: Slider(value: 0.54, onChanged: null)),
                IconButton.filledTonal(
                  onPressed: null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Start autofocus'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF7189A2), fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _FocusPage extends StatefulWidget {
  const _FocusPage();

  @override
  State<_FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<_FocusPage> {
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic> _status = kPreviewMode
      ? {
          'ekos_available': true,
          'focus_state': 'Complete',
          'capture_state': 'Capturing',
          'hfr': 1.82,
          'camera': 'ASI2600MM Pro',
          'focuser': 'ZWO EAF',
          'filter': 'L',
          'minutes_since_focus': 42.0,
          'temperature_delta_c': -0.8,
          'indi': {
            'connected': true,
            'position': 24680,
            'absolute': true,
            'can_abort': true,
            'can_reverse': true,
            'reversed': false,
            'can_sync': true,
            'can_home': true,
            'has_backlash': true,
            'temperature_c': 8.4,
            'temperature_source': 'ZWO EAF',
          },
          'controller': {'state': 'idle'},
        }
      : {};
  Map<String, dynamic> _config = {
    'temperature_enabled': true,
    'temperature_delta_c': 1.5,
    'time_enabled': true,
    'time_interval_minutes': 60,
    'only_during_capture': true,
    'resume_on_failure': false,
    'exposure_seconds': 2.0,
    'binning': 1,
    'auto_select_star': true,
    'subframe': false,
    'box_size': 64,
    'initial_step': 100,
    'max_travel': 1000,
    'tolerance_percent': 5.0,
    'manual_step': 100,
    'speed_factor': 1,
    'driver_backlash': 0,
    'af_overscan': 100,
    'settle_seconds': 1.0,
    'suspend_guiding': false,
    'filter': 'L',
  };
  List<Map<String, dynamic>> _history = kPreviewMode
      ? [
          {
            'time': 1783951200.0,
            'reason': 'temperature',
            'status': 'Complete',
            'hfr': 1.82,
            'position': 24680,
            'temperature_c': 8.4,
          },
          {
            'time': 1783947600.0,
            'reason': 'time',
            'status': 'Complete',
            'hfr': 1.91,
            'position': 24735,
            'temperature_c': 9.6,
          },
        ]
      : [];

  @override
  void initState() {
    super.initState();
    if (!kPreviewMode) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-AstroField-Token': kBridgeToken,
  };

  Future<void> _refresh() async {
    if (kBridgeToken.isEmpty) return;
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$kBridgeBaseUrl/focus/status'), headers: _headers),
        http.get(Uri.parse('$kBridgeBaseUrl/focus/config'), headers: _headers),
        http.get(Uri.parse('$kBridgeBaseUrl/focus/history'), headers: _headers),
      ]).timeout(const Duration(seconds: 7));
      if (!mounted) return;
      setState(() {
        if (responses[0].statusCode == 200) {
          _status = jsonDecode(responses[0].body);
        }
        if (responses[1].statusCode == 200) {
          _config = jsonDecode(responses[1].body);
        }
        if (responses[2].statusCode == 200) {
          _history =
              ((jsonDecode(responses[2].body)['runs'] as List?) ?? const [])
                  .cast<Map<String, dynamic>>();
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _command(
    String action, [
    Map<String, Object?> values = const {},
  ]) async {
    if (_busy || (!kPreviewMode && kBridgeToken.isEmpty)) return;
    setState(() => _busy = true);
    if (kPreviewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final response = await http
          .post(
            Uri.parse('$kBridgeBaseUrl/focus/command'),
            headers: _headers,
            body: jsonEncode({'action': action, ...values}),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 300) {
        throw Exception(body['message'] ?? 'Focus command failed');
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(Map<String, Object?> changes) async {
    setState(() => _config = {..._config, ...changes});
    if (kPreviewMode || kBridgeToken.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse('$kBridgeBaseUrl/focus/config'),
        headers: _headers,
        body: jsonEncode(changes),
      );
      if (response.statusCode >= 300) {
        throw Exception('Could not save focus settings');
      }
      final config =
          jsonDecode(response.body)['config'] as Map<String, dynamic>;
      if (mounted) setState(() => _config = config);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _gotoPosition() async {
    final controller = TextEditingController(
      text: '${(_status['indi'] as Map?)?['position'] ?? ''}',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to absolute position'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Focuser position'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _command('goto', {'value': value});
  }

  double _value(String key, double fallback) =>
      (_config[key] as num?)?.toDouble() ?? fallback;
  bool _flag(String key) => _config[key] == true;

  @override
  Widget build(BuildContext context) {
    final indi = _status['indi'] as Map<String, dynamic>? ?? const {};
    final controller =
        _status['controller'] as Map<String, dynamic>? ?? const {};
    final focusBusy =
        _busy ||
        {
          'starting',
          'waiting_for_capture',
          'running',
        }.contains(controller['state']);
    final online = kPreviewMode || _status['ekos_available'] == true;
    final temperatureAvailable = indi['temperature_c'] != null;
    final position = indi['position'];

    final dashboard = Column(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorTitle(
                          title: 'Autofocus curve',
                          subtitle:
                              '${_status['focus_state'] ?? 'Offline'} - ${controller['message'] ?? 'Ready'}',
                          icon: Icons.center_focus_strong,
                        ),
                      ),
                      Chip(label: Text('HFR ${_status['hfr'] ?? '—'}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: CustomPaint(painter: _FocusCurvePainter())),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingTile(
                          label: 'Position',
                          value: '${position ?? '—'} ticks',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SettingTile(
                          label: 'Temperature',
                          value: temperatureAvailable
                              ? '${indi['temperature_c']} °C'
                              : 'No probe',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SettingTile(
                          label: 'Last focus',
                          value: _status['minutes_since_focus'] == null
                              ? 'Not run'
                              : '${_status['minutes_since_focus']} min',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SettingTile(
                          label: 'Capture',
                          value: '${_status['capture_state'] ?? 'Offline'}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: online && !focusBusy
                            ? () => _command('autofocus')
                            : null,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Run autofocus now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: online && !focusBusy
                          ? () => _command('capture')
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Focus frame'),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: online ? () => _command('abort') : null,
                      icon: const Icon(Icons.stop),
                      tooltip: 'Abort autofocus',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: online && !focusBusy
                          ? () => _command('in', {
                              'steps': _value('manual_step', 100).round(),
                            })
                          : null,
                      icon: const Icon(Icons.keyboard_double_arrow_left),
                      tooltip: 'Move inward',
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _InspectorField(
                        label: 'Manual step',
                        value: '${_value('manual_step', 100).round()} ticks',
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      onPressed: online && !focusBusy
                          ? () => _command('out', {
                              'steps': _value('manual_step', 100).round(),
                            })
                          : null,
                      icon: const Icon(Icons.keyboard_double_arrow_right),
                      tooltip: 'Move outward',
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: indi['absolute'] == true
                          ? _gotoPosition
                          : null,
                      child: const Text('Go to'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: indi['can_abort'] == true
                          ? () => _command('abort_motion')
                          : null,
                      child: const Text('Stop motion'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final settings = Card(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _InspectorTitle(
            title: 'Focus control',
            subtitle: 'Ekos optical-train settings and automatic reruns',
            icon: Icons.tune,
          ),
          const SizedBox(height: 12),
          const _InspectorSectionLabel('AUTOMATIC RERUNS'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Temperature change'),
            subtitle: Text(
              temperatureAvailable
                  ? 'Probe: ${indi['temperature_source']} - current Δ ${_status['temperature_delta_c'] ?? 0} °C'
                  : 'No temperature source detected',
            ),
            value: _flag('temperature_enabled') && temperatureAvailable,
            onChanged: temperatureAvailable
                ? (value) => _save({'temperature_enabled': value})
                : null,
          ),
          Text(
            'Trigger after ${_value('temperature_delta_c', 1.5).toStringAsFixed(1)} °C change',
          ),
          Slider(
            value: _value('temperature_delta_c', 1.5).clamp(.5, 5),
            min: .5,
            max: 5,
            divisions: 18,
            onChanged: temperatureAvailable
                ? (value) =>
                      setState(() => _config['temperature_delta_c'] = value)
                : null,
            onChangeEnd: temperatureAvailable
                ? (value) => _save({'temperature_delta_c': value})
                : null,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Elapsed time'),
            subtitle: Text(
              'Run every ${_value('time_interval_minutes', 60).round()} minutes',
            ),
            value: _flag('time_enabled'),
            onChanged: (value) => _save({'time_enabled': value}),
          ),
          Slider(
            value: _value('time_interval_minutes', 60).clamp(15, 240),
            min: 15,
            max: 240,
            divisions: 15,
            onChanged: (value) => setState(
              () => _config['time_interval_minutes'] = value.round(),
            ),
            onChangeEnd: (value) =>
                _save({'time_interval_minutes': value.round()}),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Only while an imaging plan is active'),
            subtitle: const Text(
              'Wait for the current exposure, pause Capture, focus, then continue',
            ),
            value: _flag('only_during_capture'),
            onChanged: (value) => _save({'only_during_capture': value}),
          ),
          const Divider(height: 24),
          const _InspectorSectionLabel('FOCUS CAMERA & STAR'),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Camera',
                  value: '${_status['camera'] ?? 'Not selected'}',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Filter',
                  value: '${_status['filter'] ?? _config['filter'] ?? 'None'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Exposure',
                  value:
                      '${_value('exposure_seconds', 2).toStringAsFixed(1)} s',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Binning',
                  value:
                      '${_value('binning', 1).round()} × ${_value('binning', 1).round()}',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Box',
                  value: '${_value('box_size', 64).round()} px',
                ),
              ),
            ],
          ),
          Text(
            'Focus exposure ${_value('exposure_seconds', 2).toStringAsFixed(1)} s',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('exposure_seconds', 2).clamp(.5, 10),
            min: .5,
            max: 10,
            divisions: 19,
            onChanged: (value) =>
                setState(() => _config['exposure_seconds'] = value),
            onChangeEnd: (value) => _save({'exposure_seconds': value}),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _value('binning', 1).round().clamp(1, 4),
                  decoration: const InputDecoration(labelText: 'Binning'),
                  items: [1, 2, 3, 4]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value × $value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _save({'binning': value});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue:
                      [
                        32,
                        64,
                        96,
                        128,
                        192,
                        256,
                      ].contains(_value('box_size', 64).round())
                      ? _value('box_size', 64).round()
                      : 64,
                  decoration: const InputDecoration(labelText: 'Star box'),
                  items: [32, 64, 96, 128, 192, 256]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value px'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _save({'box_size': value});
                  },
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-select focus star'),
            value: _flag('auto_select_star'),
            onChanged: (value) => _save({'auto_select_star': value}),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use star subframe'),
            subtitle: const Text('Off uses full-field multi-star focusing'),
            value: _flag('subframe'),
            onChanged: (value) => _save({'subframe': value}),
          ),
          const Divider(height: 24),
          const _InspectorSectionLabel('PROCESS'),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Initial step',
                  value: '${_value('initial_step', 100).round()}',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Max travel',
                  value: '${_value('max_travel', 1000).round()}',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Tolerance',
                  value:
                      '${_value('tolerance_percent', 5).toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
          Text(
            'Initial step ${_value('initial_step', 100).round()} ticks',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('initial_step', 100).clamp(10, 1000),
            min: 10,
            max: 1000,
            divisions: 99,
            onChanged: (value) =>
                setState(() => _config['initial_step'] = value.round()),
            onChangeEnd: (value) => _save({'initial_step': value.round()}),
          ),
          Text(
            'Maximum travel ${_value('max_travel', 1000).round()} ticks',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('max_travel', 1000).clamp(100, 10000),
            min: 100,
            max: 10000,
            divisions: 99,
            onChanged: (value) =>
                setState(() => _config['max_travel'] = value.round()),
            onChangeEnd: (value) => _save({'max_travel': value.round()}),
          ),
          Text(
            'Solution tolerance ${_value('tolerance_percent', 5).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('tolerance_percent', 5).clamp(1, 20),
            min: 1,
            max: 20,
            divisions: 38,
            onChanged: (value) =>
                setState(() => _config['tolerance_percent'] = value),
            onChangeEnd: (value) => _save({'tolerance_percent': value}),
          ),
          const SizedBox(height: 7),
          const Text(
            'Curve algorithm and star-measure method remain stored per Ekos optical train; AstroField applies the exposure, binning, star selection, step, travel and tolerance shown here.',
            style: TextStyle(color: Color(0xFF93A8BF), fontSize: 10),
          ),
          const Divider(height: 24),
          const _InspectorSectionLabel('MECHANICS & SAFETY'),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Driver backlash',
                  value: '${_value('driver_backlash', 0).round()} ticks',
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: _InspectorField(
                  label: 'AF overscan',
                  value: 'Ekos optical train',
                ),
              ),
            ],
          ),
          Text(
            'Manual move ${_value('manual_step', 100).round()} ticks',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('manual_step', 100).clamp(10, 2000),
            min: 10,
            max: 2000,
            divisions: 199,
            onChanged: (value) =>
                setState(() => _config['manual_step'] = value.round()),
            onChangeEnd: (value) => _save({'manual_step': value.round()}),
          ),
          Text(
            'Movement speed factor ${_value('speed_factor', 1).round()}×',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('speed_factor', 1).clamp(1, 10),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (value) =>
                setState(() => _config['speed_factor'] = value.round()),
            onChangeEnd: (value) => _save({'speed_factor': value.round()}),
          ),
          Text(
            'Driver backlash ${_value('driver_backlash', 0).round()} ticks',
            style: const TextStyle(fontSize: 10),
          ),
          Slider(
            value: _value('driver_backlash', 0).clamp(0, 2000),
            min: 0,
            max: 2000,
            divisions: 200,
            onChanged: indi['has_backlash'] == true
                ? (value) =>
                      setState(() => _config['driver_backlash'] = value.round())
                : null,
            onChangeEnd: indi['has_backlash'] == true
                ? (value) => _save({'driver_backlash': value.round()})
                : null,
          ),
          const SizedBox(height: 7),
          const Text(
            'Autofocus overscan remains managed by the selected Ekos optical train. The current Ekos Focus DBus interface does not provide a safe setter for this value.',
            style: TextStyle(color: Color(0xFF93A8BF), fontSize: 10),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: indi['has_backlash'] == true
                      ? () => _command('backlash', {
                          'value': _value('driver_backlash', 0),
                        })
                      : null,
                  child: const Text('Apply driver backlash'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: OutlinedButton(
                  onPressed: indi['can_sync'] == true && position != null
                      ? () => _command('sync', {'value': position})
                      : null,
                  child: const Text('Sync current position'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: indi['can_home'] == true
                      ? () => _command('home')
                      : null,
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Home focuser'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Reverse'),
                  value: indi['reversed'] == true,
                  onChanged: indi['can_reverse'] == true
                      ? (value) => _command('reverse', {'enabled': value})
                      : null,
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resume imaging after focus failure'),
            subtitle: const Text(
              'Disabled is safer: a failed autofocus leaves Capture paused',
            ),
            value: _flag('resume_on_failure'),
            onChanged: (value) => _save({'resume_on_failure': value}),
          ),
          const Divider(height: 24),
          const _InspectorSectionLabel('RECENT AUTOFOCUS RUNS'),
          if (_history.isEmpty)
            const Text(
              'No completed autofocus runs yet',
              style: TextStyle(color: Color(0xFF93A8BF)),
            )
          else
            ..._history
                .take(5)
                .map(
                  (run) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      run['status'] == 'Complete'
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: run['status'] == 'Complete'
                          ? const Color(0xFF69E3A5)
                          : const Color(0xFFFF7C8D),
                    ),
                    title: Text('${run['reason']} - HFR ${run['hfr']}'),
                    subtitle: Text(
                      'Position ${run['position'] ?? '—'} - ${run['temperature_c'] ?? '—'} °C',
                    ),
                  ),
                ),
        ],
      ),
    );

    return SafeArea(
      child: Column(
        children: [
          _ModuleHeader(
            title: 'Autofocus',
            subtitle: _loading
                ? 'Loading focus equipment...'
                : 'Manual focus, Ekos autofocus and unattended rerun triggers',
            icon: Icons.center_focus_strong,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 850) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: dashboard),
                        const SizedBox(width: 12),
                        SizedBox(width: 430, child: settings),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      SizedBox(height: 620, child: dashboard),
                      const SizedBox(height: 12),
                      SizedBox(height: 900, child: settings),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkyPage extends StatefulWidget {
  const _SkyPage();

  @override
  State<_SkyPage> createState() => _SkyPageState();
}

class _SkyPageState extends State<_SkyPage> {
  int _columns = 2;
  int _rows = 2;
  double _rotation = 0;
  List<Map<String, dynamic>> _targets = const [
    {'name': 'M 42', 'altitude_degrees': 48.2, 'magnitude': 4.0},
    {'name': 'NGC 2244', 'altitude_degrees': 41.7, 'magnitude': 4.8},
    {'name': 'NGC 2264', 'altitude_degrees': 38.4, 'magnitude': 3.9},
  ];
  String _selectedTarget = 'M 42';

  @override
  void initState() {
    super.initState();
    if (!kPreviewMode) _loadTargets();
  }

  Future<void> _loadTargets([String? query]) async {
    try {
      final path = query == null || query.trim().isEmpty
          ? 'sky/visible?limit=16&min_altitude=20'
          : 'sky/search?q=${Uri.encodeQueryComponent(query)}&limit=16&min_altitude=0';
      final response = await http
          .get(Uri.parse('$kBridgeBaseUrl/$path'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return;
      final targets = (jsonDecode(response.body)['objects'] as List)
          .cast<Map<String, dynamic>>();
      if (targets.isNotEmpty && mounted) {
        setState(() {
          _targets = targets;
          _selectedTarget = '${targets.first['name']}';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final atlas = Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _SkyAtlasPainter(
              rows: _rows,
              columns: _columns,
              rotation: _rotation,
            ),
          ),
          const Positioned(
            left: 12,
            top: 12,
            child: _OverlayLabel(
              icon: Icons.public,
              text: 'KSTARS OPENNGC · LIVE SKY',
            ),
          ),
          const Positioned(
            right: 12,
            top: 12,
            child: _OverlayLabel(
              icon: Icons.gps_fixed,
              text: 'TELESCOPE · OFFLINE',
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xDD0A1625),
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search M42, NGC 7000, Vega…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _loadTargets,
            ),
          ),
        ],
      ),
    );
    final planner = _FramingPlanner(
      rows: _rows,
      columns: _columns,
      rotation: _rotation,
      onRowsChanged: (value) => setState(() => _rows = value),
      onColumnsChanged: (value) => setState(() => _columns = value),
      onRotationChanged: (value) => setState(() => _rotation = value),
      targets: _targets,
      selectedTarget: _selectedTarget,
      onTargetSelected: (target) => setState(() => _selectedTarget = target),
      onAdd: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_selectedTarget $_columns×$_rows mosaic added to Session',
          ),
        ),
      ),
    );
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'Sky Atlas & Framing',
            subtitle: 'Live telescope position, camera framing and mosaics',
            icon: Icons.travel_explore,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: constraints.maxWidth >= 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: atlas),
                          const SizedBox(width: 12),
                          SizedBox(width: 350, child: planner),
                        ],
                      )
                    : ListView(
                        children: [
                          SizedBox(height: 330, child: atlas),
                          const SizedBox(height: 12),
                          SizedBox(height: 500, child: planner),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramingPlanner extends StatelessWidget {
  const _FramingPlanner({
    required this.rows,
    required this.columns,
    required this.rotation,
    required this.onRowsChanged,
    required this.onColumnsChanged,
    required this.onRotationChanged,
    required this.targets,
    required this.selectedTarget,
    required this.onTargetSelected,
    required this.onAdd,
  });

  final int rows;
  final int columns;
  final double rotation;
  final ValueChanged<int> onRowsChanged;
  final ValueChanged<int> onColumnsChanged;
  final ValueChanged<double> onRotationChanged;
  final List<Map<String, dynamic>> targets;
  final String selectedTarget;
  final ValueChanged<String> onTargetSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const _InspectorTitle(
            title: 'Framing assistant',
            subtitle: 'ASI2600MM · 500 mm focal length',
            icon: Icons.crop_free,
          ),
          const SizedBox(height: 14),
          const _InspectorSectionLabel('WHAT IS UP NOW'),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: targets.take(6).map((target) {
              final name = '${target['name']}';
              final altitude = (target['altitude_degrees'] as num?)?.round();
              return ChoiceChip(
                selected: selectedTarget == name,
                label: Text('$name${altitude == null ? '' : '  $altitude°'}'),
                onSelected: (_) => onTargetSelected(name),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _InspectorSectionLabel('CAMERA FIELD OF VIEW'),
          const SizedBox(height: 7),
          const Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'Width', value: '2.69°'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Height', value: '1.80°'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Scale', value: '1.55″/px'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _InspectorSectionLabel('MOSAIC'),
          Text('Columns: $columns'),
          Slider(
            value: columns.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (v) => onColumnsChanged(v.round()),
          ),
          Text('Rows: $rows'),
          Slider(
            value: rows.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (v) => onRowsChanged(v.round()),
          ),
          Text('Rotation: ${rotation.round()}°'),
          Slider(
            value: rotation,
            min: -90,
            max: 90,
            divisions: 36,
            onChanged: onRotationChanged,
          ),
          const _InspectorSectionLabel('MANUAL ROTATION ASSISTANT'),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Desired PA',
                  value: '${rotation.round()}°',
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: _InspectorField(
                  label: 'Solved PA',
                  value: 'Not measured',
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Capture and plate-solve a short exposure. AstroField will show which direction to rotate the camera and the remaining angle, then repeat until within 1°.',
            style: TextStyle(color: Color(0xFF93A8BF), fontSize: 11),
          ),
          const SizedBox(height: 7),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.rotate_right),
            label: const Text('Measure camera rotation'),
          ),
          const Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'Overlap', value: '15%'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Panels', value: 'Auto'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Add mosaic to session'),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MountAction(icon: Icons.near_me_outlined, label: 'GoTo'),
              _MountAction(icon: Icons.gps_fixed, label: 'Solve'),
              _MountAction(icon: Icons.center_focus_strong, label: 'Center'),
              _MountAction(icon: Icons.track_changes, label: 'Track'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkyAtlasPainter extends CustomPainter {
  const _SkyAtlasPainter({
    required this.rows,
    required this.columns,
    required this.rotation,
  });
  final int rows;
  final int columns;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF071421),
    );
    final star = Paint()..color = const Color(0xFFD9ECFF);
    for (var i = 0; i < 90; i++) {
      canvas.drawCircle(
        Offset(
          ((i * 73) % 997) / 997 * size.width,
          ((i * 137) % 991) / 991 * size.height,
        ),
        i % 11 == 0 ? 1.7 : 0.7,
        star,
      );
    }
    final center = Offset(size.width * .52, size.height * .43);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 3.14159265 / 180);
    final frame = Paint()
      ..color = const Color(0xFF67D4FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const panelW = 92.0;
    const panelH = 62.0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (col - (columns - 1) / 2) * panelW * .85 - panelW / 2,
            (row - (rows - 1) / 2) * panelH * .85 - panelH / 2,
            panelW,
            panelH,
          ),
          frame,
        );
      }
    }
    canvas.restore();
    final reticle = Paint()
      ..color = const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 10, reticle);
    canvas.drawLine(
      center - const Offset(16, 0),
      center + const Offset(16, 0),
      reticle,
    );
    canvas.drawLine(
      center - const Offset(0, 16),
      center + const Offset(0, 16),
      reticle,
    );
  }

  @override
  bool shouldRepaint(covariant _SkyAtlasPainter oldDelegate) =>
      rows != oldDelegate.rows ||
      columns != oldDelegate.columns ||
      rotation != oldDelegate.rotation;
}

class _MountAction extends StatelessWidget {
  const _MountAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filledTonal(onPressed: null, icon: Icon(icon)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _GuidePage extends StatefulWidget {
  const _GuidePage();

  @override
  State<_GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<_GuidePage> {
  Timer? _timer;
  Map<String, dynamic> _status = {
    'installed': '2.6.14',
    'running': false,
    'state': 'Stopped',
  };
  Map<String, dynamic> _assistant = kPreviewMode
      ? {
          'state': 'complete',
          'results': {
            'duration_seconds': 612.0,
            'samples': 304,
            'ra_rms_arcsec': 0.61,
            'dec_rms_arcsec': 0.48,
            'total_rms_arcsec': 0.78,
            'ra_drift_arcsec_per_min': 0.22,
            'dec_drift_arcsec_per_min': -0.31,
            'average_snr': 24.7,
            'seeing_ra_arcsec': 0.42,
            'seeing_dec_arcsec': 0.51,
            'polar_alignment_error_arcmin': 3.8,
            'trace': [
              {'t': 0.0, 'ra': -0.4, 'dec': 0.2},
              {'t': 20.0, 'ra': 0.7, 'dec': -0.3},
              {'t': 40.0, 'ra': -0.2, 'dec': 0.8},
              {'t': 60.0, 'ra': 0.3, 'dec': -0.5},
              {'t': 80.0, 'ra': -0.6, 'dec': 0.1},
              {'t': 100.0, 'ra': 0.1, 'dec': -0.2},
            ],
            'backlash': {
              'milliseconds': 640,
              'classification': 'compensatable',
              'recommended_compensation_ms': 640,
              'north_points': [0.0, 3.8, 7.7, 11.5, 15.4],
              'south_points': [15.4, 15.2, 14.9, 11.1, 7.3, 3.5],
            },
            'messages': [
              {
                'category': 'mechanical',
                'severity': 'advice',
                'message':
                    'Small DEC delay detected; PHD2 adaptive compensation is suitable.',
              },
            ],
            'recommendations': {
              'ra_min_move_pixels': 0.18,
              'dec_min_move_pixels': 0.21,
              'phd2_backlash_compensation_ms': 640,
            },
          },
        }
      : {'state': 'idle', 'samples': 0};
  List<Map<String, dynamic>> _assistantHistory = kPreviewMode
      ? [
          {
            'id': 'preview-previous',
            'completed_at': 1783950300.0,
            'total_rms_arcsec': 1.12,
            'ra_rms_arcsec': 0.84,
            'dec_rms_arcsec': 0.74,
          },
        ]
      : [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!kPreviewMode) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$kBridgeBaseUrl/phd2/status')),
        if (kBridgeToken.isNotEmpty)
          http.get(
            Uri.parse('$kBridgeBaseUrl/phd2/assistant/status'),
            headers: {'X-AstroField-Token': kBridgeToken},
          ),
        if (kBridgeToken.isNotEmpty)
          http.get(
            Uri.parse('$kBridgeBaseUrl/phd2/assistant/history'),
            headers: {'X-AstroField-Token': kBridgeToken},
          ),
      ]).timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          if (responses.first.statusCode == 200) {
            _status = jsonDecode(responses.first.body);
          }
          if (responses.length > 1 && responses[1].statusCode == 200) {
            _assistant = jsonDecode(responses[1].body);
          }
          if (responses.length > 2 && responses[2].statusCode == 200) {
            _assistantHistory =
                ((jsonDecode(responses[2].body)['runs'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status['state'] = 'Bridge offline');
    }
  }

  Future<void> _assistantAction(
    String action, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (kBridgeToken.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$kBridgeBaseUrl/phd2/assistant/$action'),
            headers: {
              'Content-Type': 'application/json',
              'X-AstroField-Token': kBridgeToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 300) {
        throw Exception(body['message'] ?? 'Guiding Assistant error');
      }
      if (mounted && action == 'apply') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recommended PHD2 MinMo settings applied'),
          ),
        );
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rpc(String method, [Object? params]) async {
    if (kBridgeToken.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$kBridgeBaseUrl/phd2/rpc'),
            headers: {
              'Content-Type': 'application/json',
              'X-AstroField-Token': kBridgeToken,
            },
            body: jsonEncode({'method': method, 'params': ?params}),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 300) {
        throw Exception(jsonDecode(response.body)['message'] ?? 'PHD2 error');
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'PHD2 Guiding',
            subtitle: 'Guide camera, calibration, corrections and dithering',
            icon: Icons.show_chart,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graph = Column(
                  children: [
                    Expanded(
                      child: Card(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(painter: _GuideGraphPainter()),
                            const Positioned(
                              left: 12,
                              top: 12,
                              child: _OverlayLabel(
                                icon: Icons.show_chart,
                                text: 'RA / DEC ERROR · 100 SAMPLES',
                              ),
                            ),
                            const Center(
                              child: Text(
                                'Start PHD2 to stream guide corrections',
                                style: TextStyle(
                                  color: Color(0xFF7189A2),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(
                          child: _SettingTile(
                            label: 'Total RMS',
                            value: '— arcsec',
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _SettingTile(label: 'RA', value: '—'),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _SettingTile(label: 'DEC', value: '—'),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _SettingTile(label: 'SNR', value: '—'),
                        ),
                      ],
                    ),
                  ],
                );
                if (constraints.maxWidth >= 760) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: graph),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 370,
                          child: _Phd2Inspector(
                            status: _status,
                            assistant: _assistant,
                            history: _assistantHistory,
                            busy: _busy,
                            rpc: _rpc,
                            assistantAction: _assistantAction,
                            reviewRun: (run) => setState(
                              () => _assistant = {
                                'state': 'review',
                                'results': run,
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    SizedBox(height: 250, child: graph),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 650,
                      child: _Phd2Inspector(
                        status: _status,
                        assistant: _assistant,
                        history: _assistantHistory,
                        busy: _busy,
                        rpc: _rpc,
                        assistantAction: _assistantAction,
                        reviewRun: (run) => setState(
                          () =>
                              _assistant = {'state': 'review', 'results': run},
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Phd2Inspector extends StatelessWidget {
  const _Phd2Inspector({
    required this.status,
    required this.assistant,
    required this.history,
    required this.busy,
    required this.rpc,
    required this.assistantAction,
    required this.reviewRun,
  });

  final Map<String, dynamic> status;
  final Map<String, dynamic> assistant;
  final List<Map<String, dynamic>> history;
  final bool busy;
  final Future<void> Function(String, [Object?]) rpc;
  final Future<void> Function(String, [Map<String, Object?>]) assistantAction;
  final ValueChanged<Map<String, dynamic>> reviewRun;

  @override
  Widget build(BuildContext context) {
    final running = status['running'] == true;
    final connected = status['connected'] == true;
    final equipment = status['equipment'] as Map<String, dynamic>? ?? const {};
    final enabled = running && !busy && kBridgeToken.isNotEmpty;
    final assistantState = '${assistant['state'] ?? 'idle'}';
    final assistantRunning =
        assistantState == 'starting' ||
        assistantState == 'measuring' ||
        assistantState == 'backlash';
    final results = assistant['results'] as Map<String, dynamic>?;
    final recommendations =
        results?['recommendations'] as Map<String, dynamic>? ?? const {};
    final backlash = results?['backlash'] as Map<String, dynamic>?;
    final trace = ((results?['trace'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final messages = ((results?['messages'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();

    Future<void> confirmAction(String title, String body, String action) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirm & apply'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await assistantAction(action, {'confirmed': true});
      }
    }

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InspectorTitle(
            title: 'PHD2 ${status['installed'] ?? 'unknown'}',
            subtitle: '${status['state'] ?? 'Unknown'} · TCP 4400',
            icon: Icons.track_changes,
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('EQUIPMENT PROFILE'),
          SizedBox(height: 7),
          _InspectorField(
            label: 'Profile',
            value: '${status['profile'] ?? 'Default'}',
          ),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(
                  label: 'Camera',
                  value:
                      '${equipment['camera'] ?? (connected ? 'Connected' : 'Not connected')}',
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(
                  label: 'Mount',
                  value:
                      '${equipment['mount'] ?? (connected ? 'Connected' : 'Not connected')}',
                ),
              ),
            ],
          ),
          SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: enabled ? () => rpc('set_connected', [true]) : null,
              icon: Icon(Icons.power),
              label: Text('Connect PHD2 equipment'),
            ),
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('GUIDE CAMERA'),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'Exposure', value: '2.0 s'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Binning', value: '1 × 1'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Gamma', value: '1.0'),
              ),
            ],
          ),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => rpc('loop') : null,
                  icon: Icon(Icons.loop),
                  label: Text('Loop'),
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => rpc('find_star') : null,
                  icon: Icon(Icons.star),
                  label: Text('Auto star'),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('CALIBRATE & GUIDE'),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled
                      ? () => rpc('guide', [
                          {'pixels': 0.5, 'time': 5, 'timeout': 15},
                          true,
                        ])
                      : null,
                  icon: Icon(Icons.straighten),
                  label: Text('Calibrate'),
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled
                      ? () => rpc('guide', [
                          {'pixels': 0.5, 'time': 5, 'timeout': 15},
                          false,
                        ])
                      : null,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Guide'),
                ),
              ),
              SizedBox(width: 7),
              IconButton.filledTonal(
                onPressed: enabled ? () => rpc('stop_capture') : null,
                icon: Icon(Icons.stop),
              ),
            ],
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('GUIDING ASSISTANT'),
          SizedBox(height: 7),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color(0xFF0A1625),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Color(0xFF263A50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      assistantRunning
                          ? Icons.science
                          : Icons.analytics_outlined,
                      size: 18,
                      color: assistantState == 'complete'
                          ? Color(0xFF69E3A5)
                          : Color(0xFF67D4FF),
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        assistantRunning
                            ? 'Measuring ${assistant['elapsed_seconds'] ?? 0}s - ${assistant['samples'] ?? 0} frames'
                            : assistantState == 'complete' ||
                                  assistantState == 'review'
                            ? 'Latest measurement complete'
                            : assistantState == 'error'
                            ? '${assistant['message']}'
                            : 'Measure seeing, drift and mount response',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (assistantRunning) ...[
                  SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: assistantState == 'backlash'
                        ? null
                        : ((assistant['elapsed_seconds'] as num?)?.toDouble() ??
                                  0) /
                              ((assistant['duration_seconds'] as num?)
                                      ?.toDouble() ??
                                  600),
                  ),
                  if (assistantState == 'backlash') ...[
                    SizedBox(height: 5),
                    Text(
                      '${assistant['backlash_phase'] ?? 'Preparing test'} - step ${assistant['backlash_steps'] ?? 0}/${assistant['backlash_total_steps'] ?? '-'}',
                      style: TextStyle(color: Color(0xFF93A8BF), fontSize: 10),
                    ),
                  ],
                ],
                if (results != null) ...[
                  if (trace.length > 1) ...[
                    SizedBox(height: 9),
                    SizedBox(
                      height: 105,
                      child: CustomPaint(
                        painter: _AssistantTracePainter(trace),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(
                              'SEEING / HIGH-FREQUENCY MOTION',
                              style: TextStyle(
                                color: Color(0xFF93A8BF),
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorField(
                          label: 'Total RMS',
                          value: '${results['total_rms_arcsec']} arcsec',
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _InspectorField(
                          label: 'RA / DEC',
                          value:
                              '${results['ra_rms_arcsec']} / ${results['dec_rms_arcsec']}',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorField(
                          label: 'RA drift',
                          value:
                              '${results['ra_drift_arcsec_per_min']} arcsec/min',
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _InspectorField(
                          label: 'DEC drift',
                          value:
                              '${results['dec_drift_arcsec_per_min']} arcsec/min',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorField(
                          label: 'Seeing RA / DEC',
                          value:
                              '${results['seeing_ra_arcsec']} / ${results['seeing_dec_arcsec']} arcsec',
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _InspectorField(
                          label: 'Polar error',
                          value:
                              '${results['polar_alignment_error_arcmin']} arcmin',
                        ),
                      ),
                    ],
                  ),
                  if (backlash != null) ...[
                    SizedBox(height: 8),
                    Text(
                      'DEC BACKLASH - ${backlash['milliseconds']} ms - ${backlash['classification']}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    SizedBox(
                      height: 92,
                      child: CustomPaint(
                        painter: _BacklashTracePainter(
                          ((backlash['north_points'] as List?) ?? const [])
                              .cast<num>(),
                          ((backlash['south_points'] as List?) ?? const [])
                              .cast<num>(),
                        ),
                      ),
                    ),
                  ],
                  if (messages.isNotEmpty) ...[
                    SizedBox(height: 8),
                    ...messages.map(
                      (message) => Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              message['severity'] == 'warning'
                                  ? Icons.warning_amber
                                  : Icons.build_outlined,
                              size: 14,
                              color: message['severity'] == 'warning'
                                  ? Color(0xFFFFC857)
                                  : Color(0xFF67D4FF),
                            ),
                            SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${message['message']}',
                                style: TextStyle(
                                  color: Color(0xFFB8C9DB),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Text(
                    'Recommended MinMo: RA ${recommendations['ra_min_move_pixels']} px - DEC ${recommendations['dec_min_move_pixels']} px',
                    style: TextStyle(color: Color(0xFFB8C9DB), fontSize: 11),
                  ),
                ],
                SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: enabled && !assistantRunning
                            ? () => assistantAction('start', {
                                'duration_seconds': 600,
                                'measure_backlash': true,
                              })
                            : null,
                        icon: Icon(Icons.play_circle_outline),
                        label: Text('Run 10 min'),
                      ),
                    ),
                    SizedBox(width: 7),
                    if (assistantRunning)
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: enabled
                              ? () => assistantAction('stop')
                              : null,
                          icon: Icon(Icons.stop_circle_outlined),
                          label: Text('Finish'),
                        ),
                      )
                    else
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: enabled && results != null
                              ? () => confirmAction(
                                  'Apply PHD2 recommendations?',
                                  'This changes RA/DEC MinMo and, for excessive backlash, the confirmed one-direction DEC guide mode. Mount firmware is not changed.',
                                  'apply',
                                )
                              : null,
                          icon: Icon(Icons.tune),
                          label: Text('Apply to PHD2'),
                        ),
                      ),
                  ],
                ),
                if (!assistantRunning &&
                    recommendations['phd2_backlash_compensation_ms'] !=
                        null) ...[
                  SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () => confirmAction(
                              'Enable adaptive DEC backlash compensation?',
                              'PHD2 will close, save ${recommendations['phd2_backlash_compensation_ms']} ms adaptive compensation, and restart. Guiding equipment will need to reconnect.',
                              'backlash/apply',
                            )
                          : null,
                      icon: Icon(Icons.swap_vert_circle_outlined),
                      label: Text(
                        'Enable adaptive backlash (${recommendations['phd2_backlash_compensation_ms']} ms)',
                      ),
                    ),
                  ),
                ],
                if (history.isNotEmpty) ...[
                  SizedBox(height: 9),
                  _InspectorSectionLabel('PREVIOUS RUNS'),
                  SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: history.take(4).map((run) {
                      final completed = DateTime.fromMillisecondsSinceEpoch(
                        ((run['completed_at'] as num?)?.toDouble() ?? 0)
                                .round() *
                            1000,
                      ).toLocal();
                      return ActionChip(
                        avatar: Icon(Icons.history, size: 14),
                        label: Text(
                          '${completed.month}/${completed.day} - ${run['total_rms_arcsec']}"',
                          style: TextStyle(fontSize: 9),
                        ),
                        onPressed: () => reviewRun(run),
                      );
                    }).toList(),
                  ),
                ],
                SizedBox(height: 6),
                Text(
                  'PHD2 guide output is paused during measurement and restored automatically. Mount-firmware backlash compensation is never changed.',
                  style: TextStyle(color: Color(0xFF8298AE), fontSize: 10),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('DITHER & SETTLE'),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'Amount', value: '3.0 px'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Settle', value: '0.5 px'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Timeout', value: '15 s'),
              ),
            ],
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('GUIDING ALGORITHMS'),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'RA', value: 'Hysteresis'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'DEC', value: 'Resist Switch'),
              ),
            ],
          ),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'RA aggression', value: '70%'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'DEC aggression', value: '100%'),
              ),
            ],
          ),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'RA MinMo', value: '0.15 px'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'DEC MinMo', value: '0.15 px'),
              ),
            ],
          ),
          SizedBox(height: 12),
          _InspectorSectionLabel('CALIBRATION SETTINGS'),
          SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _InspectorField(label: 'Step', value: '1000 ms'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'Distance', value: '25 px'),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _InspectorField(label: 'DEC mode', value: 'Auto'),
              ),
            ],
          ),
          SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: enabled
                  ? () => rpc('clear_calibration', ['both'])
                  : null,
              icon: Icon(Icons.delete_sweep_outlined),
              label: Text('Clear calibration data'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideGraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF213247);
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), grid);
    }
    for (var i = 1; i < 7; i++) {
      final x = size.width * i / 7;
      canvas.drawLine(Offset(x, 12), Offset(x, size.height - 12), grid);
    }
    final baseline = Paint()
      ..color = const Color(0xFF7189A2)
      ..strokeWidth = 1.3;
    canvas.drawLine(
      Offset(12, size.height / 2),
      Offset(size.width - 12, size.height / 2),
      baseline,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AssistantTracePainter extends CustomPainter {
  const _AssistantTracePainter(this.samples);
  final List<Map<String, dynamic>> samples;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = const Color(0xFF071421),
    );
    final grid = Paint()..color = const Color(0xFF1C3045);
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final values = samples
        .expand(
          (sample) => [
            (sample['ra'] as num?)?.toDouble() ?? 0,
            (sample['dec'] as num?)?.toDouble() ?? 0,
          ],
        )
        .toList();
    final maximum = math.max(
      1.0,
      values.map((value) => value.abs()).reduce(math.max),
    );
    Path trace(String key) {
      final path = Path();
      for (var index = 0; index < samples.length; index++) {
        final x = samples.length == 1
            ? 0.0
            : index / (samples.length - 1) * size.width;
        final value = (samples[index][key] as num?)?.toDouble() ?? 0;
        final y = size.height / 2 - value / maximum * size.height * .42;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(
      trace('ra'),
      Paint()
        ..color = const Color(0xFF67D4FF)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      trace('dec'),
      Paint()
        ..color = const Color(0xFFFF7C8D)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AssistantTracePainter oldDelegate) =>
      oldDelegate.samples != samples;
}

class _BacklashTracePainter extends CustomPainter {
  const _BacklashTracePainter(this.north, this.south);
  final List<num> north;
  final List<num> south;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = const Color(0xFF071421),
    );
    final all = [...north, ...south];
    if (all.length < 2) return;
    final minimum = all.map((value) => value.toDouble()).reduce(math.min);
    final maximum = all.map((value) => value.toDouble()).reduce(math.max);
    final range = math.max(1.0, maximum - minimum);
    void drawSeries(List<num> values, Color color, double offset) {
      final path = Path();
      final total = math.max(1, north.length + south.length - 2);
      for (var index = 0; index < values.length; index++) {
        final x = (offset + index) / total * size.width;
        final y =
            size.height -
            8 -
            (values[index].toDouble() - minimum) / range * (size.height - 16);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    drawSeries(north, const Color(0xFF69E3A5), 0);
    drawSeries(
      south,
      const Color(0xFFFFC857),
      math.max(0, north.length - 1).toDouble(),
    );
  }

  @override
  bool shouldRepaint(covariant _BacklashTracePainter oldDelegate) =>
      oldDelegate.north != north || oldDelegate.south != south;
}

class _EquipmentPage extends StatefulWidget {
  const _EquipmentPage();

  @override
  State<_EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<_EquipmentPage> {
  final _focalLength = TextEditingController(text: '500');
  final _aperture = TextEditingController(text: '80');
  List<Map<String, dynamic>> _cameras = [];
  List<Map<String, dynamic>> _telescopes = [];
  List<Map<String, dynamic>> _focusers = [];
  Map<String, dynamic>? _mainCamera;
  Map<String, dynamic>? _guideCamera;
  Map<String, dynamic>? _telescope;
  Map<String, dynamic>? _focuser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (kPreviewMode) {
      _cameras = const [
        {'label': 'ZWO CCD', 'driver': 'indi_asi_ccd'},
        {'label': 'QHY CCD', 'driver': 'indi_qhy_ccd'},
      ];
      _telescopes = const [
        {'label': 'EQMod Mount', 'driver': 'indi_eqmod_telescope'},
      ];
      _focusers = const [
        {'label': 'ZWO EAF', 'driver': 'indi_asi_focuser'},
      ];
      _loading = false;
    } else {
      _scanDrivers();
    }
  }

  @override
  void dispose() {
    _focalLength.dispose();
    _aperture.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _drivers(String group) async {
    final response = await http
        .get(Uri.parse('$kBridgeBaseUrl/equipment/drivers?group=$group'))
        .timeout(const Duration(seconds: 4));
    return (jsonDecode(response.body)['drivers'] as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> _scanDrivers() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _drivers('CCD'),
        _drivers('Telescope'),
        _drivers('Focuser'),
      ]);
      if (mounted) {
        setState(() {
          _cameras = results[0];
          _telescopes = results[1];
          _focusers = results[2];
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Astroberry driver catalogue is offline'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final focalLength = double.tryParse(_focalLength.text);
    final aperture = double.tryParse(_aperture.text);
    if (focalLength == null || aperture == null) return;
    try {
      final response = await http.post(
        Uri.parse('$kBridgeBaseUrl/equipment/profile'),
        headers: {
          'Content-Type': 'application/json',
          'X-AstroField-Token': kBridgeToken,
        },
        body: jsonEncode({
          'name': '${_telescope?['label']} optical train',
          'telescope': {
            'name': '${_telescope?['label']}',
            'focal_length_mm': focalLength,
            'aperture_mm': aperture,
            'reducer_factor': 1.0,
            'driver': _telescope,
          },
          'main_camera': _mainCamera,
          'guide_camera': _guideCamera,
          'focuser': _focuser,
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.statusCode == 200
                ? 'Optical train saved on Astroberry'
                : 'Could not save optical train',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Astroberry bridge is offline')),
        );
      }
    }
  }

  DropdownMenuItem<Map<String, dynamic>> _driverItem(
    Map<String, dynamic> driver,
  ) => DropdownMenuItem(value: driver, child: Text('${driver['label']}'));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'Equipment Manager',
            subtitle: 'Build optical trains and assign device roles',
            icon: Icons.settings_input_component,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _EquipmentSection(
                        title: 'Telescope & mount',
                        icon: Icons.radar,
                        child: Column(
                          children: [
                            DropdownButtonFormField<Map<String, dynamic>>(
                              initialValue: _telescope,
                              decoration: const InputDecoration(
                                labelText: 'INDI telescope driver',
                              ),
                              items: _telescopes.map(_driverItem).toList(),
                              onChanged: (value) =>
                                  setState(() => _telescope = value),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _focalLength,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Focal length (mm)',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _aperture,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Aperture (mm)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _EquipmentSection(
                        title: 'Main imaging camera',
                        icon: Icons.camera_alt,
                        child: Column(
                          children: [
                            DropdownButtonFormField<Map<String, dynamic>>(
                              initialValue: _mainCamera,
                              decoration: const InputDecoration(
                                labelText: 'Camera / driver',
                              ),
                              items: _cameras.map(_driverItem).toList(),
                              onChanged: (value) =>
                                  setState(() => _mainCamera = value),
                            ),
                            const SizedBox(height: 9),
                            const Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Chip(label: Text('Auto-identify')),
                                Chip(label: Text('Cooling if exposed')),
                                Chip(label: Text('Gain + offset')),
                                Chip(label: Text('Dew heater if exposed')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _EquipmentSection(
                        title: 'Guide camera role',
                        icon: Icons.track_changes,
                        child: DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: _guideCamera,
                          decoration: const InputDecoration(
                            labelText: 'Dedicated guide camera',
                          ),
                          items: _cameras.map(_driverItem).toList(),
                          onChanged: (value) =>
                              setState(() => _guideCamera = value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _EquipmentSection(
                        title: 'Focuser',
                        icon: Icons.center_focus_strong,
                        child: Column(
                          children: [
                            DropdownButtonFormField<Map<String, dynamic>>(
                              initialValue: _focuser,
                              decoration: const InputDecoration(
                                labelText: 'INDI focuser driver',
                              ),
                              items: _focusers.map(_driverItem).toList(),
                              onChanged: (value) =>
                                  setState(() => _focuser = value),
                            ),
                            const SizedBox(height: 9),
                            const Row(
                              children: [
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Manual step',
                                    value: '100 ticks',
                                  ),
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Backlash',
                                    value: '0 ticks',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _scanDrivers,
                      icon: _loading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.usb),
                      label: const Text('Scan installed INDI drivers'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed:
                          _telescope != null &&
                              _mainCamera != null &&
                              kBridgeToken.isNotEmpty
                          ? _saveProfile
                          : null,
                      icon: const Icon(Icons.save),
                      label: const Text('Save optical train & connect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentSection extends StatelessWidget {
  const _EquipmentSection({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF67D4FF)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _PolarAlignmentPage extends StatefulWidget {
  const _PolarAlignmentPage();

  @override
  State<_PolarAlignmentPage> createState() => _PolarAlignmentPageState();
}

class _PolarAlignmentPageState extends State<_PolarAlignmentPage> {
  int _points = 3;
  double _slewDegrees = 30;
  bool _east = true;
  double _altitudeErrorArcmin = kPreviewMode ? 6.7 : 0;
  double _azimuthErrorArcmin = kPreviewMode ? -4.3 : 0;
  bool _hasCorrection = kPreviewMode;
  bool _refreshing = false;

  String _angle(double value) {
    final absolute = value.abs();
    return '${absolute.floor()}′${((absolute % 1) * 60).round()}″';
  }

  Future<void> _refreshCorrection() async {
    if (!kPreviewMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect the mount and alignment camera to refresh the solve',
          ),
        ),
      );
      return;
    }
    setState(() => _refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _altitudeErrorArcmin *= 0.38;
      _azimuthErrorArcmin *= 0.38;
      _hasCorrection = true;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'Polar Alignment',
            subtitle: 'Plate-solved polar-axis measurement and correction',
            icon: Icons.explore,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _InspectorTitle(
                              title: 'Alignment method',
                              subtitle:
                                  'Three-point is recommended for final alignment',
                              icon: Icons.assistant_navigation,
                            ),
                            const SizedBox(height: 15),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(
                                  value: 2,
                                  label: Text('2-point quick'),
                                ),
                                ButtonSegment(
                                  value: 3,
                                  label: Text('3-point recommended'),
                                ),
                              ],
                              selected: {_points},
                              onSelectionChanged: (value) =>
                                  setState(() => _points = value.first),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Slew between captures: ${_slewDegrees.round()}°',
                            ),
                            Slider(
                              value: _slewDegrees,
                              min: 10,
                              max: 60,
                              divisions: 10,
                              label: '${_slewDegrees.round()}°',
                              onChanged: (value) =>
                                  setState(() => _slewDegrees = value),
                            ),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  label: Text('Slew East'),
                                ),
                                ButtonSegment(
                                  value: false,
                                  label: Text('Slew West'),
                                ),
                              ],
                              selected: {_east},
                              onSelectionChanged: (value) =>
                                  setState(() => _east = value.first),
                            ),
                            const SizedBox(height: 16),
                            const _InspectorSectionLabel('SAFETY'),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Total planned slew',
                                    value:
                                        '${(_slewDegrees * (_points - 1)).round()}°',
                                  ),
                                ),
                                const SizedBox(width: 7),
                                const Expanded(
                                  child: _InspectorField(
                                    label: 'Mount limit',
                                    value: 'Check before start',
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.play_arrow),
                                label: Text('Start $_points-point alignment'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _InspectorTitle(
                              title: 'Measurement sequence',
                              subtitle:
                                  'Capture, solve, slew and calculate polar error',
                              icon: Icons.auto_fix_high,
                            ),
                            const SizedBox(height: 16),
                            for (var i = 1; i <= _points; i++) ...[
                              _InfoCard(
                                icon: i == 1
                                    ? Icons.camera_alt
                                    : Icons.rotate_right,
                                title:
                                    'Point $i · ${i == 1 ? 'Initial solve' : '${_east ? 'East' : 'West'} ${(i - 1) * _slewDegrees.round()}°'}',
                                subtitle:
                                    'Waiting for camera, mount and plate solver.',
                              ),
                              const SizedBox(height: 8),
                            ],
                            Expanded(
                              child: _PolarCorrectionView(
                                altitudeError: _altitudeErrorArcmin,
                                azimuthError: _azimuthErrorArcmin,
                                hasResult: _hasCorrection,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const _InspectorSectionLabel(
                              'MOVE THE MOUNT KNOBS',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              !_hasCorrection
                                  ? 'Complete the measurement sequence to calculate the required knob movements.'
                                  : 'ALTITUDE: ${_altitudeErrorArcmin >= 0 ? 'raise' : 'lower'} the mount axis by ${_angle(_altitudeErrorArcmin)}.  AZIMUTH: move the mount base ${_azimuthErrorArcmin >= 0 ? 'east/right' : 'west/left'} by ${_angle(_azimuthErrorArcmin)}.',
                              style: const TextStyle(
                                color: Color(0xFFFFD166),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _refreshing
                                        ? null
                                        : _refreshCorrection,
                                    icon: _refreshing
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.refresh),
                                    label: const Text(
                                      'Refresh after knob adjustment',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const _InspectorSectionLabel('CORRECTION RESULT'),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Altitude error',
                                    value: _hasCorrection
                                        ? _angle(_altitudeErrorArcmin)
                                        : '—',
                                  ),
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Azimuth error',
                                    value: _hasCorrection
                                        ? _angle(_azimuthErrorArcmin)
                                        : '—',
                                  ),
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: _InspectorField(
                                    label: 'Total error',
                                    value: _hasCorrection
                                        ? _angle(
                                            math.sqrt(
                                              _altitudeErrorArcmin *
                                                      _altitudeErrorArcmin +
                                                  _azimuthErrorArcmin *
                                                      _azimuthErrorArcmin,
                                            ),
                                          )
                                        : '—',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolarCorrectionView extends StatelessWidget {
  const _PolarCorrectionView({
    required this.altitudeError,
    required this.azimuthError,
    required this.hasResult,
  });

  final double altitudeError;
  final double azimuthError;
  final bool hasResult;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF081522),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF213247)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _PolarCorrectionPainter(
              altitudeError: altitudeError,
              azimuthError: azimuthError,
              hasResult: hasResult,
            ),
          ),
          const Positioned(
            left: 10,
            top: 8,
            child: Text(
              'POLAR AXIS CORRECTION MAP',
              style: TextStyle(
                color: Color(0xFF93A8BF),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Positioned(
            left: 10,
            bottom: 7,
            child: Row(
              children: [
                Icon(Icons.circle, size: 9, color: Color(0xFF55E6A5)),
                SizedBox(width: 4),
                Text('Target', style: TextStyle(fontSize: 9)),
                SizedBox(width: 10),
                Icon(Icons.circle, size: 9, color: Color(0xFFFFB84D)),
                SizedBox(width: 4),
                Text('Current axis', style: TextStyle(fontSize: 9)),
              ],
            ),
          ),
          if (!hasResult)
            const Center(
              child: Text(
                'Waiting for polar-alignment solve',
                style: TextStyle(color: Color(0xFF7189A2)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PolarCorrectionPainter extends CustomPainter {
  const _PolarCorrectionPainter({
    required this.altitudeError,
    required this.azimuthError,
    required this.hasResult,
  });

  final double altitudeError;
  final double azimuthError;
  final bool hasResult;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final grid = Paint()
      ..color = const Color(0xFF213247)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 26, grid);
    canvas.drawCircle(center, 52, grid);
    canvas.drawLine(
      Offset(18, center.dy),
      Offset(size.width - 18, center.dy),
      grid,
    );
    canvas.drawLine(
      Offset(center.dx, 25),
      Offset(center.dx, size.height - 24),
      grid,
    );
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFF55E6A5));
    if (!hasResult) return;
    final scale = math.max(
      12.0,
      math.max(altitudeError.abs(), azimuthError.abs()),
    );
    final current = Offset(
      center.dx + azimuthError / scale * size.width * .34,
      center.dy - altitudeError / scale * size.height * .34,
    );
    final vector = Paint()
      ..color = const Color(0xFFFFB84D)
      ..strokeWidth = 2.5;
    canvas.drawLine(current, center, vector);
    canvas.drawCircle(current, 7, Paint()..color = const Color(0xFFFFB84D));
    final direction = center - current;
    final length = direction.distance;
    if (length > 4) {
      final unit = direction / length;
      final normal = Offset(-unit.dy, unit.dx);
      canvas.drawLine(center, center - unit * 12 + normal * 6, vector);
      canvas.drawLine(center, center - unit * 12 - normal * 6, vector);
    }
  }

  @override
  bool shouldRepaint(covariant _PolarCorrectionPainter oldDelegate) =>
      altitudeError != oldDelegate.altitudeError ||
      azimuthError != oldDelegate.azimuthError ||
      hasResult != oldDelegate.hasResult;
}

class _SystemPage extends StatefulWidget {
  const _SystemPage();

  @override
  State<_SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<_SystemPage> {
  Map<String, dynamic> _details = const {
    'hostname': 'astroberry',
    'astroberry_version': '3.2',
    'temperature_c': 56.2,
    'storage': {
      'total_bytes': 125327712256,
      'used_bytes': 7981252608,
      'free_bytes': 112170409984,
    },
    'packages': {
      'astap': '2024.05.01-1',
      'astrometry_net': '0.97+dfsg-2',
      'stellarsolver': '2.7-1',
      'kstars': '6:3.8.2-1',
      'indi': '2.2.1',
    },
    'solver_data': {
      'astap_database_files': 0,
      'astap_ready': false,
      'astrometry_index_files': 0,
      'astrometry_ready': false,
    },
    'cached_update_count': 0,
  };
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (!kPreviewMode) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$kBridgeBaseUrl/system/details'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) {
        setState(() => _details = jsonDecode(response.body));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read Astroberry status')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _gigabytes(Object? bytes) =>
      '${((bytes as num? ?? 0) / 1073741824).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final packages = _details['packages'] as Map<String, dynamic>? ?? const {};
    final solver = _details['solver_data'] as Map<String, dynamic>? ?? const {};
    final storage = _details['storage'] as Map<String, dynamic>? ?? const {};
    return SafeArea(
      child: Column(
        children: [
          const _ModuleHeader(
            title: 'Astroberry System',
            subtitle: 'Pi health, software updates and offline solver data',
            icon: Icons.memory,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Card(
                      child: ListView(
                        padding: const EdgeInsets.all(15),
                        children: [
                          const _InspectorTitle(
                            title: 'Raspberry Pi health',
                            subtitle: 'Live data from the AstroField bridge',
                            icon: Icons.developer_board,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _InspectorField(
                                  label: 'Host',
                                  value: '${_details['hostname'] ?? '—'}',
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _InspectorField(
                                  label: 'Astroberry',
                                  value:
                                      '${_details['astroberry_version'] ?? '—'}',
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _InspectorField(
                                  label: 'CPU temperature',
                                  value:
                                      '${(_details['temperature_c'] as num?)?.toStringAsFixed(1) ?? '—'} °C',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _InspectorField(
                                  label: 'Storage used',
                                  value: _gigabytes(storage['used_bytes']),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _InspectorField(
                                  label: 'Storage free',
                                  value: _gigabytes(storage['free_bytes']),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _InspectorField(
                                  label: 'Cached updates',
                                  value:
                                      '${_details['cached_update_count'] ?? 0}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const _InspectorSectionLabel('INSTALLED SOFTWARE'),
                          const SizedBox(height: 7),
                          _SoftwareRow(
                            name: 'KStars / Ekos',
                            version: '${packages['kstars'] ?? '—'}',
                          ),
                          _SoftwareRow(
                            name: 'INDI',
                            version: '${packages['indi'] ?? '—'}',
                          ),
                          _SoftwareRow(
                            name: 'StellarSolver',
                            version: '${packages['stellarsolver'] ?? '—'}',
                          ),
                          _SoftwareRow(
                            name: 'ASTAP',
                            version: '${packages['astap'] ?? '—'}',
                          ),
                          _SoftwareRow(
                            name: 'Astrometry.net',
                            version: '${packages['astrometry_net'] ?? '—'}',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _refresh,
                            icon: _loading
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('Refresh system status'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: ListView(
                        padding: const EdgeInsets.all(15),
                        children: [
                          const _InspectorTitle(
                            title: 'Plate-solving data',
                            subtitle:
                                'Offline catalogues selected for this optical train',
                            icon: Icons.auto_fix_high,
                          ),
                          const SizedBox(height: 14),
                          _SolverDataTile(
                            title: 'ASTAP star database',
                            ready: solver['astap_ready'] == true,
                            detail: solver['astap_ready'] == true
                                ? '${solver['astap_database_files']} files installed'
                                : 'Engine installed · star database missing',
                          ),
                          const SizedBox(height: 8),
                          _SolverDataTile(
                            title: 'Astrometry.net indexes',
                            ready: solver['astrometry_ready'] == true,
                            detail: solver['astrometry_ready'] == true
                                ? '${solver['astrometry_index_files']} index files installed'
                                : 'No offline index files installed',
                          ),
                          const SizedBox(height: 14),
                          const _InspectorSectionLabel(
                            'RECOMMENDED FOR 2.69° × 1.80° FOV',
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'ASTAP D50 database, or Astrometry.net 5205–5206 and 4107–4111 indexes. The exact recommendation will recalculate from the saved telescope and camera.',
                            style: TextStyle(
                              color: Color(0xFF93A8BF),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const _InspectorSectionLabel('PHONE INTERNET RELAY'),
                          const SizedBox(height: 7),
                          const Text(
                            'The phone downloads an official catalogue over cellular data, verifies its checksum, then uploads it to the Pi over the Astroberry Wi-Fi link.',
                            style: TextStyle(
                              color: Color(0xFF93A8BF),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.phone_android),
                            label: const Text(
                              'Download recommended solver data',
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'System-package upgrades will require external power, no active imaging session and explicit confirmation.',
                            style: TextStyle(
                              color: Color(0xFFFFC857),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftwareRow extends StatelessWidget {
  const _SoftwareRow({required this.name, required this.version});
  final String name;
  final String version;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        Text(version, style: const TextStyle(color: Color(0xFF93A8BF))),
      ],
    ),
  );
}

class _SolverDataTile extends StatelessWidget {
  const _SolverDataTile({
    required this.title,
    required this.ready,
    required this.detail,
  });
  final String title;
  final bool ready;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0B1727),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: ready ? const Color(0xFF285D50) : const Color(0xFF6A4E27),
      ),
    ),
    child: Row(
      children: [
        Icon(
          ready ? Icons.check_circle : Icons.warning_amber,
          color: ready ? const Color(0xFF55E6A5) : const Color(0xFFFFC857),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF93A8BF), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SessionPage extends StatelessWidget {
  const _SessionPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const _ModuleHeader(
            title: 'Session',
            subtitle: 'Autorun sequences and multi-target plans',
            icon: Icons.event_note_outlined,
          ),
          const _InfoCard(
            icon: Icons.nights_stay_outlined,
            title: 'No active imaging plan',
            subtitle:
                'Create a target, configure filters and choose the number of exposures.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AUTOMATION PIPELINE',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7189A2),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      Chip(label: Text('Track')),
                      Chip(label: Text('Focus')),
                      Chip(label: Text('Align')),
                      Chip(label: Text('Guide')),
                      Chip(label: Text('Capture')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.add),
                      label: const Text('Create imaging plan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF67D4FF)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF93A8BF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RigDashboard extends StatefulWidget {
  const RigDashboard({super.key});

  @override
  State<RigDashboard> createState() => _RigDashboardState();
}

class _RigDashboardState extends State<RigDashboard> {
  static String get _bridgeBaseUrl => kBridgeBaseUrl;
  static const _bridgeToken = kBridgeToken;
  Timer? _refreshTimer;
  Map<String, dynamic>? _system;
  String? _error;
  String _locationMessage = 'Waiting for Astroberry connection';
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  bool _loading = true;
  bool _locationBusy = false;
  bool _locationAttempted = false;

  @override
  void initState() {
    super.initState();
    if (kPreviewMode) {
      _system = {
        'hostname': 'astroberry',
        'astroberry_version': '3.2',
        'kstars_version': '6:3.8.2-1',
        'indi_version': '2.2.1',
        'architecture': 'aarch64',
        'indi_running': false,
      };
      _latitude = 17.38500;
      _longitude = 78.48670;
      _accuracy = 6;
      _locationMessage = 'Saved — it will apply when the telescope connects';
      _loading = false;
      return;
    }
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$_bridgeBaseUrl/system'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        throw Exception('Bridge returned ${response.statusCode}');
      }
      final system = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _system = system;
        _error = null;
        _loading = false;
      });
      if (!_locationAttempted) {
        _locationAttempted = true;
        unawaited(_syncPhoneLocation());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _syncPhoneLocation() async {
    if (_bridgeToken.isEmpty) {
      setState(() {
        _locationMessage = 'Pairing token required for location sync';
      });
      return;
    }
    setState(() {
      _locationBusy = true;
      _locationMessage = 'Requesting phone location…';
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled on this phone');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final response = await http
          .post(
            Uri.parse('$_bridgeBaseUrl/location'),
            headers: {
              'Content-Type': 'application/json',
              'X-AstroField-Token': _bridgeToken,
            },
            body: jsonEncode({
              'latitude': position.latitude,
              'longitude': position.longitude,
              'altitude': position.altitude,
              'accuracy': position.accuracy,
              'captured_at': position.timestamp.toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 && response.statusCode != 202) {
        throw Exception('Location sync returned ${response.statusCode}');
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final indi = result['indi'] as Map<String, dynamic>?;
      final applied = indi?['status'] == 'applied';
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
        _locationMessage = applied
            ? 'Applied to ${indi?['device'] ?? 'the telescope'}'
            : 'Saved — it will apply when the telescope connects';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _system != null && _error == null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AstroField', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'Mobile observatory control',
              style: TextStyle(fontSize: 12, color: Color(0xFF93A8BF)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _ConnectionCard(
              connected: connected,
              loading: _loading,
              hostname: _system?['hostname'] as String? ?? 'astroberry.local',
              error: _error,
            ),
            const SizedBox(height: 16),
            _PhoneLocationCard(
              busy: _locationBusy,
              message: _locationMessage,
              latitude: _latitude,
              longitude: _longitude,
              accuracy: _accuracy,
              onSync: connected && !_locationBusy ? _syncPhoneLocation : null,
            ),
            const SizedBox(height: 16),
            const Text(
              'SYSTEM',
              style: TextStyle(
                color: Color(0xFF7189A2),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _SystemGrid(system: _system),
            const SizedBox(height: 16),
            const Text(
              'RIG',
              style: TextStyle(
                color: Color(0xFF7189A2),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _RigCard(indiRunning: _system?['indi_running'] == true),
          ],
        ),
      ),
    );
  }
}

class _PhoneLocationCard extends StatelessWidget {
  const _PhoneLocationCard({
    required this.busy,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.onSync,
  });

  final bool busy;
  final String message;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final hasLocation = latitude != null && longitude != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF67D4FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Color(0xFF67D4FF)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phone location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasLocation
                        ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)} · ±${accuracy!.round()} m\n$message'
                        : message,
                    style: const TextStyle(
                      color: Color(0xFF93A8BF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Update from phone',
              onPressed: onSync,
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connected,
    required this.loading,
    required this.hostname,
    this.error,
  });

  final bool connected;
  final bool loading;
  final String hostname;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF46DBA7) : const Color(0xFFFFB867);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      connected ? Icons.router : Icons.cloud_off,
                      color: color,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'Astroberry connected' : 'Waiting for bridge',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    connected ? hostname : (error ?? 'Checking local network…'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF93A8BF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemGrid extends StatelessWidget {
  const _SystemGrid({required this.system});

  final Map<String, dynamic>? system;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _Metric(
          label: 'Astroberry',
          value: system?['astroberry_version'] ?? '—',
        ),
        _Metric(label: 'KStars', value: system?['kstars_version'] ?? '—'),
        _Metric(label: 'INDI', value: system?['indi_version'] ?? '—'),
        _Metric(label: 'Architecture', value: system?['architecture'] ?? '—'),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF7189A2), fontSize: 12),
            ),
            const SizedBox(height: 5),
            Text(
              '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RigCard extends StatelessWidget {
  const _RigCard({required this.indiRunning});

  final bool indiRunning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.hub_outlined,
              color: indiRunning
                  ? const Color(0xFF46DBA7)
                  : const Color(0xFF7189A2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INDI equipment server',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    indiRunning
                        ? 'Running — device discovery is ready'
                        : 'Stopped — start an Ekos profile to discover devices',
                    style: const TextStyle(
                      color: Color(0xFF93A8BF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
