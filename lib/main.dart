import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kamera Timestamp',
      theme: ThemeData(primarySwatch: Colors.purple),
      home: HomePage(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomePage({super.key, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _savedImage;
  String _gpsLat = '';
  String _gpsLng = '';
  String _manualLat = '';
  String _manualLng = '';
  bool _useManualGps = false;
  String _timeFormat = 'DD/MM/YYYY HH:mm:ss';
  String? _logoPath;
  bool _showLogo = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualLat = prefs.getString('manualLat') ?? '';
      _manualLng = prefs.getString('manualLng') ?? '';
      _useManualGps = prefs.getBool('useManualGps') ?? false;
      _timeFormat = prefs.getString('timeFormat') ?? 'DD/MM/YYYY HH:mm:ss';
      _logoPath = prefs.getString('logoPath');
      _showLogo = prefs.getBool('showLogo') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manualLat', _manualLat);
    await prefs.setString('manualLng', _manualLng);
    await prefs.setBool('useManualGps', _useManualGps);
    await prefs.setString('timeFormat', _timeFormat);
    await prefs.setString('logoPath', _logoPath ?? '');
    await prefs.setBool('showLogo', _showLogo);
  }

  String _formatTime(DateTime dt) {
    return _timeFormat
        .replaceAll('YYYY', dt.year.toString())
        .replaceAll('MM', dt.month.toString().padLeft(2, '0'))
        .replaceAll('DD', dt.day.toString().padLeft(2, '0'))
        .replaceAll('HH', dt.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', dt.minute.toString().padLeft(2, '0'))
        .replaceAll('ss', dt.second.toString().padLeft(2, '0'));
  }

  Future<void> _getGPS() async {
    if (_useManualGps && _manualLat.isNotEmpty && _manualLng.isNotEmpty) {
      setState(() {
        _gpsLat = _manualLat;
        _gpsLng = _manualLng;
      });
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aktifkan layanan lokasi dulu')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _gpsLat = position.latitude.toStringAsFixed(6);
      _gpsLng = position.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _openCamera() async {
    setState(() => _isLoading = true);
    await _getGPS();

    final now = DateTime.now();
    final timeText = _formatTime(now);
    final gpsText = '$_gpsLat, $_gpsLng';

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(
          camera: widget.cameras.first,
          timeText: timeText,
          gpsText: gpsText,
          logoPath: _showLogo ? _logoPath : null,
        ),
      ),
    );

    if (result != null && result is File) {
      setState(() {
        _savedImage = result;
      });
    }

    setState(() => _isLoading = false);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16, right: 16, top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚙️ Pengaturan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                const Text('🕐 Format Waktu:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: _timeFormat),
                  onChanged: (v) => setModalState(() => _timeFormat = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'DD/MM/YYYY HH:mm:ss',
                  ),
                ),
                const Text('Gunakan: DD=Tanggal, MM=Bulan, YYYY=Tahun, HH=Jam, mm=Menit, ss=Detik',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 16),

                SwitchListTile(
                  title: const Text('📍 Gunakan Koordinat Manual'),
                  value: _useManualGps,
                  onChanged: (v) => setModalState(() => _useManualGps = v),
                ),
                if (_useManualGps) ...[
                  TextField(
                    controller: TextEditingController(text: _manualLat),
                    onChanged: (v) => setModalState(() => _manualLat = v),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: _manualLng),
                    onChanged: (v) => setModalState(() => _manualLng = v),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 16),

                SwitchListTile(
                  title: const Text('🖼️ Tampilkan Logo'),
                  value: _showLogo,
                  onChanged: (v) => setModalState(() => _showLogo = v),
                ),
                if (_showLogo) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery);
                      if (picked != null) {
                        setModalState(() => _logoPath = picked.path);
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Pilih Logo dari Galeri'),
                  ),
                  if (_logoPath != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('✅ Logo terpilih: ${_logoPath!.split('/').last}'),
                    ),
                ],
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _saveSettings();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Pengaturan tersimpan!')),
                      );
                    },
                    child: const Text('Simpan Pengaturan'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamera dengan Timestamp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Pengaturan',
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('📅 ${_formatTime(DateTime.now())}', style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('📍 ${_gpsLat.isNotEmpty ? "$_gpsLat, $_gpsLng" : "Belum ada data GPS"}',
                    style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 20),
                  _savedImage != null
                      ? Column(
                          children: [
                            Image.file(_savedImage!, height: 300),
                            const SizedBox(height: 10),
                            const Text('✅ Foto tersimpan di Galeri'),
                          ],
                        )
                      : const Text('Belum ada foto', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: _openCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Ambil Foto'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class CameraPage extends StatefulWidget {
  final CameraDescription camera;
  final String timeText;
  final String gpsText;
  final String? logoPath;

  const CameraPage({
    super.key,
    required this.camera,
    required this.timeText,
    required this.gpsText,
    this.logoPath,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.high);
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<File> _addOverlay(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 40,
      shadows: [Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 2)],
    );
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: '${widget.timeText}\n${widget.gpsText}',
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(20, 20));

    if (widget.logoPath != null) {
      try {
        final logoFile = File(widget.logoPath!);
        final logoBytes = await logoFile.readAsBytes();
        final logoCodec = await ui.instantiateImageCodec(logoBytes);
        final logoFrame = await logoCodec.getNextFrame();
        final logoImage = logoFrame.image;

        const logoW = 150.0;
        final logoH = logoW * logoImage.height / logoImage.width;
        canvas.drawImageRect(
          logoImage,
          Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
          Rect.fromLTWH(image.width - logoW - 20, 20, logoW, logoH),
          Paint(),
        );
      } catch (e) {
        // abaikan jika gagal
      }
    }

    final newImage = await recorder.endRecording().toImage(image.width, image.height);
    final pngBytes = await newImage.toByteData(format: ui.ImageByteFormat.png);

    final dir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newFile = File(path.join(dir.path, 'photo_$timestamp.png'));
    await newFile.writeAsBytes(pngBytes!.buffer.asUint8List());

    return newFile;
  }

  Future<void> _takePicture() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      await _controller.setFlashMode(FlashMode.off);
      final image = await _controller.takePicture();

      final fileWithOverlay = await _addOverlay(File(image.path));

      final now = DateTime.now();
      final fileName = 'IMG_${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}';
