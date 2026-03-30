import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../config.dart';

class AuthService {
  static final _googleSignIn = GoogleSignIn.instance;
  static GoogleSignInAccount? _currentUser;
  static String? _accessToken;

  static GoogleSignInAccount? get currentUser => _currentUser;
  static bool get isSignedIn => _currentUser != null;

  /// Must be called once at app startup.
  static Future<void> initialize() async {
    await _googleSignIn.initialize();
    // Listen to auth events
    _googleSignIn.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            _currentUser = event.user;
          case GoogleSignInAuthenticationEventSignOut():
            _currentUser = null;
            _accessToken = null;
        }
      },
    );
  }

  /// Last sign-in error message (for debugging).
  static String? lastError;

  /// Full sign-in with account picker.
  /// Returns true on success. On failure, check [lastError].
  static Future<bool> signIn() async {
    lastError = null;
    try {
      _currentUser = await _googleSignIn.authenticate(
        scopeHint: AppConfig.scopes,
      );
      // Request authorization for our scopes
      if (_currentUser != null) {
        await _authorizeScopes();
      }
      return _currentUser != null;
    } on GoogleSignInException catch (e) {
      lastError = '${e.code.name}: ${e.description}';
      print('Sign-in error: $lastError');
      return false;
    } catch (e) {
      lastError = e.toString();
      print('Sign-in error: $lastError');
      return false;
    }
  }

  /// Try lightweight (silent) sign-in.
  /// Does NOT prompt for scope authorization — that happens lazily when needed.
  static Future<bool> silentSignIn() async {
    try {
      final result = _googleSignIn.attemptLightweightAuthentication();
      if (result is Future<GoogleSignInAccount?>) {
        _currentUser = await result;
      } else {
        _currentUser = result as GoogleSignInAccount?;
      }
      if (_currentUser != null) {
        // Try to get existing authorization silently (no prompt)
        final auth = await _currentUser!.authorizationClient
            .authorizationForScopes(AppConfig.scopes);
        _accessToken = auth?.accessToken;
      }
      return _currentUser != null;
    } catch (e) {
      print('Silent sign-in error: $e');
      return false;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _accessToken = null;
  }

  /// Request authorization for our scopes and cache the access token.
  static Future<void> _authorizeScopes() async {
    if (_currentUser == null) return;
    // Try existing authorization first
    var auth = await _currentUser!.authorizationClient
        .authorizationForScopes(AppConfig.scopes);
    if (auth == null) {
      // Request new authorization
      auth = await _currentUser!.authorizationClient
          .authorizeScopes(AppConfig.scopes);
    }
    _accessToken = auth.accessToken;
  }

  /// Clear cached token so the next call fetches a fresh one.
  static void invalidateToken() => _accessToken = null;

  /// Get auth headers with Bearer token.
  /// Uses cached token; call [invalidateToken] first to force refresh.
  static Future<Map<String, String>> getAuthHeaders() async {
    if (_accessToken == null) {
      final auth = await _currentUser?.authorizationClient
          .authorizationForScopes(AppConfig.scopes);
      _accessToken = auth?.accessToken;
    }
    if (_accessToken == null) {
      // Must prompt — user hasn't authorized these scopes yet
      await _authorizeScopes();
    }
    if (_accessToken == null) throw Exception('No access token');
    return {'Authorization': 'Bearer $_accessToken'};
  }

  /// Get an authenticated HTTP client for Google APIs.
  /// Retries once with a fresh token on 401.
  static Future<http.Client> getAuthClient() async {
    final headers = await getAuthHeaders();
    return _AuthenticatedClient(http.Client(), headers);
  }

  /// Get a Sheets API client.
  static Future<sheets.SheetsApi> getSheetsApi() async {
    return sheets.SheetsApi(await getAuthClient());
  }

  /// Get a Drive API client.
  static Future<drive.DriveApi> getDriveApi() async {
    return drive.DriveApi(await getAuthClient());
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  Map<String, String> _headers;

  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      // Token expired — refresh and retry once
      AuthService.invalidateToken();
      _headers = await AuthService.getAuthHeaders();
      // Clone the request for retry
      final retry = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..headers.addAll(_headers);
      if (request is http.Request) {
        retry.body = request.body;
      }
      return _inner.send(retry);
    }
    return response;
  }
}
