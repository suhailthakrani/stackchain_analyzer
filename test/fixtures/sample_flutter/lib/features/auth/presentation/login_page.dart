// Layer violation: presentation imports data directly.
import '../data/auth_repository.dart';

/// Fixture presentation widget (text-scanned; not executed).
class LoginPage {
  final _repo = AuthRepository();

  // Hardcoded Google-style API key — security analyzer target.
  static const apiKey = 'AIzaSyDummyKeyForTestingPurposesOnly12345';

  Object build() {
    // TODO: wire up real auth flow
    setState(() {});
    setState(() {});
    setState(() {});
    setState(() {});
    setState(() {});
    // ignore: avoid_print
    print('password debug dump');
    _repo.login('a', 'b');

    // Unoptimized ListView(children:) pattern.
    return ListView(
      children: const [
        'a',
        'b',
        'c',
      ],
    );
  }

  void setState(void Function() fn) => fn();
}

class ListView {
  const ListView({this.children});
  final List<Object>? children;
}
