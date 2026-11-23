//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library vouch_api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/alerts_api.dart';
part 'api/devices_api.dart';
part 'api/requests_api.dart';
part 'api/server_api.dart';
part 'api/sms_api.dart';

part 'model/add_sms_contact_request.dart';
part 'model/alert.dart';
part 'model/approval_request.dart';
part 'model/approval_request_sms_contact.dart';
part 'model/check_in_request.dart';
part 'model/conflict_error.dart';
part 'model/decision_request.dart';
part 'model/delete_sms_messages200_response.dart';
part 'model/delete_sms_messages_request.dart';
part 'model/device.dart';
part 'model/error.dart';
part 'model/list_alerts200_response.dart';
part 'model/list_pending_requests200_response.dart';
part 'model/list_sms_contacts200_response.dart';
part 'model/list_sms_conversations200_response.dart';
part 'model/list_sms_messages200_response.dart';
part 'model/modules.dart';
part 'model/pair_request.dart';
part 'model/pair_response.dart';
part 'model/platform.dart';
part 'model/policy.dart';
part 'model/push_data.dart';
part 'model/sms_contact.dart';
part 'model/sms_conversation.dart';
part 'model/sms_error.dart';
part 'model/sms_message.dart';
part 'model/update_push_token_request.dart';

/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) =>
    pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
