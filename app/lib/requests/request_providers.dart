import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/vouch_api_client.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import '../screens/request/request_route_screen.dart';

/// Open requests from the server, newest first. Fetched on launch, resume
/// and pull-to-refresh so a missed push never means a missed request.
final pendingRequestsProvider =
    FutureProvider.autoDispose<List<ApprovalRequest>>((ref) async {
      final api = ref.watch(transportApiProvider);
      if (api == null) return const [];
      final page = await api.requests.listPendingRequests(limit: 20);
      await ref
          .read(pairedDeviceProvider.notifier)
          .applyServer(lastContactAt: DateTime.now());
      return page?.requests ?? const [];
    });

/// One request by id: from the server when paired, else from the in-memory
/// store (debug fakes). The server copy wins when both exist, since it
/// carries the final state and `decided_by`.
final requestProvider = FutureProvider.autoDispose
    .family<ApprovalRequest?, String>((ref, id) async {
      final api = ref.watch(transportApiProvider);
      final local = ref.read(requestStoreProvider).find(id);
      if (api == null) return local;
      try {
        final r = await api.requests.getRequest(id);
        if (r != null) {
          await ref
              .read(pairedDeviceProvider.notifier)
              .applyServer(lastContactAt: DateTime.now());
          return r;
        }
      } on ApiException catch (e) {
        if (e.code == 404) return local;
        if (e.innerException == null) rethrow;
        // Unreachable: fall back to whatever we have.
      } on http.ClientException {
        // Same.
      }
      return local;
    });
