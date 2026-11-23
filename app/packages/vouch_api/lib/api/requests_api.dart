//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class RequestsApi {
  RequestsApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Approve once, always allow, or deny.
  ///
  /// Signed by the **decision key**, not the transport key. The first valid decision from any paired device wins. `always` is only valid for `sign_in` requests. The decision is bound to this request by the signed path and body, and to what the owner saw by `shown_digest`.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] requestId (required):
  ///
  /// * [DecisionRequest] decisionRequest (required):
  Future<Response> decideRequestWithHttpInfo(
    String requestId,
    DecisionRequest decisionRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/requests/{request_id}/decision'
        .replaceAll('{request_id}', requestId);

    // ignore: prefer_final_locals
    Object? postBody = decisionRequest;

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

  /// Approve once, always allow, or deny.
  ///
  /// Signed by the **decision key**, not the transport key. The first valid decision from any paired device wins. `always` is only valid for `sign_in` requests. The decision is bound to this request by the signed path and body, and to what the owner saw by `shown_digest`.
  ///
  /// Parameters:
  ///
  /// * [String] requestId (required):
  ///
  /// * [DecisionRequest] decisionRequest (required):
  Future<ApprovalRequest?> decideRequest(
    String requestId,
    DecisionRequest decisionRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await decideRequestWithHttpInfo(
      requestId,
      decisionRequest,
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
        'ApprovalRequest',
      ) as ApprovalRequest;
    }
    return null;
  }

  /// One request, by the ID from the push.
  ///
  /// The first fetch per device is recorded as that device's `fetched_at`.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] requestId (required):
  Future<Response> getRequestWithHttpInfo(
    String requestId, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path =
        r'/v1/requests/{request_id}'.replaceAll('{request_id}', requestId);

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

  /// One request, by the ID from the push.
  ///
  /// The first fetch per device is recorded as that device's `fetched_at`.
  ///
  /// Parameters:
  ///
  /// * [String] requestId (required):
  Future<ApprovalRequest?> getRequest(
    String requestId, {
    Future<void>? abortTrigger,
  }) async {
    final response = await getRequestWithHttpInfo(
      requestId,
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
        'ApprovalRequest',
      ) as ApprovalRequest;
    }
    return null;
  }

  /// Open requests, newest first.
  ///
  /// Call on app launch and resume, so a missed push never means a missed request.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<Response> listPendingRequestsWithHttpInfo({
    int? limit,
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/requests/pending';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }

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

  /// Open requests, newest first.
  ///
  /// Call on app launch and resume, so a missed push never means a missed request.
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  Future<ListPendingRequests200Response?> listPendingRequests({
    int? limit,
    Future<void>? abortTrigger,
  }) async {
    final response = await listPendingRequestsWithHttpInfo(
      limit: limit,
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
        'ListPendingRequests200Response',
      ) as ListPendingRequests200Response;
    }
    return null;
  }
}
