class AppSession {
  const AppSession({required this.user, required this.session, this.profile});

  final Map<String, dynamic> user;
  final Map<String, dynamic> session;
  final Map<String, dynamic>? profile;

  String get accessToken => session['access_token']?.toString() ?? '';
  String? get refreshToken => session['refresh_token']?.toString();
  bool get hasAccessToken => accessToken.isNotEmpty;
  String get displayName => user['display_name']?.toString() ?? '';

  factory AppSession.fromApiData(Map<String, dynamic> data) {
    return AppSession(
      user:
          (data['user'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      session:
          (data['session'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      profile: (data['profile'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'user': user,
      'session': session,
      if (profile != null) 'profile': profile,
    };
  }

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      user:
          (json['user'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      session:
          (json['session'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      profile: (json['profile'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
