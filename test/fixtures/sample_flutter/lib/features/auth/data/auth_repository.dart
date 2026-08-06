/// Fixture data-layer repository.
class AuthRepository {
  Future<String> login(String email, String password) async {
    // Insecure HTTP — security analyzer target.
    final url = 'http://api.example.com/login';
    return url;
  }
}
