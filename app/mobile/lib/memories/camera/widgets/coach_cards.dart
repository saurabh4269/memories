import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/camera/coach_models.dart';

/// Swipeable "missing shot" cards from the director's shot coach.
///
/// Renders nothing when there are no cards. Large type for elder-friendly reading.
class CoachCardsOverlay extends StatefulWidget {
  const CoachCardsOverlay({
    super.key,
    required this.cards,
    required this.missingLabel,
    this.onDismiss,
  });

  final List<CoachCard> cards;

  /// Prefix shown before the title, e.g. "Missing".
  final String missingLabel;

  final VoidCallback? onDismiss;

  @override
  State<CoachCardsOverlay> createState() => _CoachCardsOverlayState();
}

class _CoachCardsOverlayState extends State<CoachCardsOverlay> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void didUpdateWidget(CoachCardsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= widget.cards.length && widget.cards.isNotEmpty) {
      _page = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    final textScale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 112 * textScale.scale(1),
            child: PageView.builder(
              controller: _controller,
              itemCount: cards.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _CoachCardTile(
                card: cards[i],
                missingLabel: widget.missingLabel,
                onDismiss: widget.onDismiss,
              ),
            ),
          ),
          if (cards.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: i == _page ? 0.95 : 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CoachCardTile extends StatelessWidget {
  const _CoachCardTile({required this.card, required this.missingLabel, this.onDismiss});

  final CoachCard card;
  final String missingLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final title = card.title.isEmpty ? '' : '$missingLabel: ${card.title}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 12),
                child: Icon(Icons.lightbulb_rounded, color: Color(0xFFFFD60A), size: 28),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    if (card.tip.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          card.tip,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 16, height: 1.25),
                        ),
                      ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
