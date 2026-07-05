import 'package:surlor_ai/data/model/server/snippet.dart';
import 'package:surlor_ai/data/store/cached_store.dart';

class SnippetStore extends CachedHiveStore<Snippet> {
  SnippetStore._() : super('snippet');

  static final instance = SnippetStore._();

  @override
  String getKey(Snippet item) => item.name;

  @override
  Snippet? fromJson(Map<String, dynamic> json) => Snippet.fromJson(json);
}
