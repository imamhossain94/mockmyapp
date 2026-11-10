import 'video_encoder.dart';

/// Off the web there is no browser encoder to ask.
Future<VideoSink?> webVideoSink() async => null;
