import 'package:flutter/material.dart';

const double _kMinWidthFraction = 0.22;
const double _kMinTileWidth = 220;

/// Ширину привязываем к колонкам, а не к абсолютным пикселям: при шаге в
/// пикселях сумма ширин почти никогда не совпадает с шириной строки, и справа
/// оставалась пустая полоса, а плашки перестали выравниваться. Колоночная
/// сетка по формуле cols/N * (доступная ширина + промежуток) − промежуток
/// раскладывается ровно, без остатка.
const int _kGridColumns = 12;

/// Высоту достаточно привязать к пикселям — по вертикали ничего не тайлится.
const double _kGridStepPx = 40;
const double _kMinTileHeight = 120;

double _snap(double value, double step) => (value / step).round() * step;

/// Сколько колонок сетки занимает ширина [raw].
int _columnsFor(double raw, double maxWidth, double spacing) {
  final unit = (maxWidth + spacing) / _kGridColumns;
  return (((raw + spacing) / unit).round()).clamp(1, _kGridColumns);
}

double _widthForColumns(int columns, double maxWidth, double spacing) {
  final width = columns / _kGridColumns * (maxWidth + spacing) - spacing;
  return width < 0 ? maxWidth : width;
}

/// Сетка с переносом (аналог CSS flex-wrap) с ручным drag-and-drop
/// переупорядочиванием элементов через ручку-«грипп» слева. Ширина элемента
/// считается по доступной ширине контейнера: обычные элементы занимают одну
/// колонку, "широкие" (см. [isWide]) — две, если позволяет место. На узких
/// экранах (одна колонка) всё естественным образом складывается в список.
///
/// Если задан [widthFractionOf] (и [onResize]) — вместо фиксированных
/// narrow/wide колонок используется непрерывный ресайз: у каждой плашки
/// появляется ручка в правом нижнем углу, перетаскивание которой плавно
/// меняет долю доступной ширины, которую занимает плашка (как ресайз виджетов
/// на дашборде в Яндекс Трекере). Высота при этом остаётся по содержимому —
/// не резервируем/не обрезаем контент карточек под произвольную высоту.
class ReorderableFlexWrap<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool Function(T item)? isWide;
  final double minColumnWidth;
  final double spacing;
  final double runSpacing;
  final ValueChanged<List<T>> onReorder;

  final double Function(T item)? widthFractionOf;
  final void Function(String id, double fraction)? onResize;

  /// Заданная вручную высота плашки в пикселях. null/0 — высота по
  /// содержимому, как было до появления ресайза по вертикали.
  final double? Function(T item)? heightOf;
  final void Function(String id, double? height)? onResizeHeight;

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
    this.widthFractionOf,
    this.onResize,
    this.heightOf,
    this.onResizeHeight,
  });

  @override
  State<ReorderableFlexWrap<T>> createState() =>
      _ReorderableFlexWrapState<T>();
}

class _ReorderableFlexWrapState<T> extends State<ReorderableFlexWrap<T>> {
  String? _draggedId;
  String? _dragOverId;

  String? _resizingId;
  double _resizeDeltaPx = 0;
  double _resizeDeltaPy = 0;

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
    final resizeEnabled =
        widget.widthFractionOf != null && widget.onResize != null;

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
            final isResizingThis = resizeEnabled && _resizingId == id;

            double width;
            double baseFraction = 1;
            if (resizeEnabled) {
              baseFraction = widget.widthFractionOf!(item).clamp(
                _kMinWidthFraction,
                1.0,
              );
              // Тянем по пикселям, но кладём на колоночную сетку — тогда
              // соседние плашки складываются в строку без зазора справа.
              final rawWidth = isResizingThis
                  ? baseFraction * maxWidth + _resizeDeltaPx
                  : baseFraction * maxWidth;
              final columns = _columnsFor(rawWidth, maxWidth, widget.spacing);
              width = _widthForColumns(columns, maxWidth, widget.spacing);
              // На узком экране колонка может оказаться уже минимума — тогда
              // растягиваем на всю доступную ширину, а не режем содержимое.
              if (width < _kMinTileWidth && maxWidth >= _kMinTileWidth) {
                width = _kMinTileWidth;
              }
              if (width > maxWidth) width = maxWidth;
            } else {
              final wide = columns > 1 && (widget.isWide?.call(item) ?? false);
              width = wide ? columnWidth * 2 + widget.spacing : columnWidth;
            }

            // Высота: null — по содержимому. Задать её вручную можно тем же
            // уголком, потянув вниз.
            final heightEnabled =
                widget.heightOf != null && widget.onResizeHeight != null;
            final baseHeight = heightEnabled ? widget.heightOf!(item) : null;
            double? height;
            if (heightEnabled) {
              final raw = isResizingThis
                  ? (baseHeight ?? _kMinTileHeight) + _resizeDeltaPy
                  : baseHeight;
              if (raw != null) {
                final snapped = _snap(raw, _kGridStepPx);
                height = snapped < _kMinTileHeight ? _kMinTileHeight : snapped;
              }
            }

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
              duration: isResizingThis
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
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
                child: Stack(
                  children: [
                    Row(
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
                        // Заданная высота — жёсткая, чтобы блок можно было и
                        // сжать. Обрезки при этом нет: карточки (CardSection и
                        // _Card) при ограниченной высоте прокручивают
                        // содержимое внутри себя, сохраняя рамку и тень.
                        Expanded(
                          child: height == null
                              ? content
                              : SizedBox(height: height, child: content),
                        ),
                      ],
                    ),
                    if (resizeEnabled)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: heightEnabled
                              ? SystemMouseCursors.resizeDownRight
                              : SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => setState(() {
                              _resizingId = id;
                              _resizeDeltaPx = 0;
                              _resizeDeltaPy = 0;
                            }),
                            onPanUpdate: (details) => setState(() {
                              _resizeDeltaPx += details.delta.dx;
                              _resizeDeltaPy += details.delta.dy;
                            }),
                            onPanEnd: (_) {
                              final columns = _columnsFor(
                                baseFraction * maxWidth + _resizeDeltaPx,
                                maxWidth,
                                widget.spacing,
                              );
                              final snappedWidth = _widthForColumns(
                                columns,
                                maxWidth,
                                widget.spacing,
                              );
                              widget.onResize!(
                                id,
                                (snappedWidth / maxWidth).clamp(
                                  _kMinWidthFraction,
                                  1.0,
                                ),
                              );

                              if (heightEnabled) {
                                final raw =
                                    (baseHeight ?? _kMinTileHeight) +
                                    _resizeDeltaPy;
                                // Утащили выше минимума — считаем это отменой
                                // ручной высоты и возвращаем «по содержимому».
                                final snapped = _snap(raw, _kGridStepPx);
                                widget.onResizeHeight!(
                                  id,
                                  snapped < _kMinTileHeight ? null : snapped,
                                );
                              }

                              setState(() {
                                _resizingId = null;
                                _resizeDeltaPx = 0;
                                _resizeDeltaPy = 0;
                              });
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.bottomRight,
                              padding: const EdgeInsets.only(
                                bottom: 2,
                                right: 2,
                              ),
                              child: const Icon(
                                Icons.open_in_full_rounded,
                                size: 14,
                                color: Color(0xFFBDBDBD),
                              ),
                            ),
                          ),
                        ),
                      ),
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
