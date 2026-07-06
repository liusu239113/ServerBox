/// Ollama 鏈湴妯″瀷鏈嶅姟
library;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

class OllamaModel {
  final String name;
  final String size;
  const OllamaModel({required this.name, required this.size});
  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    final bytes = (json['size'] as num?)?.toInt() ?? 0;
    return OllamaModel(name: json['name'] as String? ?? '', size: _fmt(bytes));
  }
  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}

sealed class PullProgress { const PullProgress(); }
class PullDownloading extends PullProgress {
  final int completed, total;
  final String status;
  const PullDownloading(this.completed, this.total, this.status);
  double get pct => total > 0 ? completed / total : 0;
}
class PullStatus extends PullProgress { final String msg; const PullStatus(this.msg); }
class PullDone extends PullProgress { final String name; const PullDone(this.name); }
class PullErr extends PullProgress { final String msg; const PullErr(this.msg); }
class OllamaService {
  final Dio _d;
  final String _url;
  OllamaService({Dio? dio, String baseUrl = 'http://127.0.0.1:11434'})
    : _d = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10))),
      _url = baseUrl;

  Future<bool> isAvailable() async {
    try { return (await _d.get('$_url/api/tags')).statusCode == 200; } catch (_) { return false; }
  }

  Future<List<OllamaModel>> listModels() async {
    try {
      final r = await _d.get('$_url/api/tags');
      return ((r.data['models'] as List?) ?? []).map((m) => OllamaModel.fromJson(m as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  Stream<PullProgress> pullModel(String name) async* {
    try {
      final r = await _d.post<ResponseBody>('$_url/api/pull',
        data: jsonEncode({'name': name, 'stream': true}),
        options: Options(responseType: ResponseType.stream, headers: {'Content-Type': 'application/json'}, receiveTimeout: const Duration(hours: 2)),
      );
      final s = r.data?.stream.cast<List<int>>().transform(utf8.decoder);
      if (s == null) { yield const PullErr('Empty response'); return; }
      final buf = StringBuffer();
      await for (final c in s) {
        buf.write(c);
        while (true) {
          final n = buf.toString().indexOf('\n');
          if (n == -1) break;
          final line = buf.toString().substring(0, n).trim();
          buf..clear()..write(buf.toString().substring(n + 1));
          if (line.isEmpty) continue;
          try {
            final j = jsonDecode(line) as Map<String, dynamic>;
            final st = j['status'] as String? ?? '';
            if (st == 'success') { yield PullDone(name); return; }
            if (j.containsKey('completed') && j.containsKey('total')) {
              yield PullDownloading((j['completed'] as num).toInt(), (j['total'] as num).toInt(), st);
            } else { yield PullStatus(st); }
          } catch (_) {}
        }
      }
      final rem = buf.toString().trim();
      if (rem.isNotEmpty) {
        try { if ((jsonDecode(rem) as Map)['status'] == 'success') { yield PullDone(name); return; } } catch (_) {}
      }
    } on DioException catch (e) { yield PullErr(e.message ?? 'conn err'); } catch (e) { yield PullErr('$e'); }
  }
}
