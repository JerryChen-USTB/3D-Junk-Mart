import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/session/app_session.dart';
import '../core/session/session_store.dart';
import '../features/auth/auth_pages.dart';
import '../features/shell/app_shell.dart';
import '../theme/app_theme.dart';

enum _AuthViewMode { login, register }

class JunkMartApp extends StatefulWidget {
  const JunkMartApp({super.key, this.apiClient, this.sessionStore});

  final ApiClient? apiClient;
  final SessionStore? sessionStore;

  @override
  State<JunkMartApp> createState() => _JunkMartAppState();
}

class _JunkMartAppState extends State<JunkMartApp> {
  late final ApiClient _apiClient;
  late final SessionStore _sessionStore;

  AppSession? _session;
  bool _bootstrapping = true;
  _AuthViewMode _authViewMode = _AuthViewMode.login;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _sessionStore = widget.sessionStore ?? SessionStore();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final storedSession = await _sessionStore.read();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = storedSession;
      _bootstrapping = false;
    });
  }

  Future<void> _persistSession(AppSession session) async {
    await _sessionStore.write(session);
    if (!mounted) {
      return;
    }

    setState(() {
      _session = session;
      _authViewMode = _AuthViewMode.login;
      _errorMessage = null;
    });
  }

  Future<void> _signIn({
    required String identifier,
    required String password,
    required bool rememberDevice,
  }) async {
    final response = await _apiClient.postJson(
      '/auth/login',
      body: <String, dynamic>{
        'identifier': identifier,
        'password': password,
        'remember_device': rememberDevice,
      },
    );
    await _persistSession(AppSession.fromApiData(response.data));
  }

  Future<void> _register({
    required String displayName,
    required String identifier,
    required String password,
    required bool acceptedTerms,
  }) async {
    final response = await _apiClient.postJson(
      '/auth/register',
      body: <String, dynamic>{
        'display_name': displayName,
        'identifier': identifier,
        'password': password,
        'accepted_terms': acceptedTerms,
        'consent_version': 'v1',
      },
    );
    await _persistSession(AppSession.fromApiData(response.data));
  }

  Future<void> _continueAsGuest() async {
    final response = await _apiClient.getJson('/auth/session');
    await _persistSession(AppSession.fromApiData(response.data));
  }

  Future<void> _signOut() async {
    final token = _session?.accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _apiClient.postJson('/auth/logout', bearerToken: token);
      } catch (_) {
        // The client should still clear local state even if the backend is
        // already expired or unreachable.
      }
    }

    await _sessionStore.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = null;
      _authViewMode = _AuthViewMode.login;
      _errorMessage = null;
    });
  }

  void _showLogin() {
    setState(() {
      _authViewMode = _AuthViewMode.login;
      _errorMessage = null;
    });
  }

  void _showRegister() {
    setState(() {
      _authViewMode = _AuthViewMode.register;
      _errorMessage = null;
    });
  }

  Future<void> _reportAuthError(Object error) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Junk Mart',
      theme: buildAppTheme(),
      home: _bootstrapping
          ? const _BootstrapScreen()
          : _session != null
          ? AppShell(
              onSignOut: _signOut,
              apiClient: _apiClient,
              session: _session!,
            )
          : _authViewMode == _AuthViewMode.login
          ? AuthLoginPage(
              onSubmit:
                  ({
                    required String identifier,
                    required String password,
                    required bool rememberDevice,
                  }) async {
                    try {
                      await _signIn(
                        identifier: identifier,
                        password: password,
                        rememberDevice: rememberDevice,
                      );
                    } catch (error) {
                      await _reportAuthError(error);
                    }
                  },
              onSwitchToRegister: _showRegister,
              onContinueAsGuest: () async {
                try {
                  await _continueAsGuest();
                } catch (error) {
                  await _reportAuthError(error);
                }
              },
              errorMessage: _errorMessage,
            )
          : AuthRegisterPage(
              onSubmit:
                  ({
                    required String displayName,
                    required String identifier,
                    required String password,
                    required bool acceptedTerms,
                  }) async {
                    try {
                      await _register(
                        displayName: displayName,
                        identifier: identifier,
                        password: password,
                        acceptedTerms: acceptedTerms,
                      );
                    } catch (error) {
                      await _reportAuthError(error);
                    }
                  },
              onSwitchToLogin: _showLogin,
              errorMessage: _errorMessage,
            ),
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
