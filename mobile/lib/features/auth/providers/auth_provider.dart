import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/user_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final bool isInitialized;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.isInitialized = false,
    this.error,
  });

  bool get isLoggedIn => user != null;
  bool get needsInterests => isLoggedIn && user!.interests.isEmpty;

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    bool? isInitialized,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) =>
      AuthState(
        user: clearUser ? null : user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        isInitialized: isInitialized ?? this.isInitialized,
        error: clearError ? null : error ?? this.error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final token = await StorageService.getToken().timeout(const Duration(seconds: 3));
      if (token != null) {
        _api.setAuthToken(token);
        try {
          final res = await _api.get('/auth/me');
          state = state.copyWith(user: UserModel.fromJson(res.data), isInitialized: true);
          return;
        } catch (_) {
          await StorageService.deleteToken();
        }
      }
    } catch (_) {
      // storage timed out or failed — proceed as logged out
    }
    state = state.copyWith(isInitialized: true);
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _saveSession(res.data);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Invalid email or password');
    }
  }

  Future<void> register(String email, String password, String name) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
        'interests': [],
      });
      await _saveSession(res.data);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Registration failed. Try a different email.');
    }
  }

  Future<void> updateInterests(List<String> interests) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.patch('/auth/interests', data: {'interests': interests});
      state = state.copyWith(
        isLoading: false,
        user: UserModel.fromJson(res.data),
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Could not save interests');
    }
  }

  Future<void> refreshUser() async {
    try {
      final res = await _api.get('/auth/me');
      state = state.copyWith(user: UserModel.fromJson(res.data));
    } catch (_) {}
  }

  Future<void> logout() async {
    await StorageService.deleteToken();
    state = const AuthState(isInitialized: true);
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final token = data['access_token'] as String;
    await StorageService.saveToken(token);
    _api.setAuthToken(token);
    state = state.copyWith(
      isLoading: false,
      user: UserModel.fromJson(data['user']),
    );
  }
}

final apiServiceProvider = Provider<ApiService>((_) => ApiService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(apiServiceProvider)),
);
