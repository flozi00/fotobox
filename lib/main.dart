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
  CameraDescription? _selectedCamera;
  List<File?> _capturedImages = [null, null, null, null]; // Store 4 photos
  List<Uint8List?> _processedImages = [
    null,
    null,
    null,
    null,
  ]; // Store 4 processed images
  List<Uint8List?> _backgroundRemovedImages = [
    null,
    null,
    null,
    null,
  ]; // Store 4 background removed images
  String? _selectedBackground;
  bool _isLoading = false;
  bool _isSaving = false;
  String _status = 'Bereit für Foto-Serie';

  // Timer and photo sequence state
  bool _isCountdownActive = false;
  int _currentPhotoIndex = 0;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;
  Timer? _photoTimer;

  // Animation controllers
  late AnimationController _cameraAnimationController;
  late AnimationController _captureAnimationController;
  late AnimationController _transitionAnimationController;
  late Animation<double> _cameraScale;
  late Animation<double> _captureButtonScale;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Screen state
  bool _showBackgroundSelection = false;

  // Available background assets
  final List<String> _backgroundAssets = [
    'assets/backgrounds/background1.jpg',
    'assets/backgrounds/background2.jpg',
    'assets/backgrounds/background3.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _requestPermissions();
    if (widget.cameras.isNotEmpty) {
      _selectedCamera = widget.cameras.first;
      _initializeCamera();
    }
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

    // Start camera animation
    _cameraAnimationController.forward();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera].request();
  }

  Future<void> _initializeCamera() async {
    if (_selectedCamera != null) {
      _cameraController = CameraController(
        _selectedCamera!,
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

  Future<void> _onCameraSelected(CameraDescription camera) async {
    if (_selectedCamera == camera) return;

    setState(() {
      _selectedCamera = camera;
      _isLoading = true;
      _status = 'Kamera wird gewechselt...';
    });

    // Dispose current controller
    await _cameraController?.dispose();
    _cameraController = null;

    // Initialize new camera
    await _initializeCamera();

    setState(() {
      _isLoading = false;
      _status = 'Bereit für Foto-Serie';
    });
  }

  // Helper method to get camera lens icon
  IconData _getCameraLensIcon(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return Icons.camera_rear;
      case CameraLensDirection.front:
        return Icons.camera_front;
      case CameraLensDirection.external:
        return Icons.camera;
    }
  }

  // Helper method to get camera display name
  String _getCameraDisplayName(CameraDescription camera) {
    switch (camera.lensDirection) {
      case CameraLensDirection.back:
        return 'Rückkamera';
      case CameraLensDirection.front:
        return 'Frontkamera';
      case CameraLensDirection.external:
        return 'Externe Kamera';
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cameraAnimationController.dispose();
    _captureAnimationController.dispose();
    _transitionAnimationController.dispose();
    _countdownTimer?.cancel();
    _photoTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPhotoSequence() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isLoading ||
        _isCountdownActive) {
      return;
    }

    setState(() {
      _isCountdownActive = true;
      _currentPhotoIndex = 0;
      _countdownSeconds = 5;
      _status = 'Foto-Serie startet in $_countdownSeconds Sekunden...';
      _capturedImages = [null, null, null, null];
      _processedImages = [null, null, null, null];
      _backgroundRemovedImages = [null, null, null, null];
    });

    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
        if (_countdownSeconds > 0) {
          _status =
              'Foto ${_currentPhotoIndex + 1} in $_countdownSeconds Sekunden...';
        } else {
          _status = 'Foto ${_currentPhotoIndex + 1} wird aufgenommen...';
        }
      });

      if (_countdownSeconds <= 0) {
        timer.cancel();
        _takeSinglePhoto();
      }
    });
  }

  Future<void> _takeSinglePhoto() async {
    try {
      // Animate capture button
      await _captureAnimationController.forward();
      await _captureAnimationController.reverse();

      final XFile photo = await _cameraController!.takePicture();
      setState(() {
        _capturedImages[_currentPhotoIndex] = File(photo.path);
        _status = 'Foto ${_currentPhotoIndex + 1} aufgenommen!';
      });

      _currentPhotoIndex++;

      if (_currentPhotoIndex < 4) {
        // Schedule next photo
        setState(() {
          _countdownSeconds = 5;
          _status =
              'Nächstes Foto ${_currentPhotoIndex + 1} in $_countdownSeconds Sekunden...';
        });
        _startCountdown();
      } else {
        // All photos taken, start processing
        setState(() {
          _isCountdownActive = false;
          _status = 'Alle 4 Fotos aufgenommen! Hintergründe werden entfernt...';
          _showBackgroundSelection = true;
        });

        // Start transition animation
        await _transitionAnimationController.forward();

        // Process all images
        await _processAllImages();
      }
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Aufnehmen des Fotos: $e';
        _isCountdownActive = false;
      });
    }
  }

  Future<void> _processAllImages() async {
    setState(() {
      _isLoading = true;
    });

    for (int i = 0; i < 4; i++) {
      if (_capturedImages[i] != null) {
        setState(() {
          _status = 'Hintergrund wird von Foto ${i + 1} entfernt...';
        });

        await _processImageAtIndex(i);
      }
    }

    setState(() {
      _isLoading = false;
      _status =
          'Alle Hintergründe entfernt! Wählen Sie einen Hintergrund zum Kombinieren.';
    });
  }

  Future<void> _takePicture() async {
    // This method is now replaced by _startPhotoSequence
    await _startPhotoSequence();
  }

  void _reset() {
    setState(() {
      _capturedImages = [null, null, null, null];
      _processedImages = [null, null, null, null];
      _backgroundRemovedImages = [null, null, null, null];
      _selectedBackground = _backgroundAssets.first;
      _status = 'Bereit für Foto-Serie';
      _showBackgroundSelection = false;
      _isLoading = false;
      _isCountdownActive = false;
      _currentPhotoIndex = 0;
    });

    // Cancel any active timers
    _countdownTimer?.cancel();
    _photoTimer?.cancel();

    // Reset animations but keep camera selection
    _transitionAnimationController.reset();
    _cameraAnimationController.forward();
  }

  Future<void> _processImageAtIndex(int index) async {
    if (_capturedImages[index] == null) {
      return;
    }

    try {
      // Step 1: Upload the image to Gradio server
      final imageBytes = await _capturedImages[index]!.readAsBytes();

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
          filename: 'photo_$index.jpg',
        ),
      );

      final uploadResponse = await uploadRequest.send();

      if (uploadResponse.statusCode != 200) {
        throw Exception(
          'Fehler beim Hochladen des Bildes ${index + 1}: ${uploadResponse.statusCode}',
        );
      }

      final uploadResponseBody = await uploadResponse.stream.bytesToString();

      // Parse the upload response to get the file path
      final uploadData = uploadResponseBody
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '');
      final filePath = uploadData.trim();

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
          'Fehler beim Verarbeiten des Bildes ${index + 1}: ${apiResponse.statusCode}',
        );
      }

      final apiResponseBody = await apiResponse.stream.bytesToString();

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

      // Step 3: Get the result using the event ID
      await _getProcessedResultAtIndex(eventId, index);
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Verarbeiten des Bildes ${index + 1}: $e';
      });
      print('Error processing image $index: $e');
    }
  }

  Future<void> _getProcessedResultAtIndex(String eventId, int index) async {
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

          try {
            final jsonResponse = jsonDecode(data);

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
              final resultItem = resultData.first;

              String? imageUrl;

              if (resultItem is Map<String, dynamic>) {
                imageUrl = resultItem['url'] as String?;
              } else if (resultItem is String) {
                imageUrl = resultItem;
              }

              if (imageUrl != null) {
                if (!imageUrl.startsWith('http')) {
                  imageUrl =
                      'https://not-lain-background-removal.hf.space/gradio_api/file=$imageUrl';
                }

                final imageResponse = await http.get(Uri.parse(imageUrl));
                if (imageResponse.statusCode == 200) {
                  setState(() {
                    _backgroundRemovedImages[index] = imageResponse.bodyBytes;
                  });

                  await _compositeWithBackgroundAtIndex(index);
                  client.close();
                  return;
                } else {
                  throw Exception(
                    'Fehler beim Herunterladen des verarbeiteten Bildes: ${imageResponse.statusCode}',
                  );
                }
              }
            }

            throw Exception(
              'Bild-URL konnte nicht aus dem Ergebnis extrahiert werden',
            );
          } catch (e) {
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
      });
      print('Error getting result: $e');
    }
  }

  Future<void> _compositeWithBackgroundAtIndex(int index) async {
    if (_backgroundRemovedImages[index] == null ||
        _selectedBackground == null) {
      return;
    }

    try {
      final foreground = img.decodeImage(_backgroundRemovedImages[index]!);
      if (foreground == null) {
        throw Exception(
          'Vordergrund-Bild $index konnte nicht dekodiert werden',
        );
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
        _processedImages[index] = Uint8List.fromList(compositeBytes);
      });
    } catch (e) {
      setState(() {
        _status =
            'Fehler beim Erstellen des zusammengesetzten Bildes $index: $e';
      });
    }
  }

  void _selectBackground(String backgroundAsset) {
    setState(() {
      _selectedBackground = backgroundAsset;
      _status =
          'Hintergrund ausgewählt! Zusammengesetzte Bilder werden erstellt...';
    });

    _compositeAllWithBackground();
  }

  Future<void> _compositeAllWithBackground() async {
    setState(() {
      _isLoading = true;
    });

    for (int i = 0; i < 4; i++) {
      if (_backgroundRemovedImages[i] != null) {
        await _compositeWithBackgroundAtIndex(i);
      }
    }

    setState(() {
      _isLoading = false;
      _status = 'Alle zusammengesetzten Bilder erfolgreich erstellt!';
    });
  }

  // Add this method to save all processed images
  Future<void> _saveAllProcessedImages() async {
    bool hasAnyProcessedImage = _processedImages.any((image) => image != null);

    if (!hasAnyProcessedImage) {
      setState(() {
        _status = 'Keine verarbeiteten Bilder zum Speichern verfügbar.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _status = 'Bilder werden gespeichert...';
    });

    try {
      // Request storage permission
      await Permission.storage.request();

      // Get the documents directory (or use getApplicationDocumentsDirectory for app-specific folder)
      Directory? directory;

      if (Platform.isAndroid) {
        // For Android, use external storage
        directory = await getExternalStorageDirectory();
      } else {
        // For iOS/other platforms, use documents directory
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        // Create PhotoBox folder if it doesn't exist
        final photoBoxDir = Directory('${directory.path}/PhotoBox');
        if (!await photoBoxDir.exists()) {
          await photoBoxDir.create(recursive: true);
        }

        // Generate unique filename with timestamp
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        int savedCount = 0;

        for (int i = 0; i < 4; i++) {
          if (_processedImages[i] != null) {
            final fileName = 'photobox_${timestamp}_${i + 1}.png';
            final filePath = '${photoBoxDir.path}/$fileName';
            final file = File(filePath);
            await file.writeAsBytes(_processedImages[i]!);
            savedCount++;
          }
        }

        setState(() {
          _status = '$savedCount Bilder erfolgreich gespeichert!';
          _isSaving = false;
        });

        // Show success dialog
        if (mounted) {
          _showSaveSuccessDialog(photoBoxDir.path, savedCount);
        }
      } else {
        throw Exception('Speicherordner konnte nicht gefunden werden');
      }
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Speichern der Bilder: $e';
        _isSaving = false;
      });
    }
  }

  // Update this method to show success dialog for multiple images
  void _showSaveSuccessDialog(String folderPath, int savedCount) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Erfolgreich gespeichert!',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '$savedCount Bilder wurden gespeichert unter:\n$folderPath',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.blue)),
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
          // Fullscreen Camera View
          if (!_showBackgroundSelection) _buildFullscreenCamera(),

          // Background Selection View
          if (_showBackgroundSelection) _buildBackgroundSelectionView(),
        ],
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
              // Main camera preview (larger)
              Positioned(
                left: 0,
                top: 0,
                right: 200,
                bottom: 0,
                child: _buildCameraPreview(),
              ),

              // Camera selection dropdown (always show for debugging)
              if (widget.cameras.isNotEmpty)
                Positioned(
                  left: 20,
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: DropdownButton<CameraDescription>(
                      value: _selectedCamera,
                      dropdownColor: Colors.grey[900],
                      underline: Container(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                      items: widget.cameras.map((camera) {
                        return DropdownMenuItem<CameraDescription>(
                          value: camera,
                          child: Row(
                            children: [
                              Icon(
                                _getCameraLensIcon(camera.lensDirection),
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getCameraDisplayName(camera),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (camera) {
                        if (camera != null &&
                            !_isCountdownActive &&
                            !_isLoading) {
                          _onCameraSelected(camera);
                        }
                      },
                    ),
                  ),
                ),

              // Debug info panel (can be removed later)
              Positioned(
                left: 20,
                top: 80,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Kameras gefunden: ${widget.cameras.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),

              // 4 photo slots on the right
              Positioned(
                right: 20,
                top: 20,
                bottom: 20,
                width: 160,
                child: Column(
                  children: [
                    // Photo slot headers
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _isCountdownActive
                            ? 'Foto ${_currentPhotoIndex + 1} wird aufgenommen...'
                            : 'Foto-Serie (4 Fotos)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // 4 photo preview slots
                    Expanded(
                      child: Column(
                        children: List.generate(4, (index) {
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color:
                                      _currentPhotoIndex == index &&
                                          _isCountdownActive
                                      ? Colors.red
                                      : _capturedImages[index] != null
                                      ? Colors.green
                                      : Colors.white.withOpacity(0.3),
                                  width:
                                      _currentPhotoIndex == index &&
                                          _isCountdownActive
                                      ? 3
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: _capturedImages[index] != null
                                    ? Image.file(
                                        _capturedImages[index]!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.grey[800],
                                        child: Center(
                                          child:
                                              _currentPhotoIndex == index &&
                                                  _isCountdownActive
                                              ? Text(
                                                  '$_countdownSeconds',
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              // Capture Button
              Positioned(
                right: 50,
                bottom: 50,
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

              // Status overlay
              if (_status != 'Bereit für Foto-Serie')
                Positioned(
                  top: widget.cameras.isNotEmpty
                      ? 120
                      : 50, // Adjust based on dropdown and debug info presence
                  left: 50,
                  right: 220,
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
    return GestureDetector(
      onTap: _takePicture,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isLoading || _isCountdownActive ? Colors.grey : Colors.white,
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
                padding: EdgeInsets.all(25.0),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : _isCountdownActive
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer, size: 20, color: Colors.black),
                  Text(
                    '$_countdownSeconds',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 30, color: Colors.black),
                  Text(
                    'Start',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
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
                                onPressed: _reset,
                                icon: const Icon(
                                  Icons.arrow_back,
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
                                child: GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                      ),
                                  itemCount: 4,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _capturedImages[index] != null
                                              ? Colors.green
                                              : Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: _capturedImages[index] != null
                                            ? Image.file(
                                                _capturedImages[index]!,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey[800],
                                                child: Center(
                                                  child: Text(
                                                    '${index + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 24,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    );
                                  },
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
                          if (_backgroundRemovedImages.any(
                            (img) => img != null,
                          )) ...[
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
                          if (_processedImages.any((img) => img != null)) ...[
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
                                        // Add Save Button
                                        ElevatedButton.icon(
                                          onPressed: _isSaving
                                              ? null
                                              : _saveAllProcessedImages,
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
                                          child: GridView.builder(
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  crossAxisSpacing: 4,
                                                  mainAxisSpacing: 4,
                                                ),
                                            itemCount: 4,
                                            itemBuilder: (context, index) {
                                              return Container(
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color:
                                                        _processedImages[index] !=
                                                            null
                                                        ? Colors.green
                                                        : Colors.white
                                                              .withOpacity(0.3),
                                                    width: 1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  child:
                                                      _processedImages[index] !=
                                                          null
                                                      ? Image.memory(
                                                          _processedImages[index]!,
                                                          fit: BoxFit.cover,
                                                        )
                                                      : Container(
                                                          color:
                                                              Colors.grey[800],
                                                          child: Center(
                                                            child: Text(
                                                              '${index + 1}',
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .white54,
                                                                    fontSize:
                                                                        16,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                              );
                                            },
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

  // ...rest of existing code...
}
