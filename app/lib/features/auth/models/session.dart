enum UserRole {
  admin('Admin'),
  viewer('Viewer');

  const UserRole(this.label);
  final String label;

  static UserRole? fromName(Object? name) {
    for (final r in UserRole.values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// A signed-in session: the API token plus who it belongs to.
class Session {
  const Session({
    required this.token,
    required this.email,
    required this.role,
    required this.expiresAt,
  });

  final String token;
  final String email;
  final UserRole role;
  final DateTime expiresAt;

  bool get isAdmin => role == UserRole.admin;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Parses the `POST /auth/login` response. Throws [FormatException] if malformed.
  factory Session.fromLoginJson(Map<String, dynamic> json) {
    final token = json['token'];
    final user = json['user'];
    final expires = DateTime.tryParse('${json['expiresAt']}');
    final role = user is Map ? UserRole.fromName(user['role']) : null;
    final email = user is Map ? user['email'] : null;
    if (token is! String || token.isEmpty || expires == null || role == null || email is! String) {
      throw const FormatException('Malformed login response');
    }
    return Session(token: token, email: email, role: role, expiresAt: expires);
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'email': email,
    'role': role.name,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  /// Returns null for anything unreadable (a stored session is optional).
  static Session? tryFromJson(Map<String, dynamic> json) {
    try {
      return Session.fromLoginJson({
        'token': json['token'],
        'expiresAt': json['expiresAt'],
        'user': {'email': json['email'], 'role': json['role']},
      });
    } on FormatException {
      return null;
    }
  }
}
