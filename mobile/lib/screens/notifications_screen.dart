import 'package:flutter/material.dart';

import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiService();
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = data['notifications'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _api.markNotificationRead(id);
      if (!mounted) return;
      setState(() {
        for (final n in _notifications) {
          if (n['id'] == id) n['lu'] = true;
        }
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await _api.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        for (final n in _notifications) {
          n['lu'] = true;
        }
      });
    } catch (_) {}
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'SOS':
        return Icons.sos;
      case 'TRAJET':
        return Icons.directions_car;
      case 'DOSSIER':
        return Icons.folder_open;
      case 'IDENTITE':
        return Icons.verified_user;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'SOS':
        return Colors.red;
      case 'TRAJET':
        return Colors.green;
      case 'DOSSIER':
        return Colors.orange;
      case 'IDENTITE':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  bool get _hasUnread => _notifications.any((n) => n['lu'] == false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Tout lire'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _notifications.isEmpty
                  ? const Center(child: Text('Aucune notification'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          final read = n['lu'] == true;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            color: read
                                ? null
                                : Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.35),
                            child: ListTile(
                              leading: Icon(
                                _iconFor(n['type'] ?? ''),
                                color: _colorFor(n['type'] ?? ''),
                              ),
                              title: Text(
                                n['titre'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(n['message'] ?? ''),
                              trailing: read
                                  ? null
                                  : const Icon(
                                      Icons.mark_email_read_outlined,
                                      size: 20,
                                    ),
                              onTap: () => _markRead(n['id']),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}