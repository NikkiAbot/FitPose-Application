import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../components/camera_widget.dart';
import '../../core/engine.dart';
import 'features.dart';
import 'classifier.dart';
import 'fsm.dart';

class ShoulderPressPage extends StatefulWidget {
  const ShoulderPressPage({super.key});
  @override
  State<ShoulderPressPage> createState() => _ShoulderPressPageState();
}

class _ShoulderPressPageState extends State<ShoulderPressPage> {
  bool _showCamera = true;
  late final ExerciseEngine<ShoulderPressFeats> engine;
  final fsm = ShoulderPressFSM();
  String _label = "—";
  double _metric = 0.0;

  @override
  void initState() {
    super.initState();
    engine = ExerciseEngine(
      extractor: ShoulderPressExtractor(),
      classifier: ShoulderPressClassifier(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  @override
  void dispose() {
    engine.close();
    super.dispose();
  }

  void _onFrame(CameraImage img, int rotation, bool isFront) async {
    final out = await engine.process(img, rotation);
    if (out.feats == null) {
      setState(() => _label = "No Pose");
      return;
    }
    _metric = out.feats!.primaryMetric; // avg elbow angle
    fsm.update(metric: _metric, goodForm: out.good);
    setState(() => _label = out.label);
  }

  void _showDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.fitness_center, color: Colors.purple, size: 28),
              SizedBox(width: 8),
              Text('Shoulder Press', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Keep core tight. Press overhead without arching your back. '
            'Lower to shoulder level each rep.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleCamera() => setState(() => _showCamera = !_showCamera);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showCamera
          ? AppBar(
              title: const Text('Shoulder Press'),
              backgroundColor: Colors.black.withOpacity(0.7),
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              actions: [
                IconButton(icon: const Icon(Icons.info_outline), onPressed: _showDialog),
                IconButton(icon: const Icon(Icons.videocam_off), onPressed: _toggleCamera),
              ],
            )
          : AppBar(
              title: const Text('Shoulder Press'),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              actions: [IconButton(icon: const Icon(Icons.videocam), onPressed: _toggleCamera)],
            ),
      body: _showCamera
          ? Stack(
              children: [
                CameraWidget(
                  showCamera: _showCamera,
                  onToggleCamera: _toggleCamera,
                  onImage: _onFrame,
                ),
                Positioned(
                  left: 12, right: 12, top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('STATE: ${fsm.stateText}'),
                          Text('REPS: ${fsm.reps}'),
                          Text('FORM: $_label'),
                          Text('ELBOW: ${_metric.toStringAsFixed(1)}°'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _Instructions(onStart: _toggleCamera),
    );
  }
}

class _Instructions extends StatelessWidget {
  final VoidCallback onStart;
  const _Instructions({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shoulder Press Exercise', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text('Instructions:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text(
            '1) Feet shoulder-width\n'
            '2) Palms forward at shoulder level\n'
            '3) Press straight up overhead\n'
            '4) Keep core engaged (no back arch)\n'
            '5) Lower to shoulder level\n',
            style: TextStyle(fontSize: 18, height: 1.6),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.videocam),
              label: const Text('Start Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
