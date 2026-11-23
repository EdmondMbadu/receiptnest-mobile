import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recieptnest_ai/src/features/ai/data/ai_repository.dart';
import 'package:recieptnest_ai/src/features/ai/models/chat_models.dart';
import 'package:recieptnest_ai/src/features/ai/presentation/insights_conversation_controller.dart';
import 'package:recieptnest_ai/src/features/auth/data/auth_repository.dart';
import 'package:recieptnest_ai/src/features/receipts/data/receipt_repository.dart';
import 'support/ai_fakes.dart';

AiChatMessage message(int index, {String role = 'user'}) => AiChatMessage(
  id: '$index',
  role: role,
  content: 'Message $index',
  timestamp: DateTime(2026),
);

void main() {
  test('new drafts remain intact when an earlier question fails', () async {
    final pending = Completer<List<AiChatMessage>>();
    final ai = InsightsTestAi()..pendingResponse = pending;
    final controller = InsightsConversationController(
      uid: 'u',
      ai: ai,
      insightData: () async => {},
    );
    addTearDown(controller.dispose);
    controller.updateDraft('First question');
    final sending = controller.send();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.pending!.content, 'First question');
    controller.updateDraft('Next question being written');
    pending.completeError(StateError('offline'));
    await sending;
    expect(controller.state.draft, 'Next question being written');
    expect(controller.state.pending, isNull);
    expect(controller.state.error, contains('couldn’t send'));
    expect(controller.state.busy, isFalse);
    expect(ai.sent, ['First question']);
  });

  test(
    'new question clears the thread and ignores an older response',
    () async {
      final pending = Completer<List<AiChatMessage>>();
      final controller = InsightsConversationController(
        uid: 'u',
        ai: InsightsTestAi()..pendingResponse = pending,
        insightData: () async => {},
      );
      addTearDown(controller.dispose);
      controller.updateDraft('Old question');
      final sending = controller.send();
      await Future<void>.delayed(Duration.zero);
      controller.startNew();
      controller.updateDraft('Fresh question');
      pending.complete([message(1)]);
      await sending;
      expect(controller.state.messages, isEmpty);
      expect(controller.state.chatId, isNull);
      expect(controller.state.draft, 'Fresh question');
      expect(controller.state.busy, isFalse);
    },
  );

  test(
    'changing accounts clears the session and ignores a late answer',
    () async {
      final account = StateProvider<String?>((ref) => 'u');
      final pending = Completer<List<AiChatMessage>>();
      final ai = InsightsTestAi()..pendingResponse = pending;
      final receipts = InsightsTestReceipts();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
          aiRepositoryProvider.overrideWithValue(ai),
          receiptRepositoryProvider.overrideWithValue(receipts),
          receiptsStreamProvider.overrideWith(
            (ref) => Stream.value(receipts.records.values.toList()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final old = container.read(insightsConversationProvider('u').notifier);
      old.updateDraft('Private question for the first account');
      final sending = old.send();
      await Future<void>.delayed(Duration.zero);
      container.read(account.notifier).state = 'v';
      expect(
        container.read(insightsConversationProvider('u')).messages,
        isEmpty,
      );
      final next = container.read(insightsConversationProvider('v'));
      pending.complete([message(1)]);
      await sending;
      expect(next.draft, isEmpty);
      expect(
        container.read(insightsConversationProvider('v')).messages,
        isEmpty,
      );
      expect(
        container.read(insightsConversationProvider('u')).messages,
        isEmpty,
      );
    },
  );

  test(
    'long conversations send the latest ten messages including the new question',
    () async {
      final functions = _Functions();
      final repository = _PersistSpy(functions);
      final original = List.generate(
        25,
        (index) => message(index, role: index.isEven ? 'user' : 'assistant'),
      );
      final result = await repository.sendMessage(
        userId: 'u',
        chatId: 'chat',
        message: 'The latest follow-up',
        currentMessages: original,
        insightData: {},
      );
      final context = functions.payload!['history'] as List;
      expect(context, hasLength(10));
      expect((context.first as Map)['content'], 'Message 16');
      expect((context.last as Map)['content'], 'The latest follow-up');
      expect(
        context.any((entry) => (entry as Map)['content'] == 'Message 0'),
        isFalse,
      );
      expect(result, hasLength(27));
      expect(repository.persisted, result);
      expect(original, hasLength(25));
    },
  );
}

class _Db extends Fake implements FirebaseFirestore {}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.owner);
  final _Functions owner;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    owner.payload = Map<String, dynamic>.from(parameters as Map);
    return _Result({'response': 'Answer based on the latest question'} as T);
  }
}

class _Functions extends Fake implements FirebaseFunctions {
  Map<String, dynamic>? payload;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable(this);
}

class _PersistSpy extends AiRepository {
  _PersistSpy(_Functions functions) : super(db: _Db(), functions: functions);
  List<AiChatMessage>? persisted;
  @override
  Future<void> persistChat(
    String userId,
    String chatId,
    List<AiChatMessage> messages,
  ) async {
    persisted = messages;
  }
}
