import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  static const String _nameKey = 'mesh_display_name';

  String _displayName = '';
  bool _loaded = false;

  String get displayName => _displayName;
  bool get hasName => _displayName.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_nameKey)?.trim() ?? '';
    _loaded = true;
  }

  Future<void> saveName(String name) async {
    _displayName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _displayName);
  }
}
