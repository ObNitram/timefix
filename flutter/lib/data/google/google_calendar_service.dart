import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

/// Client ids are injected at build time:
/// `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...`
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

class GoogleAuthRequiredException implements Exception {
  @override
  String toString() => 'Google authorization required';
}

/// Abstraction over the Google Calendar API so the sync logic can be tested.
abstract class GoogleCalendarGateway {
  /// Interactive sign-in. Returns the account e-mail.
  Future<String> signIn();
  Future<void> signOut();

  /// E-mail of the account currently signed in, if any (non-interactive).
  Future<String?> currentAccount();

  Future<List<gcal.CalendarListEntry>> listCalendars({bool interactive = false});
  Future<List<gcal.Event>> listEvents(
      String calendarId, DateTime timeMin, DateTime timeMax,
      {bool interactive = false});
  Future<gcal.Event> insertEvent(String calendarId, gcal.Event event);
  Future<gcal.Event> patchEvent(String calendarId, String eventId, gcal.Event event);
  Future<void> deleteEvent(String calendarId, String eventId);
}

/// Implementation based on `google_sign_in` 7 + `googleapis`.
///
/// Note: google_sign_in only keeps one signed-in account on the device, so a
/// single Google account is supported at a time.
class GoogleCalendarService implements GoogleCalendarGateway {
  static const scopes = [gcal.CalendarApi.calendarScope];

  bool _initialized = false;
  GoogleSignInAccount? _account;
  gcal.CalendarApi? _api;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: _iosClientId.isEmpty ? null : _iosClientId,
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
  }

  @override
  Future<String> signIn() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    _account = account;
    final authz = await account.authorizationClient.authorizeScopes(scopes);
    _api = gcal.CalendarApi(authz.authClient(scopes: scopes));
    return account.email;
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    _api = null;
    _account = null;
    await GoogleSignIn.instance.disconnect();
  }

  @override
  Future<String?> currentAccount() async {
    await _ensureInitialized();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    return _account?.email;
  }

  Future<gcal.CalendarApi> _client({required bool interactive}) async {
    if (_api != null) return _api!;
    await _ensureInitialized();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    final account = _account;
    if (account == null) {
      if (!interactive) throw GoogleAuthRequiredException();
      await signIn();
      return _api!;
    }
    var authz = await account.authorizationClient.authorizationForScopes(scopes);
    if (authz == null) {
      if (!interactive) throw GoogleAuthRequiredException();
      authz = await account.authorizationClient.authorizeScopes(scopes);
    }
    return _api = gcal.CalendarApi(authz.authClient(scopes: scopes));
  }

  /// Runs [call]; on an expired token, drops the cached client and retries once.
  Future<T> _withRetry<T>(
      bool interactive, Future<T> Function(gcal.CalendarApi api) call) async {
    final api = await _client(interactive: interactive);
    try {
      return await call(api);
    } on gcal.DetailedApiRequestError catch (e) {
      if (e.status != 401) rethrow;
      _api = null;
      return call(await _client(interactive: interactive));
    }
  }

  @override
  Future<List<gcal.CalendarListEntry>> listCalendars({bool interactive = false}) =>
      _withRetry(interactive, (api) async {
        final result = <gcal.CalendarListEntry>[];
        String? token;
        do {
          final page = await api.calendarList.list(pageToken: token);
          result.addAll(page.items ?? const []);
          token = page.nextPageToken;
        } while (token != null);
        return result;
      });

  @override
  Future<List<gcal.Event>> listEvents(
          String calendarId, DateTime timeMin, DateTime timeMax,
          {bool interactive = false}) =>
      _withRetry(interactive, (api) async {
        final result = <gcal.Event>[];
        String? token;
        do {
          final page = await api.events.list(
            calendarId,
            singleEvents: true,
            timeMin: timeMin.toUtc(),
            timeMax: timeMax.toUtc(),
            maxResults: 2500,
            pageToken: token,
          );
          result.addAll(page.items ?? const []);
          token = page.nextPageToken;
        } while (token != null);
        return result;
      });

  @override
  Future<gcal.Event> insertEvent(String calendarId, gcal.Event event) =>
      _withRetry(true, (api) => api.events.insert(event, calendarId));

  @override
  Future<gcal.Event> patchEvent(
          String calendarId, String eventId, gcal.Event event) =>
      _withRetry(true, (api) => api.events.patch(event, calendarId, eventId));

  @override
  Future<void> deleteEvent(String calendarId, String eventId) =>
      _withRetry(true, (api) => api.events.delete(calendarId, eventId));
}
