import 'package:dart_openai/openai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chatgpt/cubit/setting_cubit.dart';
import 'package:flutter_chatgpt/repository/conversation.dart';
import 'package:get_it/get_it.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class MessageRepository {
  static final MessageRepository _instance = MessageRepository._internal();

  factory MessageRepository() {
    return _instance;
  }

  MessageRepository._internal() {
    init();
  }

  void postMessage(Message message, ValueChanged<Message> onResponse,
      ValueChanged<Message> onError, ValueChanged<Message> onSuccess) async {
    List<Message> messages = await ConversationRepository()
        .getMessagesByConversationUUid(message.conversationId);
    _getResponseFromGpt(messages, onResponse, onError, onSuccess);
  }

  void init() {
    OpenAI.apiKey = GetIt.instance.get<UserSettingCubit>().state.key;
    OpenAI.baseUrl = GetIt.instance.get<UserSettingCubit>().state.baseUrl;
  }

  void _getResponseFromGpt(
      List<Message> messages,
      ValueChanged<Message> onResponse,
      ValueChanged<Message> errorCallback,
      ValueChanged<Message> onSuccess) async {
    List<OpenAIChatCompletionChoiceMessageModel> openAIMessages = [];
    //将messages反转
    messages = messages.reversed.toList();
    while (true) {
      // 将messages里面的每条消息的内容取出来拼接在一起
      String content = "";
      for (Message message in messages) {
        content = content + message.text;
        if (content.length < 1800) {
          // 插入到 openAIMessages 第一个位置
          openAIMessages.insert(
            0,
            OpenAIChatCompletionChoiceMessageModel(
              content: message.text,
              role: message.role.asOpenAIChatMessageRole,
            ),
          );
        }
      }
      break;
    }
    var message = Message(
        conversationId: messages.first.conversationId,
        text: "",
        role: Role.assistant); //仅仅第一个返回了角色
    if (GetIt.instance.get<UserSettingCubit>().state.useStream) {
      Stream<OpenAIStreamChatCompletionModel> chatStream = OpenAI.instance.chat
          .createStream(
              model: GetIt.instance.get<UserSettingCubit>().state.gptModel,
              messages: openAIMessages);
      chatStream.listen(
        (chatStreamEvent) {
          if (chatStreamEvent.choices.first.delta.content != null) {
            message.text =
                message.text + chatStreamEvent.choices.first.delta.content!;
            onResponse(message);
          }
        },
        onError: (error) {
          message.text = error.message;
          errorCallback(message);
        },
        onDone: () {
          onSuccess(message);
        },
      );
    } else {
      try {
        // var response = await OpenAI.instance.chat.create(
        //   model: GetIt.instance.get<UserSettingCubit>().state.gptModel,
        //   messages: openAIMessages,
        // );
        // message.text = response.choices.first.message.content;
        // onSuccess(message);

        var url = 'http://168.138.54.34:8000/api/chat';
        var headersMap = <String, String>{};
        headersMap["Content-Type"] = "application/json";

        var jsonParams =
            utf8.encode(json.encode({'content': openAIMessages.last.content}));
        http.Client()
            .post(Uri.parse(url), body: jsonParams, headers: headersMap)
            .then((http.Response response) {
          if (response.statusCode == 200) {
            // response.transform(utf8.decoder).join().then((String json) {
            var data = jsonDecode(response.body);
            message.text = data['content'];
            onSuccess(message);
          } else {
            message.text = 'HttpClientJson Fail：${response.statusCode}';
            errorCallback(message);
          }
        });
      } catch (e) {
        message.text = e.toString();
        errorCallback(message);
      }
    }
  }

  deleteMessage(int messageId) {
    ConversationRepository().deleteMessage(messageId);
  }
}
