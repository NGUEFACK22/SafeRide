import 'package:flutter/material.dart';
import '../utils/error_helper.dart';

import '../services/api_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Tableau'),
              Tab(icon: Icon(Icons.group), text: 'Utilisateurs'),
              Tab(icon: Icon(Icons.badge), text: 'Gestionnaires'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DashboardTab(),
            _UsersTab(),
            _ManagersTab(),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/admin/dashboard');
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _RetryError(message: _error!, onRetry: _load);
    }
    if (_data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = <MapEntry<String, String>>[
      MapEntry('Utilisateurs', '${_data!['users_total'] ?? 0}'),
      MapEntry('Trajets (total)', '${_data!['trips_total'] ?? 0}'),
      MapEntry('Trajets en cours', '${_data!['trips_active'] ?? 0}'),
      MapEntry('Alertes SOS', '${_data!['sos_total'] ?? 0}'),
      MapEntry('SOS ouverts', '${_data!['sos_open'] ?? 0}'),
      MapEntry('Litiges', '${_data!['disputes_total'] ?? 0}'),
      MapEntry('Objets perdus', '${_data!['lost_items_total'] ?? 0}'),
      MapEntry('Identités vérifiées', '${_data!['identities'] ?? 0}'),
      MapEntry('Gestionnaires', '${_data!['managers_total'] ?? 0}'),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final entry in stats)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insights),
                title: Text(entry.key),
                trailing: Text(
                  entry.value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _api = ApiService();
  List<dynamic> _users = [];
  String? _roleFilter;
  String? _error;
  bool _loading = true;

  static const _roles = ['passager', 'transporteur', 'gestionnaire', 'admin'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final suffix = _roleFilter == null ? '' : '?role=$_roleFilter';
      final data = await _api.get('/admin/users$suffix');
      if (!mounted) return;
      setState(() {
        _users = (data['users'] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggleSuspension(dynamic user) async {
    try {
      await _api.post('/admin/users/${user['id']}/toggle-suspension', {});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  List<String> _rolesOf(dynamic user) {
    final roles = user['roles'] as List<dynamic>? ?? [];
    return roles.map((r) => r['slug'] as String).toList();
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _CreateUserDialog(),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${created['message']}')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _RetryError(message: _error!, onRetry: _load);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Rôle : '),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _roleFilter,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous'),
                    ),
                    for (final role in _roles)
                      DropdownMenuItem<String?>(
                        value: role,
                        child: Text(role),
                      ),
                  ],
                  onChanged: (value) {
                    _roleFilter = value;
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green),
                tooltip: 'Créer un utilisateur',
                onPressed: _openCreateDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _users.isEmpty
                ? ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('Aucun utilisateur')),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final isSuspended = user['statut'] == 'SUSPENDU';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              ((user['prenom'] ?? '?') as String).isNotEmpty
                                  ? (user['prenom'] as String)[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text('${user['prenom']} ${user['nom']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user['email'] ?? ''),
                              Text(user['telephone'] ?? ''),
                              Wrap(
                                spacing: 4,
                                children: [
                                  for (final slug in _rolesOf(user))
                                    Chip(
                                      label: Text(slug),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isSuspended
                                  ? Icons.person_off
                                  : Icons.block,
                              color: isSuspended ? Colors.green : Colors.red,
                            ),
                            tooltip: isSuspended
                                ? 'Réactiver le compte'
                                : 'Suspendre le compte',
                            onPressed: () => _toggleSuspension(user),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ManagersTab extends StatefulWidget {
  const _ManagersTab();

  @override
  State<_ManagersTab> createState() => _ManagersTabState();
}

class _ManagersTabState extends State<_ManagersTab> {
  final _api = ApiService();
  List<dynamic>? _managers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/admin/managers/stats');
      if (!mounted) return;
      setState(() {
        _managers = data['managers'] as List<dynamic>? ?? [];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _RetryError(message: _error!, onRetry: _load);
    }
    if (_managers == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_managers!.isEmpty) {
      return const Center(child: Text('Aucun gestionnaire'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _managers!.length,
        itemBuilder: (context, index) {
          final m = _managers![index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['prenom']} ${m['nom']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Dossiers : ${m['total'] ?? 0}'),
                        Text('Résolus : ${m['résolus'] ?? 0}'),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${m['taux_resolution'] ?? 0}%',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Text('résolution'),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RetryError extends StatelessWidget {
  const _RetryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, textAlign: TextAlign.center),
          ),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _email = TextEditingController();
  final _telephone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'passager';
  bool _submitting = false;

  static const _roles = ['passager', 'transporteur', 'gestionnaire', 'admin'];

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _telephone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final data = await ApiService().post('/admin/users', {
        'nom': _nom.text.trim(),
        'prenom': _prenom.text.trim(),
        'email': _email.text.trim(),
        'telephone': _telephone.text.trim(),
        'password': _password.text,
        'role': _role,
      });
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un utilisateur'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nom,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Email invalide' : null,
              ),
              TextFormField(
                controller: _telephone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? '8 caractères min.' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [
                  for (final role in _roles)
                    DropdownMenuItem(value: role, child: Text(role)),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'passager'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}