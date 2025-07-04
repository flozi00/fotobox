import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation and fullscreen
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Enable fullscreen mode
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Get available cameras
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhotoBox - Hintergrund entfernen',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: PhotoBoxScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PhotoBoxScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PhotoBoxScreen({super.key, required this.cameras});

  @override
  State<PhotoBoxScreen> createState() => _PhotoBoxScreenState();
}

class _PhotoBoxScreenState extends State<PhotoBoxScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  File? _capturedImage;
  String? _selectedBackground;
  Uint8List? _processedImage;
  Uint8List? _backgroundRemovedImage;
  bool _isLoading = false;
  bool _isSaving = false;
  String _status = 'Bereit für Foto';

  // New state variables for the enhanced flow
  bool _showWelcomeScreen = true;
  bool _showCountdown = false;
  int _countdownValue = 5;
  Timer? _countdownTimer;
  String? _selectedStorageLocation;

  // Animation controllers
  late AnimationController _cameraAnimationController;
  late AnimationController _captureAnimationController;
  late AnimationController _transitionAnimationController;
  late AnimationController _countdownAnimationController;
  late Animation<double> _cameraScale;
  late Animation<double> _captureButtonScale;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _countdownScale;

  // Screen state
  bool _showBackgroundSelection = false;

  // Available background assets
  final List<String> _backgroundAssets = [
    'assets/backgrounds/background1.jpg',
    'assets/backgrounds/background2.jpg',
    'assets/backgrounds/background3.jpg',
  ];

  // Sample images for welcome screen
  final List<String> _sampleImages = [
    'assets/backgrounds/background1.jpg',
    'assets/backgrounds/background2.jpg',
    'assets/backgrounds/background3.jpg',
    'assets/backgrounds/background1.jpg', // Repeat for 4 images
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _requestPermissions();
    _initializeStorageLocation();
    _selectedBackground = _backgroundAssets.first;
  }

  void _initializeAnimations() {
    // Camera animation controller
    _cameraAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Capture animation controller
    _captureAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Transition animation controller
    _transitionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Countdown animation controller
    _countdownAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Camera scale animation
    _cameraScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cameraAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    // Capture button scale animation
    _captureButtonScale = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(
        parent: _captureAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Slide animation for transition
    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _transitionAnimationController,
            curve: Curves.easeInOutCubic,
          ),
        );

    // Fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Countdown scale animation
    _countdownScale = Tween<double>(begin: 1.5, end: 0.5).animate(
      CurvedAnimation(
        parent: _countdownAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera].request();
  }

  Future<void> _initializeStorageLocation() async {
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        final photoBoxDir = Directory('${directory.path}/PhotoBox');
        if (!await photoBoxDir.exists()) {
          await photoBoxDir.create(recursive: true);
        }
        _selectedStorageLocation = photoBoxDir.path;
      }
    } catch (e) {
      print('Error initializing storage location: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isNotEmpty) {
      _cameraController = CameraController(
        widget.cameras.first,
        ResolutionPreset.high,
      );

      try {
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      } catch (e) {
        print('Fehler beim Initialisieren der Kamera: $e');
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cameraAnimationController.dispose();
    _captureAnimationController.dispose();
    _transitionAnimationController.dispose();
    _countdownAnimationController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startPhotoProcess() {
    setState(() {
      _showWelcomeScreen = false;
      _showCountdown = true;
      _countdownValue = 5;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownValue--;
      });

      // Animate countdown number
      _countdownAnimationController.forward().then((_) {
        _countdownAnimationController.reset();
      });

      if (_countdownValue <= 0) {
        timer.cancel();
        setState(() {
          _showCountdown = false;
        });
        _initializeCamera().then((_) {
          // Start camera animation
          _cameraAnimationController.forward();
          // Auto-take picture after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            _takePicture();
          });
        });
      }
    });
  }

  void _returnToWelcome() {
    setState(() {
      _showWelcomeScreen = true;
      _showBackgroundSelection = false;
      _showCountdown = false;
      _capturedImage = null;
      _processedImage = null;
      _backgroundRemovedImage = null;
      _selectedBackground = _backgroundAssets.first;
      _status = 'Bereit für Foto';
      _isLoading = false;
      _isSaving = false;
    });

    // Reset animations
    _transitionAnimationController.reset();
    _cameraAnimationController.reset();
    _cameraController?.dispose();
    _cameraController = null;
  }

  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isLoading) {
      return;
    }

    // Animate capture button
    await _captureAnimationController.forward();
    await _captureAnimationController.reverse();

    try {
      final XFile photo = await _cameraController!.takePicture();
      setState(() {
        _capturedImage = File(photo.path);
        _status = 'Foto aufgenommen! Hintergrund wird automatisch entfernt...';
      });

      // Start transition animation
      await _transitionAnimationController.forward();

      setState(() {
        _showBackgroundSelection = true;
      });

      // Automatically process the image after taking the picture
      await _processImage();
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Aufnehmen des Fotos: $e';
      });
    }
  }

  void _reset() {
    setState(() {
      _capturedImage = null;
      _processedImage = null;
      _backgroundRemovedImage = null;
      _selectedBackground = _backgroundAssets.first;
      _status = 'Bereit für Foto';
      _showBackgroundSelection = false;
      _isLoading = false;
    });

    // Reset animations
    _transitionAnimationController.reset();
    _cameraAnimationController.forward();
  }

  Future<void> _processImage() async {
    if (_capturedImage == null) {
      setState(() {
        _status = 'Bitte zuerst ein Foto aufnehmen.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Bild wird hochgeladen...';
      _backgroundRemovedImage = null;
      _processedImage = null;
    });

    try {
      // Step 1: Upload the image to Gradio server
      final imageBytes = await _capturedImage!.readAsBytes();

      setState(() {
        _status = 'Wird zum Server hochgeladen...';
      });

      final uploadRequest = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://not-lain-background-removal.hf.space/gradio_api/upload',
        ),
      );

      uploadRequest.files.add(
        http.MultipartFile.fromBytes(
          'files',
          imageBytes,
          filename: 'photo.jpg',
        ),
      );

      final uploadResponse = await uploadRequest.send();

      if (uploadResponse.statusCode != 200) {
        throw Exception(
          'Fehler beim Hochladen des Bildes: ${uploadResponse.statusCode}',
        );
      }

      final uploadResponseBody = await uploadResponse.stream.bytesToString();
      print('Upload response: $uploadResponseBody');

      // Parse the upload response to get the file path
      final uploadData = uploadResponseBody
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '');
      final filePath = uploadData.trim();

      setState(() {
        _status = 'Hintergrund wird entfernt...';
      });

      // Step 2: Call the background removal API
      final apiRequest = http.Request(
        'POST',
        Uri.parse(
          'https://not-lain-background-removal.hf.space/gradio_api/call/image',
        ),
      );

      apiRequest.headers['Content-Type'] = 'application/json';
      apiRequest.body =
          '''
{
  "data": [
    {
      "path": "$filePath",
      "meta": {"_type": "gradio.FileData"}
    }
  ]
}''';

      final apiResponse = await apiRequest.send();

      if (apiResponse.statusCode != 200) {
        throw Exception(
          'Fehler beim Verarbeiten des Bildes: ${apiResponse.statusCode}',
        );
      }

      final apiResponseBody = await apiResponse.stream.bytesToString();
      print('API response: $apiResponseBody');

      // Extract event ID from response
      final eventIdMatch = RegExp(
        r'"event_id":"([^"]+)"',
      ).firstMatch(apiResponseBody);
      if (eventIdMatch == null) {
        throw Exception(
          'Event-ID konnte nicht aus der Antwort extrahiert werden',
        );
      }

      final eventId = eventIdMatch.group(1)!;
      print('Event ID: $eventId');

      setState(() {
        _status = 'Warten auf Ergebnis...';
      });

      // Step 3: Get the result using the event ID
      await _getProcessedResult(eventId);
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Verarbeiten des Bildes: $e';
        _isLoading = false;
      });
      print('Error: $e');
    }
  }

  Future<void> _getProcessedResult(String eventId) async {
    try {
      final resultRequest = http.Request(
        'GET',
        Uri.parse(
          'https://not-lain-background-removal.hf.space/gradio_api/call/image/$eventId',
        ),
      );

      final client = http.Client();
      final response = await client.send(resultRequest);

      if (response.statusCode != 200) {
        throw Exception(
          'Fehler beim Abrufen des Ergebnisses: ${response.statusCode}',
        );
      }

      // Listen to the server-sent events stream
      await for (String line
          in response.stream
              .transform(const SystemEncoding().decoder)
              .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          print('Received data: $data');

          try {
            final jsonResponse = jsonDecode(data);
            print('Parsed JSON: $jsonResponse');

            final resultData =
                (jsonResponse is Map<String, dynamic> &&
                    jsonResponse.containsKey('data'))
                ? jsonResponse['data']
                : (jsonResponse is List &&
                      jsonResponse.isNotEmpty &&
                      jsonResponse[0] is List)
                ? jsonResponse[0]
                : null;

            if (resultData is List && resultData.isNotEmpty) {
              print('Result data: $resultData');

              final resultItem = resultData.first;
              print('Selected result item: $resultItem');

              String? imageUrl;

              if (resultItem is Map<String, dynamic>) {
                imageUrl = resultItem['url'] as String?;
              } else if (resultItem is String) {
                imageUrl = resultItem;
              }

              if (imageUrl != null) {
                print('Result URL: $imageUrl');

                if (!imageUrl.startsWith('http')) {
                  imageUrl =
                      'https://not-lain-background-removal.hf.space/gradio_api/file=$imageUrl';
                }

                print('Final URL: $imageUrl');

                final imageResponse = await http.get(Uri.parse(imageUrl));
                if (imageResponse.statusCode == 200) {
                  setState(() {
                    _backgroundRemovedImage = imageResponse.bodyBytes;
                    _status =
                        'Hintergrund entfernt! Wählen Sie einen Hintergrund zum Kombinieren.';
                  });

                  await _compositeWithBackground();
                  client.close();
                  return;
                } else {
                  print(
                    'Failed to download image. Status: ${imageResponse.statusCode}',
                  );
                  throw Exception(
                    'Fehler beim Herunterladen des verarbeiteten Bildes: ${imageResponse.statusCode}',
                  );
                }
              } else {
                print('No URL found in result data');
              }
            } else {
              print('Could not find result data in JSON response');
            }

            throw Exception(
              'Bild-URL konnte nicht aus dem Ergebnis extrahiert werden',
            );
          } catch (e) {
            print('Error parsing result: $e');
            setState(() {
              _status = 'Fehler beim Parsen des Ergebnisses: $e';
            });
            client.close();
            return;
          }
        }
      }

      client.close();
      throw Exception('Kein vollständiges Event erhalten');
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Abrufen des Ergebnisses: $e';
        _isLoading = false;
      });
      print('Error getting result: $e');
    }
  }

  void _selectBackground(String backgroundAsset) {
    setState(() {
      _selectedBackground = backgroundAsset;
      _status =
          'Hintergrund ausgewählt! Zusammengesetztes Bild wird erstellt...';
    });

    _compositeWithBackground();
  }

  Future<void> _compositeWithBackground() async {
    if (_backgroundRemovedImage == null || _selectedBackground == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Zusammengesetztes Bild wird erstellt...';
    });

    try {
      final foreground = img.decodeImage(_backgroundRemovedImage!);
      if (foreground == null) {
        throw Exception('Vordergrund-Bild konnte nicht dekodiert werden');
      }

      final backgroundBytes = await rootBundle.load(_selectedBackground!);
      final background = img.decodeJpg(backgroundBytes.buffer.asUint8List());
      if (background == null) {
        throw Exception('Hintergrund-Bild konnte nicht dekodiert werden');
      }

      final resizedBackground = img.copyResize(
        background,
        width: foreground.width,
        height: foreground.height,
      );

      img.compositeImage(resizedBackground, foreground);

      final compositeBytes = img.encodePng(resizedBackground);

      setState(() {
        _processedImage = Uint8List.fromList(compositeBytes);
        _status = 'Zusammengesetztes Bild erfolgreich erstellt!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Erstellen des zusammengesetzten Bildes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProcessedImage() async {
    if (_processedImage == null) {
      setState(() {
        _status = 'Kein verarbeitetes Bild zum Speichern verfügbar.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _status = 'Bild wird gespeichert...';
    });

    try {
      // Request storage permission
      await Permission.storage.request();

      // Use pre-selected storage location
      String? directoryPath = _selectedStorageLocation;

      if (directoryPath == null) {
        // Fallback if storage location wasn't initialized
        Directory? directory;
        if (Platform.isAndroid) {
          directory = await getExternalStorageDirectory();
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory != null) {
          final photoBoxDir = Directory('${directory.path}/PhotoBox');
          if (!await photoBoxDir.exists()) {
            await photoBoxDir.create(recursive: true);
          }
          directoryPath = photoBoxDir.path;
        }
      }

      if (directoryPath != null) {
        // Generate unique filename with timestamp
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'photobox_$timestamp.png';
        final filePath = '$directoryPath/$fileName';

        // Write the image to file
        final file = File(filePath);
        await file.writeAsBytes(_processedImage!);

        setState(() {
          _status = 'Bild erfolgreich gespeichert: $fileName';
          _isSaving = false;
        });

        // Show success dialog and return to welcome screen
        if (mounted) {
          _showSaveSuccessDialog(filePath);
        }
      } else {
        throw Exception('Speicherordner konnte nicht gefunden werden');
      }
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Speichern des Bildes: $e';
        _isSaving = false;
      });
    }
  }

  void _showSaveSuccessDialog(String filePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Erfolgreich gespeichert!',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Das Bild wurde gespeichert unter:\n$filePath',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _returnToWelcome();
              },
              child: const Text(
                'Zurück zum Start',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Welcome Screen with four images
          if (_showWelcomeScreen) _buildWelcomeScreen(),

          // Countdown Screen
          if (_showCountdown) _buildCountdownScreen(),

          // Fullscreen Camera View
          if (!_showWelcomeScreen &&
              !_showCountdown &&
              !_showBackgroundSelection)
            _buildFullscreenCamera(),

          // Background Selection View
          if (_showBackgroundSelection) _buildBackgroundSelectionView(),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Container(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          // Top row of images
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(child: _buildSampleImage(0)),
                const SizedBox(width: 16),
                Expanded(child: _buildSampleImage(1)),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Middle section with title and start button
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'PhotoBox',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Automatische Hintergrundentfernung',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _startPhotoProcess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedStorageLocation != null)
                    Text(
                      'Speicherort: $_selectedStorageLocation',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Bottom row of images
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(child: _buildSampleImage(2)),
                const SizedBox(width: 16),
                Expanded(child: _buildSampleImage(0)), // Repeat first image
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleImage(int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          _sampleImages[index],
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[800],
              child: Center(
                child: Text(
                  'Beispiel ${index + 1}',
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCountdownScreen() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Bereit machen!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            AnimatedBuilder(
              animation: _countdownScale,
              builder: (context, child) {
                return Transform.scale(
                  scale: _countdownScale.value,
                  child: Text(
                    _countdownValue > 0 ? _countdownValue.toString() : 'Los!',
                    style: TextStyle(
                      color: _countdownValue > 0 ? Colors.red : Colors.green,
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenCamera() {
    return AnimatedBuilder(
      animation: _cameraScale,
      builder: (context, child) {
        return Transform.scale(
          scale: _cameraScale.value,
          child: Stack(
            children: [
              // Camera Preview
              Positioned.fill(child: _buildCameraPreview()),

              // Capture Button (auto-triggered, but shown for visual feedback)
              Positioned(
                right: 50,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _captureButtonScale,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _captureButtonScale.value,
                        child: _buildCaptureButton(),
                      );
                    },
                  ),
                ),
              ),

              // Status overlay
              if (_status != 'Bereit für Foto')
                Positioned(
                  top: 50,
                  left: 50,
                  right: 50,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return CameraPreview(_cameraController!);
    } else {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 80, color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Kamera wird initialisiert...',
                style: TextStyle(color: Colors.white54, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildCaptureButton() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isLoading ? Colors.grey : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.camera_alt, size: 40, color: Colors.black),
    );
  }

  Widget _buildBackgroundSelectionView() {
    return AnimatedBuilder(
      animation: _transitionAnimationController,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    // Captured image preview
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header with back button
                          Row(
                            children: [
                              IconButton(
                                onPressed: _returnToWelcome,
                                icon: const Icon(
                                  Icons.home,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(
                                    0.1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _status,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Captured image
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _capturedImage != null
                                    ? Image.file(
                                        _capturedImage!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.grey[800],
                                        child: const Center(
                                          child: Icon(
                                            Icons.image,
                                            size: 64,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Background selection and result
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Background Selection
                          if (_backgroundRemovedImage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Hintergrund wählen',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Background thumbnails
                                  ...List.generate(
                                    _backgroundAssets.length,
                                    (index) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12.0,
                                      ),
                                      child: GestureDetector(
                                        onTap: () => _selectBackground(
                                          _backgroundAssets[index],
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          height: 80,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color:
                                                  _selectedBackground ==
                                                      _backgroundAssets[index]
                                                  ? Colors.blue
                                                  : Colors.white.withOpacity(
                                                      0.3,
                                                    ),
                                              width:
                                                  _selectedBackground ==
                                                      _backgroundAssets[index]
                                                  ? 3
                                                  : 1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            boxShadow:
                                                _selectedBackground ==
                                                    _backgroundAssets[index]
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.blue
                                                          .withOpacity(0.3),
                                                      blurRadius: 8,
                                                      spreadRadius: 1,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Image.asset(
                                              _backgroundAssets[index],
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.grey[700],
                                                      child: Center(
                                                        child: Text(
                                                          'Hintergrund ${index + 1}',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Processed Image Result
                          if (_processedImage != null) ...[
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Endergebnis',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        // Save Button
                                        ElevatedButton.icon(
                                          onPressed: _isSaving
                                              ? null
                                              : _saveProcessedImage,
                                          icon: _isSaving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.save,
                                                  size: 18,
                                                ),
                                          label: Text(
                                            _isSaving
                                                ? 'Speichern...'
                                                : 'Speichern',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.memory(
                                            _processedImage!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
