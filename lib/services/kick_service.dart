import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class KickChannelInfo {
  final int chatroomId;
  final int? livestreamId;
  final int? viewers;

  KickChannelInfo({
    required this.chatroomId,
    this.livestreamId,
    this.viewers,
  });

  factory KickChannelInfo.fromJson(Map<String, dynamic> json) {
    return KickChannelInfo(
      chatroomId: json['chatroom']['id'],
      livestreamId: json['livestream']?['id'],
      viewers: json['livestream']?['viewers'],
    );
  }
}

class KickService {
  WebSocketChannel? _channel;
  final String channelName;
  final FlutterLocalNotificationsPlugin notifications;
  final void Function(String username, String content)? onMessage;
  final void Function(String message)? onDebugLog;
  bool isConnected = false;
  int? _chatroomId;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _pongReceived = true;
  static const _reconnectDelay = Duration(seconds: 5);

  // Kick's Pusher configuration
  static const String _appKey = '32cbd69e4b950bf97679';
  static const String _cluster = 'us2';
  static const String _version = '7.6.0';

  KickService(this.channelName, this.notifications,
      {this.onMessage, this.onDebugLog});

  void _log(String message) {
    print(message);
    onDebugLog?.call(message);
  }

  Future<KickChannelInfo> _getChannelInfo() async {
    final response = await http.get(
      Uri.parse('https://kick.com/api/v1/channels/$channelName'),
      headers: {
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'accept-language': 'en',
        'sec-fetch-dest': 'document',
        'sec-fetch-mode': 'navigate',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'upgrade-insecure-requests': '1',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      _log(
          'Request URL: ${Uri.parse('https://kick.com/api/v1/channels/$channelName')}');
      _log('Request headers: ${response.request?.headers}');
      _log('Response status code: ${response.statusCode}');
      _log('Response headers: ${response.headers}');
      _log('Response body: ${response.body}');
      throw Exception('Failed to get channel info: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    return KickChannelInfo.fromJson(data);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pongReceived = true;
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_pongReceived) {
        _pongReceived = false;
        _channel?.sink.add('{"event":"pusher:ping","data":{}}');
      } else {
        _reconnect();
      }
    });
  }

  void _reconnect() {
    _log('Reconnecting...');
    stop();
    _reconnectTimer = Timer(_reconnectDelay, () => start(null));
  }

  Future<void> start(BuildContext? context) async {
    try {
      _log('Starting service for channel: $channelName');

      // First get channel info
      _log('Getting channel info...');
      final channelInfo = await _getChannelInfo();
      _chatroomId = channelInfo.chatroomId;
      _log('Got chatroom ID: $_chatroomId');

      // Connect to WebSocket with proper Pusher configuration
      _log('Connecting to WebSocket...');
      final wsUrl = 'wss://ws-$_cluster.pusher.com/app/$_appKey'
          '?protocol=7'
          '&client=js'
          '&version=$_version'
          '&flash=false';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Subscribe to channel
      _log('Subscribing to chatroom: $_chatroomId');
      _channel?.sink.add(json.encode({
        'event': 'pusher:subscribe',
        'data': {'auth': '', 'channel': 'chatrooms.$_chatroomId.v2'}
      }));

      // Listen for messages
      _channel?.stream.listen(
        (message) => _handleMessage(message),
        onDone: () {
          _log('WebSocket connection closed');
          isConnected = false;
          _reconnect();
        },
        onError: (error) {
          _log('WebSocket error: $error');
          isConnected = false;
          _reconnect();
        },
      );

      _startPingTimer();
      isConnected = true;
      _log('Service started successfully');
    } catch (e) {
      _log('Error starting service: $e');
      isConnected = false;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start monitoring: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      _reconnect();
    }
  }

  void _handleMessage(String message) {
    try {
      _log('Received WebSocket message: $message');
      final data = json.decode(message);
      _log('Decoded event type: ${data['event']}');

      if (data['event'] == 'pusher:pong') {
        _pongReceived = true;
        return;
      }

      if (data['event'] == 'App\\Events\\ChatMessageEvent') {
        _log('Found chat message event');
        final chatData = json.decode(data['data']);
        final username = chatData['sender']['username'];
        final content = chatData['content'];

        _log('Processing message from $username: $content');
        _showNotification(username, content);
        onMessage?.call(username, content);
      }
    } catch (e) {
      _log('Error handling message: $e');
    }
  }

  Future<void> _showNotification(String username, String message) async {
    _log('Showing notification for $username: $message');

    const androidDetails = AndroidNotificationDetails(
      'kick_chat',
      'Kick Chat',
      channelDescription: 'Notifications for Kick chat messages',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        username,
        message,
        details,
      );
      _log('Notification shown successfully');
    } catch (e) {
      _log('Error showing notification: $e');
    }
  }

  void stop() {
    _log('Stopping service');
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    isConnected = false;
  }
}
