import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'auth_service.dart';
import 'sync_service.dart';

class ChatService {
  final Ref _ref;
  final _uuid = const Uuid();

  ChatService(this._ref);

  Box get _box => Hive.box(SyncService.messagesBoxName);

  List<Message> getMessages() {
    final messages = <Message>[];
    for (var key in _box.keys) {
      final val = _box.get(key);
      if (val != null) {
        messages.add(Message.fromJson(Map<String, dynamic>.from(val as Map)));
      }
    }
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Stream<List<Message>> watchMessages() {
    return _box.watch().map((_) => getMessages());
  }

  Future<void> sendMessage(String text) async {
    final currentUser = _ref.read(currentUserProvider);
    if (currentUser == null) return;

    final receiverId = currentUser.role == UserRole.member
        ? (currentUser.assignedTrainerId ?? 'aarav_trainer')
        : 'dk_member'; // Simplification: Trainer chats with member, Member with assigned Trainer

    final message = Message(
      id: _uuid.v4(),
      chatId: 'default_chat',
      senderId: currentUser.id,
      receiverId: receiverId,
      text: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );

    // Write to sync service
    await _ref.read(syncServiceProvider).sendChatMessage(message);
    AppLogger.chat('Message sent: "$text"');
  }

  Future<void> sendSystemMessage(String text) async {
    final message = Message(
      id: 'sys_${_uuid.v4()}',
      chatId: 'default_chat',
      senderId: 'system',
      receiverId: 'all',
      text: text,
      createdAt: DateTime.now(),
      status: MessageStatus.read,
    );

    await _ref.read(syncServiceProvider).sendChatMessage(message);
  }

  Future<void> markMessageAsRead(String messageId) async {
    await _ref.read(syncServiceProvider).updateMessageStatus(messageId, MessageStatus.read);
  }

  Future<void> setTypingStatus(bool isTyping) async {
    final currentUser = _ref.read(currentUserProvider);
    if (currentUser != null) {
      await _ref.read(syncServiceProvider).setTypingStatus(currentUser.id, isTyping);
    }
  }
}

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref);
});

// A stream provider of messages sorted chronologically
final messagesStreamProvider = StreamProvider<List<Message>>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  // Emit current state immediately, then stream changes
  return chatService.watchMessages();
});

// Current active conversation message list
final conversationMessagesProvider = Provider<List<Message>>((ref) {
  final asyncMsgs = ref.watch(messagesStreamProvider);
  return asyncMsgs.maybeWhen(
    data: (list) => list,
    orElse: () => ref.read(chatServiceProvider).getMessages(),
  );
});

// Counter of unread messages for the current user
final unreadCountProvider = Provider<int>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return 0;
  
  final messages = ref.watch(conversationMessagesProvider);
  return messages.where((m) => 
    m.senderId != currentUser.id && 
    m.senderId != 'system' &&
    m.status != MessageStatus.read
  ).length;
});
