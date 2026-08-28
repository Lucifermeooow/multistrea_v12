import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? _camera;

  bool _initialized = false;
  bool _streaming = false;
  bool _loading = true;
  bool _muted = false;

  String _status = 'جاري تجهيز الكاميرا...';

  final TextEditingController _rtmpController =
      TextEditingController(
    text:
        'rtmp://userId-3125-1b12964663-stream-proxy.cloud.red5.net:1935/live/multistream-test',
  );

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await Permission.camera.request();
      await Permission.microphone.request();

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _status = 'لم يتم العثور على كاميرا';
          _loading = false;
        });
        return;
      }

      final camera = cameras.first;

      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize(camera);

      await controller.setAudioSettings(128 * 1024);
      await controller.setVideoSettings(
        bitrate: 1500 * 1024,
      );
      await controller.setFrameRate(30);

      if (Platform.isAndroid) {
        await controller.setForceBt709Color(true);
        await controller.setRtmpShouldSendPings(true);
      }

      _camera = controller;

      if (!mounted) return;

      setState(() {
        _initialized = true;
        _loading = false;
        _status = 'جاهز للبث';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _status = 'خطأ في تشغيل الكاميرا';
      });

      _showMessage('خطأ: $e');
    }
  }

  Future<void> _startStreaming() async {
    if (_camera == null || !_initialized) {
      _showMessage('الكاميرا غير جاهزة');
      return;
    }

    if (_streaming) {
      _showMessage('البث يعمل بالفعل');
      return;
    }

    final url = _rtmpController.text.trim();

    if (url.isEmpty) {
      _showMessage('اكتب رابط RTMP');
      return;
    }

    try {
      setState(() {
        _status = 'جاري بدء البث...';
      });

      if (Platform.isAndroid) {
        await _camera!.setForceBt709Color(true);
        await _camera!.setRtmpShouldSendPings(true);
      }

      await _camera!.startVideoStreaming(
        url,
        protocol: StreamingProtocol.rtmp,
      );

      await WakelockPlus.enable();

      if (!mounted) return;

      setState(() {
        _streaming = true;
        _status = 'LIVE — البث يعمل';
      });

      _showMessage('تم بدء البث');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _streaming = false;
        _status = 'فشل بدء البث';
      });

      _showMessage('فشل البث: $e');
    }
  }

  Future<void> _stopStreaming() async {
    if (_camera == null) {
      return;
    }

    try {
      /*
       * مهم:
       * نستخدم stopVideoStreaming بدلاً من stopStreaming
       * لأن هذا هو الأسلوب المتوافق مع API المستخدم في
       * أمثلة rtmp_streaming الحالية.
       */
      await _camera!.stopVideoStreaming();

      await WakelockPlus.disable();

      if (!mounted) return;

      setState(() {
        _streaming = false;
        _status = 'تم إيقاف البث';
      });

      _showMessage('تم إيقاف البث');
    } catch (e) {
      await WakelockPlus.disable();

      if (!mounted) return;

      setState(() {
        _streaming = false;
        _status = 'تم إيقاف البث';
      });

      _showMessage('تم إيقاف البث');
    }
  }

  Future<void> _switchCamera() async {
    if (_camera == null || !_initialized) {
      return;
    }

    try {
      await _camera!.switchCamera();

      if (!mounted) return;

      _showMessage('تم تغيير الكاميرا');
    } catch (e) {
      _showMessage('تعذر تغيير الكاميرا: $e');
    }
  }

  Future<void> _toggleMute() async {
    if (_camera == null || !_initialized) {
      return;
    }

    try {
      _muted = !_muted;

      await _camera!.setHasAudio(!_muted);

      if (!mounted) return;

      setState(() {});

      _showMessage(
        _muted ? 'تم كتم الميكروفون' : 'تم تشغيل الميكروفون',
      );
    } catch (e) {
      _showMessage('تعذر تغيير حالة الميكروفون: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _rtmpController.dispose();
    _camera?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10121A),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MultiStream Real',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPreview(),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF11141D),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Server RTMP Ingest URL',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextField(
                      controller: _rtmpController,
                      enabled: !_streaming,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.link,
                          color: Colors.white54,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF080A10),
                        hintText: 'rtmp://server/live/key',
                        hintStyle: const TextStyle(
                          color: Colors.white30,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _streaming
                      ? const Color(0xFF321016)
                      : const Color(0xFF11141D),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _streaming
                            ? Colors.red
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: _streaming
                              ? Colors.redAccent
                              : Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _initialized ? _switchCamera : null,
                      icon: const Icon(Icons.flip_camera_android),
                      label: const Text('تغيير الكاميرا'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _initialized ? _toggleMute : null,
                      icon: Icon(
                        _muted
                            ? Icons.mic_off
                            : Icons.mic,
                      ),
                      label: Text(
                        _muted ? 'تشغيل الصوت' : 'كتم الصوت',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : (_streaming
                          ? _stopStreaming
                          : _startStreaming),
                  icon: Icon(
                    _streaming
                        ? Icons.stop
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    _streaming
                        ? 'إيقاف البث'
                        : 'بدء البث',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _streaming
                        ? Colors.redAccent
                        : theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'YouTube / Facebook / TikTok',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'النسخة الحالية ترسل الفيديو إلى عنوان RTMP الموجود بالأعلى. '
                'الـOAuth وربط المنصات يحتاج Backend مستقل.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      height: 360,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : (!_initialized || _camera == null)
              ? Center(
                  child: Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white54,
                    ),
                  ),
                )
              : CameraPreview(
                  _camera!,
                ),
    );
  }
}
