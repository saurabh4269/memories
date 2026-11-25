import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/memories/post/post_models.dart';

void main() {
  test('parses channels and drops entries without id', () {
    final list = PostChannel.listFromResponse({
      'channels': [
        {'id': 'c1', 'provider': 'Bluesky', 'name': 'Family', 'avatar': 'https://x/a.png'},
        {'id': 'c2', 'provider': 'telegram', 'name': 'Group'},
        {'provider': 'discord', 'name': 'no id'},
      ],
    });
    expect(list.map((c) => c.id), ['c1', 'c2']);
    expect(list.first.providerLabel, 'Bluesky');
    expect(list.last.avatar, isNull);
  });

  test('empty / malformed channels', () {
    expect(PostChannel.listFromResponse({}), isEmpty);
    expect(PostChannel.listFromResponse({'channels': 'nope'}), isEmpty);
  });

  test('parses post outcomes', () {
    final posts = PostOutcome.listFromResponse({
      'posts': [
        {'channel': 'c1', 'status': 'success', 'url': 'https://bsky.app/p/1'},
        {'channel': 'c2', 'status': 'error', 'error': 'token expired'},
        {
          'channel': {'id': 'c3'},
          'status': 'pending',
        },
      ],
    });
    expect(posts[0].state, PostState.success);
    expect(posts[0].url, 'https://bsky.app/p/1');
    expect(posts[1].state, PostState.failed);
    expect(posts[1].error, 'token expired');
    expect(posts[2].channel, 'c3');
    expect(posts[2].state, PostState.posting);
  });
}
