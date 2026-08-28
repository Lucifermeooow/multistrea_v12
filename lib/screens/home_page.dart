import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _publishUrl = TextEditingController(
    text:
        'rtmp://userId-3125-1b12964663-stream-proxy.cloud.red5.net:1935/live/multistream-test',
  );

  final TextEditingController _backendUrl = TextEditingController(
    text: 'https://YOUR-OAUTH-SERVER.example.com',
  );

  CameraController? _camera;

  bool _ready = false;
  bool _live = false;
  bool _busy = false;

  String _status = 'جاهز للبث';

  final Map<String, bool> destinations = {
    'YouTube': true,
    'Facebook': true,
    'TikTok': true,
  };

  @override
  void dispose() {
    _publishUrl.dispose();
    _backendUrl.dispose();
    _camera?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _connect(String provider) async {
    final base = _backendUrl.text
        .trim()
        .replaceAll(RegExp(r'/+$'), '');

    if (base.isEmpty ||
        base.contains('YOUR-OAUTH-SERVER.example.com')) {
      _showMessage('ضع رابط OAuth Backend أولاً.');
      return;
    }

    final uri = Uri.parse('$base/auth/$provider/start');

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _showMessage('تعذر فتح صفحة تسجيل الدخول.');
      }
    } catch (e) {
      _showMessage('خطأ في فتح تسجيل الدخول: $e');
    }
  }

  Future<void> _prepare() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'جاري تشغيل الكاميرا...';
    });

    try {
      final cameraPermission =
          await Permission.camera.request();

      final microphonePermission =
          await Permission.microphone.request();

      if (!cameraPermission.isGranted ||
          !microphonePermission.isGranted) {
        throw Exception(
          'يجب السماح للكاميرا والميكروفون.',
        );
      }

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('لم يتم العثور على كاميرا.');
      }

      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize(cameras.first);

      await controller.setAudioSettings(
        128 * 1024,
      );

      await controller.setVideoSettings(
        bitrate: 2500 * 1024,
      );

      await controller.setFrameRate(30);

      if (Platform.isAndroid) {
        await controller.setForceBt709Color(true);
        await controller.setRtmpShouldSendPings(true);
      }

      if (Platform.isIOS) {
        await controller.prepareForVideoStreaming();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _camera?.dispose();

      setState(() {
        _camera = controller;
        _ready = true;
        _status = 'الكاميرا جاهزة — اضغط GO LIVE';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'خطأ: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _goLive() async {
    if (_busy || _live) return;

    final url = _publishUrl.text.trim();

    if (!url.startsWith('rtmp://') &&
        !url.startsWith('rtmps://')) {
      _showMessage('ضع RTMP URL صحيحًا.');
      return;
    }

    if (!_ready || _camera == null) {
      await _prepare();

      if (!_ready || _camera == null) {
        return;
      }
    }

    setState(() {
      _busy = true;
      _status = 'جاري بدء البث...';
    });

    try {
      await _camera!.startVideoStreaming(
        url,
        protocol: StreamingProtocol.rtmp,
      );

      await WakelockPlus.enable();

      if (!mounted) return;

      setState(() {
        _live = true;
        _status =
            '🔴 LIVE — البث متصل بالسيرفر';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _live = false;
          _status = 'فشل بدء البث: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _stop() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'جاري إيقاف البث...';
    });

    try {
      /*
       * الإصدار 2.0.1 من rtmp_streaming
       * يستخدم stopVideoStreaming().
       */
      await _camera?.stopVideoStreaming();

      await WakelockPlus.disable();

      if (!mounted) return;

      setState(() {
        _live = false;
        _status = 'تم إيقاف البث';
      });
    } catch (e) {
      await WakelockPlus.disable();

      if (mounted) {
        setState(() {
          _live = false;
          _status = 'تم إيقاف البث';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
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

  Widget _destination(String name) {
    final enabled = destinations[name] ?? false;

    IconData icon;

    if (name == 'YouTube') {
      icon = Icons.play_circle_fill;
    } else if (name == 'Facebook') {
      icon = Icons.facebook;
    } else {
      icon = Icons.live_tv;
    }

    return SwitchListTile(
      value: enabled,
      onChanged: _live
          ? null
          : (value) {
              setState(() {
                destinations[name] = value;
              });
            },
      secondary: Icon(icon),
      title: Text(name),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MultiStream Real'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 240,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(18),
            ),
            child: _ready && _camera != null
                ? CameraPreview(_camera!)
                : const Center(
                    child: Icon(
                      Icons.videocam_outlined,
                      size: 70,
                      color: Colors.white38,
                    ),
                  ),
          ),

          const SizedBox(height: 14),

          Text(
            _status,
            style: TextStyle(
              color: _live
                  ? Colors.redAccent
                  : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _publishUrl,
            enabled: !_live,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Server RTMP Ingest URL',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'البث يخرج من الهاتف إلى السيرفر في نسخة واحدة.',
            style: TextStyle(
              color: Colors.white60,
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _backendUrl,
            enabled: !_live,
            decoration: const InputDecoration(
              labelText: 'OAuth Backend URL',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'ربط الحسابات',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _live
                      ? null
                      : () => _connect('youtube'),
                  child: const Text(
                    'Connect YouTube',
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: OutlinedButton(
                  onPressed: _live
                      ? null
                      : () => _connect('facebook'),
                  child: const Text(
                    'Connect Facebook',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _live
                  ? null
                  : () => _connect('tiktok'),
              child: const Text(
                'Connect TikTok',
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'المنصات',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          _destination('YouTube'),
          _destination('Facebook'),
          _destination('TikTok'),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      (_busy || _live)
                          ? null
                          : _prepare,
                  icon: const Icon(
                    Icons.camera_alt,
                  ),
                  label: const Text(
                    'اختبار الكاميرا',
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : (_live
                          ? _stop
                          : _goLive),
                  icon: Icon(
                    _live
                        ? Icons.stop
                        : Icons.live_tv,
                  ),
                  label: Text(
                    _live
                        ? 'إيقاف'
                        : 'GO LIVE',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          const Text(
            'YouTube + Facebook + TikTok',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
