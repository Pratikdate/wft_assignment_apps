enum MessageStatus { sending, sent, read }

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? receiverId;
  final String text;
  final DateTime createdAt;
  final MessageStatus status;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.receiverId,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    MessageStatus status = MessageStatus.sent;
    if (json['status'] == 'sending') {
      status = MessageStatus.sending;
    } else if (json['status'] == 'read') {
      status = MessageStatus.read;
    }

    return Message(
      id: json['id'] as String,
      chatId: (json['chatId'] ?? 'default_chat') as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String?,
      text: json['text'] as String,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'] as String) 
          : DateTime.now(),
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    String statusStr = 'sent';
    if (status == MessageStatus.sending) {
      statusStr = 'sending';
    } else if (status == MessageStatus.read) {
      statusStr = 'read';
    }

    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'status': statusStr,
    };
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? receiverId,
    String? text,
    DateTime? createdAt,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
