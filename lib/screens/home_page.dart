import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _publishUrl = TextEditingController(
    text: 'rtmp://YOUR_SERVER_IP:1935/live/multistream',
  );
  CameraController? _camera;
  bool _ready=false, _live=false, _busy=false;
  String _status='جاهز للبث المتعدد';
  final _backendUrl = TextEditingController(text: 'https://YOUR-OAUTH-SERVER.example.com');

  Future<void> _connect(String provider) async {
    final base = _backendUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/auth/$provider/start');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() => _status = 'تعذر فتح صفحة تسجيل الدخول.');
    }
  }


  final Map<String,bool> destinations = {
    'YouTube': true,
    'Facebook': true,
    'TikTok / Custom RTMP': true,
  };

  @override void dispose(){
    _publishUrl.dispose();
    _backendUrl.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if(_busy)return;
    setState(()=>_busy=true);
    try{
      final c=await Permission.camera.request();
      final m=await Permission.microphone.request();
      if(!c.isGranted || !m.isGranted) throw Exception('اسمح للكاميرا والميكروفون.');
      final cams=await availableCameras();
      if(cams.isEmpty) throw Exception('لا توجد كاميرا.');
      final controller=CameraController(ResolutionPreset.high, enableAudio:true);
      await controller.initialize(cams.first);
      await controller.setAudioSettings(128*1024);
      await controller.setVideoSettings(bitrate:2500*1024);
      await controller.setFrameRate(30);
      if(Platform.isAndroid){
        await controller.setForceBt709Color(true);
        await controller.setRtmpShouldSendPings(true);
      }
      if(Platform.isIOS) await controller.prepareForVideoStreaming();
      if(!mounted)return;
      setState((){_camera?.dispose();_camera=controller;_ready=true;_status='الكاميرا جاهزة — اضغط GO LIVE';});
    }catch(e){if(mounted)setState(()=>_status='خطأ: $e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _goLive() async {
    if(_busy||_live)return;
    final url=_publishUrl.text.trim();
    if(!url.startsWith('rtmp://') && !url.startsWith('rtmps://')){
      setState(()=>_status='ضع RTMP URL صحيحًا.'); return;
    }
    if(!_ready || _camera==null){await _prepare(); if(!_ready||_camera==null)return;}
    setState((){_busy=true;_status='جاري بدء البث المتعدد...';});
    try{
      await _camera!.startVideoStreaming(url, protocol: StreamingProtocol.rtmp);
      await WakelockPlus.enable();
      if(!mounted)return;
      setState((){_live=true;_status='🔴 LIVE — السيرفر يوزع البث على الوجهات المختارة';});
    }catch(e){if(mounted)setState(()=>_status='فشل بدء البث: $e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _stop() async {
    if(_busy)return;
    setState((){_busy=true;_status='جاري إيقاف البث...';});
    try{await _camera?.stopStreaming(); await WakelockPlus.disable();
      if(mounted)setState((){_live=false;_status='تم إيقاف البث';});
    }catch(e){if(mounted)setState(()=>_status='خطأ: $e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Widget _dest(String name){
    return SwitchListTile(
      value: destinations[name]!, onChanged: _live?null:(v)=>setState(()=>destinations[name]=v),
      title: Text(name), secondary: Icon(name.startsWith('You')?Icons.play_circle:name.startsWith('Facebook')?Icons.facebook:Icons.live_tv),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title:const Text('MultiStream Real'),centerTitle:true),
      body: ListView(padding:const EdgeInsets.all(16),children:[
        Container(height:240,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:Colors.black,borderRadius:BorderRadius.circular(18)),
          child:_ready&&_camera!=null?CameraPreview(_camera!):const Center(child:Icon(Icons.videocam_outlined,size:70,color:Colors.white38))),
        const SizedBox(height:14),
        Text(_status,style:TextStyle(color:_live?Colors.redAccent:Colors.white,fontWeight:FontWeight.w600)),
        const SizedBox(height:16),
        TextField(controller:_publishUrl,enabled:!_live,decoration:const InputDecoration(labelText:'Server RTMP Ingest URL',border:OutlineInputBorder(),prefixIcon:Icon(Icons.link))),
        const SizedBox(height:12),
        const Text('الوجهات تُدار على السيرفر. التطبيق يرفع نسخة واحدة فقط.',style:TextStyle(color:Colors.white60)),
        TextField(controller:_backendUrl, enabled:!_live, decoration:const InputDecoration(
          labelText:'OAuth Backend URL', border:OutlineInputBorder(), prefixIcon:Icon(Icons.cloud)
        )),
        const SizedBox(height:12),
        const Text('اربط حساباتك بدون إدخال Stream Key:', style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:_live?null:()=>_connect('youtube'), child:const Text('Connect YouTube'))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton(onPressed:_live?null:()=>_connect('facebook'), child:const Text('Connect Facebook'))),
        ]),
        const SizedBox(height:8),
        SizedBox(width:double.infinity, child:OutlinedButton(onPressed:_live?null:()=>_connect('tiktok'), child:const Text('Connect TikTok'))),

        const SizedBox(height:8),
        _dest('YouTube'),_dest('Facebook'),_dest('TikTok / Custom RTMP'),
        const SizedBox(height:14),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:(_busy||_live)?null:_prepare,icon:const Icon(Icons.camera_alt),label:const Text('اختبار الكاميرا'))),
          const SizedBox(width:10),
          Expanded(child:FilledButton.icon(onPressed:_busy?null:(_live?_stop:_goLive),icon:Icon(_live?Icons.stop:Icons.live_tv),label:Text(_live?'إيقاف':'GO LIVE')))
        ]),
        const SizedBox(height:18),
        const Text('تنبيه: لا تضع مفاتيح YouTube/Facebook/TikTok داخل التطبيق أو GitHub. ضعها في السيرفر المشفر/Secret Store.',style:TextStyle(color:Colors.orangeAccent))
      ])
    );
  }
}
