import 'package:flutter/material.dart';

/// Сетка с переносом (аналог CSS flex-wrap) с ручным drag-and-drop
/// переупорядочиванием элементов через ручку-«грипп» слева. Ширина элемента
/// считается по доступной ширине контейнера: обычные элементы занимают одну
/// колонку, "широкие" (см. [isWide]) — две, если позволяет место. На узких
/// экранах (одна колонка) всё естественным образом складывается в список.
class ReorderableFlexWrap<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool Function(T item)? isWide;
  final double minColumnWidth;
  final double spacing;
  final double runSpacing;
  final ValueChanged<List<T>> onReorder;

  const ReorderableFlexWrap({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    this.isWide,
    this.minColumnWidth = 300,
    this.spacing = 14,
    this.runSpacing = 14,
    required this.onReorder,
  });

  @override
  State<ReorderableFlexWrap<T>> createState() =>
      _ReorderableFlexWrapState<T>();
}

class _ReorderableFlexWrapState<T> extends State<ReorderableFlexWrap<T>> {
  String? _draggedId;
  String? _dragOverId;

  void _reorder(String draggedId, String targetId) {
    if (draggedId == targetId) return;
    final ids = widget.items.map(widget.idOf).toList();
    final from = ids.indexOf(draggedId);
    final to = ids.indexOf(targetId);
    if (from == -1 || to == -1) return;

    final newItems = List<T>.of(widget.items);
    final moved = newItems.removeAt(from);
    newItems.insert(to, moved);
    widget.onReorder(newItems);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var columns = (maxWidth / widget.minColumnWidth).floor();
        if (columns < 1) columns = 1;
        final columnWidth = columns <= 1
            ? maxWidth
            : (maxWidth - widget.spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: widget.spacing,
          runSpacing: widget.runSpacing,
          children: widget.items.map((item) {
            final id = widget.idOf(item);
            final wide = columns > 1 && (widget.isWide?.call(item) ?? false);
            final width = wide
                ? columnWidth * 2 + widget.spacing
                : columnWidth;
            final isDragged = _draggedId == id;
            final isOver =
                _dragOverId == id && _draggedId != null && _draggedId != id;
            final content = widget.itemBuilder(context, item);

            final grip = const Padding(
              padding: EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: Color(0xFFBDBDBD),
                size: 18,
              ),
            );

            final tile = AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isOver
                      ? const Color(0xFF1565C0)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: isDragged ? 0.4 : 1,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Draggable<String>(
                      data: id,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: width,
                          child: Opacity(opacity: 0.85, child: content),
                        ),
                      ),
                      childWhenDragging: const Icon(
                        Icons.drag_indicator_rounded,
                        color: Color(0xFFBDBDBD),
                        size: 18,
                      ),
                      onDragStarted: () => setState(() => _draggedId = id),
                      onDragEnd: (_) => setState(() {
                        _draggedId = null;
                        _dragOverId = null;
                      }),
                      child: grip,
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            );

            return DragTarget<String>(
              onWillAcceptWithDetails: (details) => details.data != id,
              onMove: (details) {
                if (_dragOverId != id) setState(() => _dragOverId = id);
              },
              onLeave: (_) {
                if (_dragOverId == id) setState(() => _dragOverId = null);
              },
              onAcceptWithDetails: (details) {
                _reorder(details.data, id);
                setState(() => _dragOverId = null);
              },
              builder: (context, candidateData, rejectedData) => tile,
            );
          }).toList(),
        );
      },
    );
  }
}
