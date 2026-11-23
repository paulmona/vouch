//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class DevicesApi {
  DevicesApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Answer a heartbeat push.
  ///
  /// Shows the path works (Firebase in, tunnel out) when the app answers. On Android the answer can wait until the app is next opened, so a late or missing check-in does not by itself mean the path is broken. Also call it whenever the app opens.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [CheckInRequest] checkInRequest (required):
  Future<Response> checkInWithHttpInfo(
    CheckInRequest checkInRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/devices/me/checkin';

    // ignore: prefer_final_locals
    Object? postBody = checkInRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Answer a heartbeat push.
  ///
  /// Shows the path works (Firebase in, tunnel out) when the app answers. On Android the answer can wait until the app is next opened, so a late or missing check-in does not by itself mean the path is broken. Also call it whenever the app opens.
  ///
  /// Parameters:
  ///
  /// * [CheckInRequest] checkInRequest (required):
  Future<void> checkIn(
    CheckInRequest checkInRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await checkInWithHttpInfo(
      checkInRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// This device's record and the current server policy.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getDeviceWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/devices/me';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// This device's record and the current server policy.
  Future<Device?> getDevice({
    Future<void>? abortTrigger,
  }) async {
    final response = await getDeviceWithHttpInfo(
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'Device',
      ) as Device;
    }
    return null;
  }

  /// Pair this device using a setup token from the QR code.
  ///
  /// Signed with the transport key being registered: `X-Vouch-Device` is omitted and the server verifies the signature against `transport_public_key` in the body. `decision_key_proof` proves the device holds the decision key. On Android the decision key's attestation chain must chain to a Google root, carry the challenge SHA-256(setup_token), and (when policy requires it) show the key requires user authentication for every use. The setup token is single use and valid for 10 minutes.  The pairing QR code holds the link `vouch://pair?v=1&server=<server URL>&token=<setup token>` (query values URL-encoded). `server` is the base URL for every call in this API, e.g. `https://vouch.example.com`. The same link can be typed or pasted by hand.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PairRequest] pairRequest (required):
  Future<Response> pairDeviceWithHttpInfo(
    PairRequest pairRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/devices/pair';

    // ignore: prefer_final_locals
    Object? postBody = pairRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Pair this device using a setup token from the QR code.
  ///
  /// Signed with the transport key being registered: `X-Vouch-Device` is omitted and the server verifies the signature against `transport_public_key` in the body. `decision_key_proof` proves the device holds the decision key. On Android the decision key's attestation chain must chain to a Google root, carry the challenge SHA-256(setup_token), and (when policy requires it) show the key requires user authentication for every use. The setup token is single use and valid for 10 minutes.  The pairing QR code holds the link `vouch://pair?v=1&server=<server URL>&token=<setup token>` (query values URL-encoded). `server` is the base URL for every call in this API, e.g. `https://vouch.example.com`. The same link can be typed or pasted by hand.
  ///
  /// Parameters:
  ///
  /// * [PairRequest] pairRequest (required):
  Future<PairResponse?> pairDevice(
    PairRequest pairRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await pairDeviceWithHttpInfo(
      pairRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'PairResponse',
      ) as PairResponse;
    }
    return null;
  }

  /// Replace this device's Firebase token after Firebase rotates it.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [UpdatePushTokenRequest] updatePushTokenRequest (required):
  Future<Response> updatePushTokenWithHttpInfo(
    UpdatePushTokenRequest updatePushTokenRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/devices/me/push-token';

    // ignore: prefer_final_locals
    Object? postBody = updatePushTokenRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Replace this device's Firebase token after Firebase rotates it.
  ///
  /// Parameters:
  ///
  /// * [UpdatePushTokenRequest] updatePushTokenRequest (required):
  Future<void> updatePushToken(
    UpdatePushTokenRequest updatePushTokenRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await updatePushTokenWithHttpInfo(
      updatePushTokenRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }
}
