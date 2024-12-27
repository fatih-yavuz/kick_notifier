import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/kick_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettingsIOS = DarwinInitializationSettings();
  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await notifications.initialize(initializationSettings);

  runApp(MyApp(notifications: notifications));
}

class MyApp extends StatelessWidget {
  final FlutterLocalNotificationsPlugin notifications;

  const MyApp({super.key, required this.notifications});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kick Notifier',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: HomeScreen(notifications: notifications),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final FlutterLocalNotificationsPlugin notifications;

  const HomeScreen({super.key, required this.notifications});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController(text: 'TechPong');
  final _messageController = TextEditingController();
  KickService? _kickService;
  bool _isMonitoring = false;
  final List<Map<String, String>> _messages = [];
  final List<String> _debugLogs = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _messageController.dispose();
    _tabController.dispose();
    _kickService?.stop();
    super.dispose();
  }

  void _addMessage(String username, String content) {
    setState(() {
      _messages.insert(0, {'username': username, 'content': content});
    });
  }

  void _addDebugLog(String log) {
    setState(() {
      _debugLogs.insert(0, "${DateTime.now().toString().split('.')[0]} - $log");
    });
  }

  void _toggleMonitoring() async {
    if (_isMonitoring) {
      _kickService?.stop();
      setState(() {
        _isMonitoring = false;
        _messages.clear();
        _debugLogs.clear();
      });
    } else {
      if (_usernameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a username')),
        );
        return;
      }

      _addDebugLog("Starting monitoring for ${_usernameController.text}");
      final service = KickService(
        _usernameController.text,
        widget.notifications,
        onMessage: _addMessage,
        onDebugLog: _addDebugLog,
      );

      setState(() {
        _kickService = service;
        _isMonitoring = true;
      });

      await service.start(context);
    }
  }

  void _sendMessage() {
    if (_messageController.text.isNotEmpty) {
      _addMessage("Me", _messageController.text);
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kick Notifier'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Enter Kick username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _toggleMonitoring,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMonitoring ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child:
                  Text(_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
            ),
            if (_isMonitoring) ...[
              const SizedBox(height: 20),
              Text(
                'Monitoring ${_usernameController.text}\'s chat',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Chat'),
                Tab(text: 'Debug Logs'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Chat Tab
                  Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(message['username']!),
                                subtitle: Text(message['content']!),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: const InputDecoration(
                                  hintText: 'Type a message...',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: _sendMessage,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Debug Logs Tab
                  ListView.builder(
                    reverse: true,
                    itemCount: _debugLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          _debugLogs[index],
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
