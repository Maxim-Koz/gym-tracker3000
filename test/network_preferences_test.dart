import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_tracker/services/network_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkPreferences().clearLoadedState();
  });

  test('keeps mobile data preference scoped per user', () async {
    await NetworkPreferences().setMobileDataAllowed(
      false,
      userIdOverride: 'user-a',
    );
    await NetworkPreferences().setMobileDataAllowed(
      true,
      userIdOverride: 'user-b',
    );

    expect(
      await NetworkPreferences().isMobileDataAllowed(userIdOverride: 'user-a'),
      isFalse,
    );
    expect(
      await NetworkPreferences().isMobileDataAllowed(userIdOverride: 'user-b'),
      isTrue,
    );
  });

  test('defaults to enabled for a user with no stored preference', () async {
    expect(
      await NetworkPreferences().isMobileDataAllowed(
        userIdOverride: 'new-user',
      ),
      isTrue,
    );
  });

  test('defaults to disabled before login', () async {
    expect(await NetworkPreferences().isMobileDataAllowed(), isFalse);
  });
}
