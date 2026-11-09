import 'package:dio/dio.dart';

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin Dio wrapper that attaches the bearer token and normalizes
/// FastAPI error payloads (`detail` as a string, an object, or a validation list).
class ApiClient {
  ApiClient({String? baseUrl, HttpClientAdapter? adapter})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.requestTimeout,
          receiveTimeout: AppConfig.requestTimeout,
          headers: {'Content-Type': 'application/json'},
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final value = token;
      if (value != null && value.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $value';
      }
      handler.next(options);
    }));
  }

  final Dio _dio;
  String? token;
  void Function()? onUnauthorized;

  bool get hasToken => token?.isNotEmpty ?? false;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.post(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.put(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.delete(path, queryParameters: _clean(query)));

  Future<dynamic> uploadFile(
    String path,
    String filePath, {
    String field = 'file',
    String? filename,
  }) {
    final name = filename ?? filePath.split(RegExp(r'[\\/]')).last;
    final form = FormData.fromMap({
      field: MultipartFile.fromFileSync(filePath, filename: name),
    });
    return _send(
      () => _dio.post(
        path,
        data: form,
        options: Options(contentType: Headers.multipartFormDataContentType),
      ),
    );
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    return Map.fromEntries(query.entries.where((e) => e.value != null && e.value != ''));
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      final error = _toApiException(e);
      if (error.isUnauthorized && hasToken) onUnauthorized?.call();
      throw error;
    }
  }

  ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      return ApiException('network', code: 'NETWORK');
    }
    final data = response.data;
    String message = 'HTTP ${response.statusCode}';
    String? code;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is Map) {
        message = (detail['message'] ?? message).toString();
        code = detail['code']?.toString();
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        message = first is Map ? (first['msg'] ?? message).toString() : first.toString();
      }
    }
    return ApiException(message, statusCode: response.statusCode, code: code);
  }
}
