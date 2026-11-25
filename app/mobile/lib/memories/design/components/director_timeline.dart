import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/design/components/basics.dart';
import 'package:immich_mobile/memories/design/tokens.dart';
import 'package:immich_mobile/memories/design/typography.dart';

class TimelineEntry {
  final String title;
  final String? detail;
  final int? ms;
  const TimelineEntry(this.title, {this.detail, this.ms});
}

/// "Under the hood": an elegant expandable timeline of the director's steps with timings.
class DirectorTimeline extends StatefulWidget {
  final List<TimelineEntry> stages;
  final List<TimelineEntry> events;
  final int? totalMs;
  final String title;

  const DirectorTimeline({
    super.key,
    required this.stages,
    this.events = const [],
    this.totalMs,
    this.title = 'Under the hood',
  });

  @override
  State<DirectorTimeline> createState() => _DirectorTimelineState();
}

class _DirectorTimelineState extends State<DirectorTimeline> {
  bool _open = false;
  bool _showAllEvents = false;

  String _fmtMs(int ms) => ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    final maxMs = widget.stages.fold<int>(1, (m, e) => math.max(m, e.ms ?? 0));
    final total = widget.totalMs ?? widget.stages.fold<int>(0, (s, e) => s + (e.ms ?? 0));
    final events = _showAllEvents ? widget.events : widget.events.take(6).toList();

    return AnimatedContainer(
      duration: MMotion.standard,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: MRadius.lgAll,
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: MRadius.lgAll,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(MSpace.md + 2),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: MRadius.smAll),
                      child: const Center(child: DirectorSpark(size: 20)),
                    ),
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: type.title.copyWith(fontSize: 19)),
                          const SizedBox(height: 2),
                          Text(
                            total > 0
                                ? '${widget.stages.length} steps · made in ${_fmtMs(total)}'
                                : 'How the director made these',
                            style: type.bodyMuted.copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: MMotion.standard,
                      child: Icon(Icons.expand_more_rounded, color: p.inkMuted, size: 28),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: MMotion.emphasised,
            curve: MMotion.emphasisedCurve,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(MSpace.md + 2, 0, MSpace.md + 2, MSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(color: p.line),
                        const SizedBox(height: MSpace.sm),
                        for (var i = 0; i < widget.stages.length; i++)
                          _TimelineRow(
                            entry: widget.stages[i],
                            fraction: (widget.stages[i].ms ?? 0) / maxMs,
                            isLast: i == widget.stages.length - 1,
                            label: widget.stages[i].ms == null ? null : _fmtMs(widget.stages[i].ms!),
                          ),
                        if (widget.events.isNotEmpty) ...[
                          const SizedBox(height: MSpace.md),
                          Text('DIRECTOR\'S NOTES', style: type.overline),
                          const SizedBox(height: MSpace.xs),
                          for (final e in events)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 7),
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(color: p.diya, shape: BoxShape.circle),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: e.title, style: type.label.copyWith(fontSize: 13.5)),
                                          if (e.detail != null && e.detail!.isNotEmpty)
                                            TextSpan(
                                              text: '  ${e.detail}',
                                              style: type.bodyMuted.copyWith(fontSize: 13.5),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (e.ms != null)
                                    Text(_fmtMs(e.ms!), style: type.label.copyWith(color: p.inkMuted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                          if (widget.events.length > 6)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => setState(() => _showAllEvents = !_showAllEvents),
                                child: Text(_showAllEvents ? 'Show less' : 'Show all ${widget.events.length} notes'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final double fraction;
  final bool isLast;
  final String? label;

  const _TimelineRow({required this.entry, required this.fraction, required this.isLast, this.label});

  @override
  Widget build(BuildContext context) {
    final p = MemoriesPalette.of(context);
    final type = MemoriesType.of(p);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.surface,
                  border: Border.all(color: p.diya, width: 2.5),
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: p.line)),
            ],
          ),
          const SizedBox(width: MSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : MSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(entry.title, style: type.titleSans.copyWith(fontSize: 15.5))),
                      if (label != null) Text(label!, style: type.label.copyWith(color: p.inkMuted)),
                    ],
                  ),
                  if (entry.detail != null && entry.detail!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(entry.detail!, style: type.bodyMuted.copyWith(fontSize: 13.5)),
                  ],
                  if (entry.ms != null) ...[
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fraction.clamp(0.02, 1.0)),
                          duration: MMotion.emphasised,
                          curve: MMotion.emphasisedCurve,
                          builder: (context, v, _) => Container(
                            width: c.maxWidth * v,
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: MRadius.pillAll,
                              gradient: LinearGradient(colors: [p.marigold, p.diya]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
