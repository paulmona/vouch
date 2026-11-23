//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class SmsApi {
  SmsApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Permit the agent to text a contact the owner picked.
  ///
  /// Signed by the **decision key** (fingerprint or Face ID), like a decision. Send the number as the contact picker gave it; the server normalises it to E.164 and refuses numbers it can't (`invalid_number`).
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AddSmsContactRequest] addSmsContactRequest (required):
  Future<Response> addSmsContactWithHttpInfo(
    AddSmsContactRequest addSmsContactRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/contacts';

    // ignore: prefer_final_locals
    Object? postBody = addSmsContactRequest;

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

  /// Permit the agent to text a contact the owner picked.
  ///
  /// Signed by the **decision key** (fingerprint or Face ID), like a decision. Send the number as the contact picker gave it; the server normalises it to E.164 and refuses numbers it can't (`invalid_number`).
  ///
  /// Parameters:
  ///
  /// * [AddSmsContactRequest] addSmsContactRequest (required):
  Future<SmsContact?> addSmsContact(
    AddSmsContactRequest addSmsContactRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await addSmsContactWithHttpInfo(
      addSmsContactRequest,
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
        'SmsContact',
      ) as SmsContact;
    }
    return null;
  }

  /// Delete every message with this number.
  ///
  /// Hard delete from Vouch only. The contact, if permitted, stays permitted.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  Future<Response> deleteSmsConversationWithHttpInfo(
    String phone, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/conversations/{phone}'.replaceAll('{phone}', phone);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Delete every message with this number.
  ///
  /// Hard delete from Vouch only. The contact, if permitted, stays permitted.
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  Future<void> deleteSmsConversation(
    String phone, {
    Future<void>? abortTrigger,
  }) async {
    final response = await deleteSmsConversationWithHttpInfo(
      phone,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Delete selected messages.
  ///
  /// Hard delete from Vouch only. Unknown ids are ignored.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DeleteSmsMessagesRequest] deleteSmsMessagesRequest (required):
  Future<Response> deleteSmsMessagesWithHttpInfo(
    DeleteSmsMessagesRequest deleteSmsMessagesRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/messages/delete';

    // ignore: prefer_final_locals
    Object? postBody = deleteSmsMessagesRequest;

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

  /// Delete selected messages.
  ///
  /// Hard delete from Vouch only. Unknown ids are ignored.
  ///
  /// Parameters:
  ///
  /// * [DeleteSmsMessagesRequest] deleteSmsMessagesRequest (required):
  Future<DeleteSmsMessages200Response?> deleteSmsMessages(
    DeleteSmsMessagesRequest deleteSmsMessagesRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await deleteSmsMessagesWithHttpInfo(
      deleteSmsMessagesRequest,
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
        'DeleteSmsMessages200Response',
      ) as DeleteSmsMessages200Response;
    }
    return null;
  }

  /// The numbers the agent may text, by name.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listSmsContactsWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/contacts';

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

  /// The numbers the agent may text, by name.
  Future<ListSmsContacts200Response?> listSmsContacts({
    Future<void>? abortTrigger,
  }) async {
    final response = await listSmsContactsWithHttpInfo(
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
        'ListSmsContacts200Response',
      ) as ListSmsContacts200Response;
    }
    return null;
  }

  /// One row per phone number, most recent activity first.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listSmsConversationsWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/conversations';

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

  /// One row per phone number, most recent activity first.
  Future<ListSmsConversations200Response?> listSmsConversations({
    Future<void>? abortTrigger,
  }) async {
    final response = await listSmsConversationsWithHttpInfo(
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
        'ListSmsConversations200Response',
      ) as ListSmsConversations200Response;
    }
    return null;
  }

  /// One conversation, newest first, paged.
  ///
  /// Without `before`, returns the newest page and marks the conversation read (its `unread_count` drops to 0). With `before`, returns the page of messages older than that message and changes nothing.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  ///
  /// * [String] before:
  ///   A message_id from the previous page's `next_before`.
  ///
  /// * [int] limit:
  Future<Response> listSmsMessagesWithHttpInfo(
    String phone, {
    String? before,
    int? limit,
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path =
        r'/v1/sms/conversations/{phone}/messages'.replaceAll('{phone}', phone);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (before != null) {
      queryParams.addAll(_queryParams('', 'before', before));
    }
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

  /// One conversation, newest first, paged.
  ///
  /// Without `before`, returns the newest page and marks the conversation read (its `unread_count` drops to 0). With `before`, returns the page of messages older than that message and changes nothing.
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  ///
  /// * [String] before:
  ///   A message_id from the previous page's `next_before`.
  ///
  /// * [int] limit:
  Future<ListSmsMessages200Response?> listSmsMessages(
    String phone, {
    String? before,
    int? limit,
    Future<void>? abortTrigger,
  }) async {
    final response = await listSmsMessagesWithHttpInfo(
      phone,
      before: before,
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
        'ListSmsMessages200Response',
      ) as ListSmsMessages200Response;
    }
    return null;
  }

  /// Stop the agent texting this number.
  ///
  /// Signed by the **decision key**. Takes effect on the agent's next send (refused as not approved). History is kept.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  Future<Response> removeSmsContactWithHttpInfo(
    String phone, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/v1/sms/contacts/{phone}'.replaceAll('{phone}', phone);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Stop the agent texting this number.
  ///
  /// Signed by the **decision key**. Takes effect on the agent's next send (refused as not approved). History is kept.
  ///
  /// Parameters:
  ///
  /// * [String] phone (required):
  ///   E.164. Send it percent-encoded (`%2B12045550150`); the server also accepts a literal `+` and never reads `+` in a path as a space.
  Future<void> removeSmsContact(
    String phone, {
    Future<void>? abortTrigger,
  }) async {
    final response = await removeSmsContactWithHttpInfo(
      phone,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }
}
