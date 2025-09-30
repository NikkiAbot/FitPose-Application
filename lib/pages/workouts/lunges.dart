import 'package:flutter/material.dart';
import '../../components/camera_widget.dart';

class Lunges extends StatefulWidget {
  const Lunges({super.key});

  @override
  State<Lunges> createState() => _LungesState();
}

class _LungesState extends State<Lunges> {
  bool _showCamera = true; // Start with camera enabled

  @override
  void initState() {
    super.initState();
    // Show instructions popup when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showInstructionsDialog();
    });
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.fitness_center, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text(
                'Lunges Exercise',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exercise Instructions:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '1. Stand upright with feet hip-width apart\n'
                  '2. Step forward with one leg, lowering your hips\n'
                  '3. Bend both knees to 90-degree angles\n'
                  '4. Keep front knee over ankle, not pushed out past toes\n'
                  '5. Push back to starting position and repeat\n'
                  '6. Alternate legs or complete set on one side first',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use the camera to record your form and track your progress!',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Start Exercise',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showInstructionsAgain() {
    _showInstructionsDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar only shows when camera is active
      appBar:
          _showCamera
              ? AppBar(
                title: const Text('Lunges'),
                backgroundColor: Colors.black.withValues(alpha: 0.7),
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showInstructionsAgain,
                    tooltip: 'Show Instructions',
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_off),
                    onPressed: () {
                      setState(() {
                        _showCamera = false;
                      });
                    },
                    tooltip: 'Turn Off Camera',
                  ),
                ],
              )
              : AppBar(
                title: const Text('Lunges'),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.videocam),
                    onPressed: () {
                      setState(() {
                        _showCamera = true;
                      });
                    },
                    tooltip: 'Turn On Camera',
                  ),
                ],
              ),
      body:
          _showCamera
              ? // Full-screen camera view
              CameraWidget(
                showCamera: _showCamera,
                onToggleCamera: () {
                  setState(() {
                    _showCamera = !_showCamera;
                  });
                },
              )
              : // Instructions view when camera is off
              Container(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lunges Exercise',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Instructions:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '1. Stand upright with feet hip-width apart\n'
                      '2. Step forward with one leg, lowering your hips\n'
                      '3. Bend both knees to 90-degree angles\n'
                      '4. Keep front knee over ankle, not pushed out past toes\n'
                      '5. Push back to starting position and repeat\n'
                      '6. Alternate legs or complete set on one side first',
                      style: TextStyle(fontSize: 18, height: 1.6),
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showCamera = true;
                          });
                        },
                        icon: const Icon(Icons.videocam),
                        label: const Text('Start Camera'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Use the camera to record your form and track your progress!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
