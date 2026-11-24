import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../logic/app_state.dart';

class UsersModule extends StatefulWidget {
  const UsersModule({super.key});

  @override
  State<UsersModule> createState() => _UsersModuleState();
}

class _UsersModuleState extends State<UsersModule> {
  String _searchQuery = '';

  List<UserAccount> get _filteredUsers {
    if (_searchQuery.isEmpty) return AppState.instance.users;
    return AppState.instance.users.where((u) {
      return u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.role.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Add (user == null) or edit an account. A password typed here is
  // temporary: the person sets their own at their next login.
  void _showUserDialog({UserAccount? user}) {
    final isEdit = user != null;
    final usernameCtrl = TextEditingController(text: user?.username ?? '');
    final passwordCtrl = TextEditingController();
    String selectedRole = user?.role ?? 'User';
    String? error;
    var saving = false;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setStateDialog) => AlertDialog(
                  scrollable: true,
                  backgroundColor: AppTheme.backgroundLight,
                  title: Text(
                    isEdit ? 'Edit User' : 'New User',
                    style: const TextStyle(color: AppTheme.accentWhite),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: usernameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          labelStyle: TextStyle(color: Colors.grey),
                        ),
                      ),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText:
                              isEdit
                                  ? 'New temporary password (optional)'
                                  : 'Temporary password',
                          labelStyle: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'They will be asked to choose their own password at '
                        'their next login.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        dropdownColor: AppTheme.backgroundLight,
                        style: const TextStyle(color: Colors.white),
                        items:
                            ['Admin', 'User']
                                .map(
                                  (value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        // The main admin always stays an admin.
                        onChanged:
                            user?.isRootAdmin == true
                                ? null
                                : (newValue) {
                                  if (newValue != null) {
                                    setStateDialog(
                                      () => selectedRole = newValue,
                                    );
                                  }
                                },
                        decoration: const InputDecoration(
                          labelText: 'Access Role',
                          labelStyle: TextStyle(color: Colors.grey),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    if (isEdit && !user.isRootAdmin)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDelete(user);
                        },
                        child: const Text(
                          'Delete User',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentWhite,
                        foregroundColor: Colors.black,
                      ),
                      onPressed:
                          saving
                              ? null
                              : () async {
                                setStateDialog(() => saving = true);
                                final problem =
                                    isEdit
                                        ? await AppState.instance.updateUser(
                                          user,
                                          username: usernameCtrl.text,
                                          role: selectedRole,
                                          newPassword: passwordCtrl.text,
                                        )
                                        : await AppState.instance.addUser(
                                          username: usernameCtrl.text,
                                          password: passwordCtrl.text,
                                          role: selectedRole,
                                        );
                                if (problem != null) {
                                  setStateDialog(() {
                                    saving = false;
                                    error = problem;
                                  });
                                  return;
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) setState(() {});
                              },
                      child: Text(isEdit ? 'Save' : 'Create User'),
                    ),
                  ],
                ),
          ),
    ).whenComplete(() {
      usernameCtrl.dispose();
      passwordCtrl.dispose();
    });
  }

  Future<void> _confirmDelete(UserAccount user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundLight,
            title: const Text(
              'Delete user?',
              style: TextStyle(color: AppTheme.accentWhite),
            ),
            content: Text(
              '${user.username} will no longer be able to sign in. '
              'This action cannot be undone.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    final problem = await AppState.instance.deleteUser(user);
    if (problem != null) {
      _toast(problem, error: true);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: AppTheme.backgroundLight,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundLight,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmall = constraints.maxWidth < 600;
                            return isSmall
                                ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'User Management',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.accentWhite,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                        ),
                                        onPressed: () => _showUserDialog(),
                                        icon: const Icon(
                                          Icons.person_add_outlined,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Provision User',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'User Management',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.accentWhite,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: () => _showUserDialog(),
                                      icon: const Icon(
                                        Icons.person_add_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Provision User',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TextField(
                            onChanged:
                                (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              icon: Icon(Icons.search, color: Colors.white54),
                              hintText: 'Search by username or role...',
                              hintStyle: TextStyle(color: Colors.white30),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _filteredUsers.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final isAdmin = user.role == 'Admin';

                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  isAdmin
                                      ? Colors.purpleAccent.withValues(
                                        alpha: 0.2,
                                      )
                                      : Colors.blueAccent.withValues(
                                        alpha: 0.2,
                                      ),
                              child: Icon(
                                isAdmin
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                                color:
                                    isAdmin
                                        ? Colors.purpleAccent
                                        : Colors.blueAccent,
                              ),
                            ),
                            title: Text(
                              user.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Icon(
                                  Icons.badge_outlined,
                                  size: 14,
                                  color: Colors.white54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  user.role,
                                  style: TextStyle(
                                    color:
                                        isAdmin
                                            ? Colors.purpleAccent
                                            : Colors.blueAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (user.mustChangePassword)
                                  const Text(
                                    '· New password needed',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: TextButton.icon(
                              onPressed: () => _showUserDialog(user: user),
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Colors.white70,
                              ),
                              label: const Text(
                                'Edit',
                                style: TextStyle(color: Colors.white70),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.05,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
