/// Tracks which conversation the user currently has open (to suppress alerts).
class ChatSession {
  ChatSession._();
  static final ChatSession instance = ChatSession._();

  String? openConversationId;

  void enter(String conversationId) => openConversationId = conversationId;

  void leave(String conversationId) {
    if (openConversationId == conversationId) openConversationId = null;
  }
}
