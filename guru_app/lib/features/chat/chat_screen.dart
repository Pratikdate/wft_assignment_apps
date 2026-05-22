import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _markAllAsRead();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _markAllAsRead() {
    final messages = ref.read(conversationMessagesProvider);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    for (var msg in messages) {
      if (msg.senderId != currentUser.id && msg.status != MessageStatus.read) {
        ref.read(chatServiceProvider).markMessageAsRead(msg.id);
      }
    }
  }

  Future<void> _sendMessage([String? text]) async {
    final body = text ?? _messageController.text.trim();
    if (body.isEmpty) return;

    if (text == null) {
      _messageController.clear();
    }
    
    _focusNode.requestFocus();
    await ref.read(chatServiceProvider).sendMessage(body);
    
    // Smooth scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(conversationMessagesProvider);
    final isPeerTyping = ref.watch(peerTypingProvider);
    final currentUser = ref.watch(currentUserProvider);
    final authService = ref.watch(authServiceProvider);
    
    final trainer = authService.getSeededTrainers().firstWhere(
      (t) => t.id == (currentUser?.assignedTrainerId ?? 'aarav_trainer'),
      orElse: () => authService.getSeededTrainers().first,
    );

    // Auto mark read whenever messages change
    ref.listen(conversationMessagesProvider, (prev, next) {
      _markAllAsRead();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    });

    final displayMessages = messages.where((m) => 
      m.senderId == currentUser?.id || 
      m.receiverId == currentUser?.id ||
      m.senderId == 'system' ||
      m.receiverId == 'all'
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(trainer.avatarUrl ?? ''),
              radius: 18,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trainer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Text('Active Now', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w500)),
              ],
            )
          ],
        ),
        actions: [
          // Small Video Camera Icon on Toolbar if upcoming call exists
          Consumer(
            builder: (context, ref, child) {
              final upcomingCall = ref.watch(upcomingCallProvider);
              if (upcomingCall == null) return const SizedBox.shrink();
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.videocam, color: AppColors.guruPrimary),
                    onPressed: () {
                      context.push('/call/${upcomingCall.id}');
                    },
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                ],
              );
            },
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message Thread
            Expanded(
              child: displayMessages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: displayMessages.length,
                      itemBuilder: (context, index) {
                        final msg = displayMessages[index];
                        return _buildChatBubble(msg, currentUser?.id);
                      },
                    ),
            ),
            
            // Peer Typing Indicator
            if (isPeerTyping) _buildTypingIndicator(trainer),

            // Quick Replies Chips
            _buildQuickReplies(),

            // Chat Input Bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'No messages yet. Start the conversation.',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _sendMessage('Hi Coach 👋'),
            child: const Text('Say hi'),
          )
        ],
      ),
    );
  }

  Widget _buildChatBubble(Message msg, String? currentUserId) {
    final isSystem = msg.senderId == 'system';
    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: AppColors.border.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(fontSize: 12.0, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final isMe = msg.senderId == currentUserId;
    final bubbleColor = isMe ? AppColors.guruPrimary : AppColors.surface;
    final textColor = isMe ? Colors.white : AppColors.textPrimary;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = isMe ? TextAlign.right : TextAlign.left;
    final timeStr = DateFormat('h:mm a').format(msg.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16.0),
                topRight: const Radius.circular(16.0),
                bottomLeft: Radius.circular(isMe ? 16.0 : 4.0),
                bottomRight: Radius.circular(isMe ? 4.0 : 16.0),
              ),
              border: isMe ? null : Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ]
            ),
            child: Text(
              msg.text,
              style: TextStyle(color: textColor, fontSize: 15.0),
              textAlign: textAlign,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(fontSize: 10.0, color: AppColors.textMuted),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                _buildStatusTick(msg.status),
              ]
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatusTick(MessageStatus status) {
    if (status == MessageStatus.sending) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.textMuted),
      );
    }
    
    final isRead = status == MessageStatus.read;
    return Icon(
      isRead ? Icons.done_all : Icons.done,
      size: 14,
      color: isRead ? AppColors.guruPrimary : AppColors.textMuted,
    );
  }

  Widget _buildTypingIndicator(User trainer) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: NetworkImage(trainer.avatarUrl ?? ''),
            radius: 12,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Interval(index * 0.2, 0.8, curve: Curves.easeInOut),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, -3.0 * (1.0 - (value - 0.5).abs() * 2)),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
      onEnd: () {
        // Simple loop trigger
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildQuickReplies() {
    final replies = ["Got it 👍", "Can we talk at 6?", "Share plan?"];
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: replies.length,
        itemBuilder: (context, index) {
          final reply = replies[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              label: Text(reply, style: const TextStyle(fontSize: 13.0, color: AppColors.guruPrimary)),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.guruPrimary, width: 0.8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
              onPressed: () => _sendMessage(reply),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              onChanged: (text) {
                // Throttle typing indicator
                ref.read(chatServiceProvider).setTypingStatus(text.isNotEmpty);
              },
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                fillColor: Colors.transparent,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: AppColors.guruPrimary),
            onPressed: () {
              ref.read(chatServiceProvider).setTypingStatus(false);
              _sendMessage();
            },
          )
        ],
      ),
    );
  }
}
