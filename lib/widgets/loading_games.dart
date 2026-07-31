import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'card_section.dart';

/// Блок с мини-игрой на время загрузки.
///
/// Выгрузка показов за весь период — это минуты ожидания, и «дашборд можно
/// листать» на самом деле никакое не занятие. Игра выбирается случайно один раз
/// при появлении блока: жеребьёвка живёт в initState, поэтому перерисовки
/// дашборда (а их во время загрузки много) партию не сбивают.
class LoadingGameCard extends StatefulWidget {
  const LoadingGameCard({super.key});

  @override
  State<LoadingGameCard> createState() => _LoadingGameCardState();
}

class _LoadingGameCardState extends State<LoadingGameCard> {
  late final bool _jumper = Random().nextBool();

  @override
  Widget build(BuildContext context) {
    return CardSection(
      title: _jumper ? 'Фотограф и билборды' : 'Три в ряд',
      subtitle: _jumper
          ? 'Пока считаются показы: клик или пробел — прыжок'
          : 'Пока считаются показы: меняйте соседние местами',
      child: _jumper ? const _JumperGame() : const _MatchThreeGame(),
    );
  }
}

// ── Игра 1: фотограф прыгает через билборды ──────────────────────────────────

class _JumperGame extends StatefulWidget {
  const _JumperGame();

  @override
  State<_JumperGame> createState() => _JumperGameState();
}

class _JumperGameState extends State<_JumperGame>
    with SingleTickerProviderStateMixin {
  static const double _height = 150;
  static const double _groundY = 122;
  static const double _playerX = 26;
  static const double _playerW = 18;
  static const double _playerH = 26;
  static const double _gravity = 1900;
  static const double _jumpSpeed = 620;

  late final Ticker _ticker;
  final _rnd = Random();
  final _focus = FocusNode();

  Duration _lastTick = Duration.zero;
  double _width = 320;

  /// Высота над землёй и вертикальная скорость.
  double _y = 0;
  double _vy = 0;

  final List<_Billboard> _billboards = [];
  double _speed = 190;
  int _score = 0;
  int _best = 0;
  bool _running = false;
  bool _over = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final rawDt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (!_running) return;
    // Ограничиваем шаг: вкладка могла быть свёрнута, и один кадр на секунду
    // телепортировал бы фотографа сквозь билборд.
    final dt = rawDt.clamp(0.0, 0.05);

    setState(() {
      _y += _vy * dt;
      _vy -= _gravity * dt;
      if (_y <= 0) {
        _y = 0;
        _vy = 0;
      }

      _speed = (190 + _score * 6).clamp(190, 420).toDouble();

      for (final billboard in _billboards) {
        billboard.x -= _speed * dt;
      }

      // Прошедшие билборды считаем и убираем.
      _billboards.removeWhere((b) {
        final passed = b.x + b.width < 0;
        if (passed) _score++;
        return passed;
      });

      final needSpawn =
          _billboards.isEmpty ||
          _billboards.last.x < _width - 170 - _rnd.nextInt(150);
      if (needSpawn) {
        _billboards.add(
          _Billboard(
            x: _width + 10,
            width: 14 + _rnd.nextInt(10),
            height: 24 + _rnd.nextInt(18),
          ),
        );
      }

      if (_billboards.any(_hits)) {
        _running = false;
        _over = true;
        if (_score > _best) _best = _score;
      }
    });
  }

  bool _hits(_Billboard billboard) {
    final playerLeft = _playerX;
    final playerRight = _playerX + _playerW;
    final playerBottom = _y;
    if (billboard.x > playerRight || billboard.x + billboard.width < playerLeft) {
      return false;
    }
    // Щит висит на столбе: сталкиваемся только если не перепрыгнули верх щита.
    return playerBottom < billboard.height;
  }

  void _tap() {
    _focus.requestFocus();
    if (!_running) {
      setState(() {
        _running = true;
        _over = false;
        _score = 0;
        _y = 0;
        _vy = 0;
        _speed = 190;
        _billboards.clear();
      });
      return;
    }
    if (_y <= 0.5) {
      setState(() => _vy = _jumpSpeed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Билбордов пройдено: $_score',
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'рекорд: $_best',
              style: const TextStyle(color: kTextSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        KeyboardListener(
          focusNode: _focus,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp)) {
              _tap();
            }
          },
          child: GestureDetector(
            onTap: _tap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _width = constraints.maxWidth;
                  return Container(
                    height: _height,
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _JumperPainter(
                              playerY: _y,
                              billboards: _billboards,
                              groundY: _groundY,
                              playerX: _playerX,
                              playerW: _playerW,
                              playerH: _playerH,
                            ),
                          ),
                        ),
                        if (!_running)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _over
                                    ? 'Снят билборд, а не перепрыгнут. '
                                          'Клик — ещё раз'
                                    : 'Клик или пробел — старт',
                                style: const TextStyle(
                                  color: kTextPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Billboard {
  double x;
  final double width;
  final double height;

  _Billboard({required this.x, required this.width, required this.height});
}

class _JumperPainter extends CustomPainter {
  final double playerY;
  final List<_Billboard> billboards;
  final double groundY;
  final double playerX;
  final double playerW;
  final double playerH;

  _JumperPainter({
    required this.playerY,
    required this.billboards,
    required this.groundY,
    required this.playerX,
    required this.playerW,
    required this.playerH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ground = Paint()
      ..color = kBorder
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, groundY + 1),
      Offset(size.width, groundY + 1),
      ground,
    );

    final post = Paint()..color = const Color(0xFF9E9E9E);
    final board = Paint()..color = kAccent;
    for (final billboard in billboards) {
      final top = groundY - billboard.height;
      // Столб.
      canvas.drawRect(
        Rect.fromLTWH(
          billboard.x + billboard.width / 2 - 1.5,
          top + billboard.height * 0.45,
          3,
          billboard.height * 0.55,
        ),
        post,
      );
      // Щит.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            billboard.x,
            top,
            billboard.width,
            billboard.height * 0.5,
          ),
          const Radius.circular(2),
        ),
        board,
      );
    }

    // Фотограф: голова, корпус, ноги и фотоаппарат в руках.
    final body = Paint()..color = const Color(0xFF37474F);
    final bottom = groundY - playerY;
    final torsoTop = bottom - playerH;
    canvas.drawCircle(Offset(playerX + playerW / 2, torsoTop + 4), 5, body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(playerX + 3, torsoTop + 9, playerW - 6, playerH - 15),
        const Radius.circular(3),
      ),
      body,
    );
    // Ноги: в воздухе поджаты, на земле расставлены.
    final inAir = playerY > 1;
    canvas.drawRect(
      Rect.fromLTWH(playerX + 3, bottom - 6, 4, inAir ? 4 : 6),
      body,
    );
    canvas.drawRect(
      Rect.fromLTWH(playerX + playerW - 7, bottom - 6, 4, inAir ? 6 : 6),
      body,
    );
    // Фотоаппарат.
    final camera = Paint()..color = const Color(0xFF212121);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(playerX + playerW - 3, torsoTop + 11, 8, 6),
        const Radius.circular(1.5),
      ),
      camera,
    );
    canvas.drawCircle(
      Offset(playerX + playerW + 2, torsoTop + 14),
      2,
      Paint()..color = const Color(0xFFB0BEC5),
    );
  }

  @override
  bool shouldRepaint(_JumperPainter oldDelegate) => true;
}

// ── Игра 2: три в ряд ────────────────────────────────────────────────────────

/// Элемент поля. Цвет — основной признак: если эмодзи в системе не окажется,
/// плитки всё равно останутся различимыми.
class _Gem {
  final String glyph;
  final String? badge;
  final Color color;
  final double fontSize;
  final String name;

  const _Gem({
    required this.glyph,
    required this.color,
    required this.name,
    this.badge,
    this.fontSize = 20,
  });
}

const _gems = <_Gem>[
  _Gem(
    glyph: 'ФК',
    color: Color(0xFF7B1FA2),
    name: 'Киркоров',
    fontSize: 14,
  ),
  _Gem(
    glyph: 'НБ',
    color: Color(0xFFF9A825),
    name: 'Басков',
    fontSize: 14,
  ),
  _Gem(glyph: '🪆', color: Color(0xFFE53935), name: 'матрёшка'),
  _Gem(glyph: '🐄', color: Color(0xFF43A047), name: 'корова'),
  _Gem(
    glyph: 'КОР',
    color: Color(0xFF1565C0),
    name: 'КОР',
    fontSize: 12,
  ),
  _Gem(
    glyph: '🐉',
    badge: '4',
    color: Color(0xFF00838F),
    name: 'дракон с четвёркой',
  ),
];

class _MatchThreeGame extends StatefulWidget {
  const _MatchThreeGame();

  @override
  State<_MatchThreeGame> createState() => _MatchThreeGameState();
}

class _MatchThreeGameState extends State<_MatchThreeGame> {
  static const int _size = 6;

  final _rnd = Random();
  late List<List<int>> _board;
  ({int row, int col})? _selected;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _board = _freshBoard();
  }

  List<List<int>> _freshBoard() {
    List<List<int>> board = [];
    // Ограничение попыток, а не while(true): случайность здесь на стороне
    // игрока, но зависшая вкладка вместо развлечения — плохая шутка.
    for (var attempt = 0; attempt < 200; attempt++) {
      board = [
        for (var r = 0; r < _size; r++)
          [for (var c = 0; c < _size; c++) _rnd.nextInt(_gems.length)],
      ];
      // Стартовое поле без готовых линий и хотя бы с одним возможным ходом:
      // иначе первая же партия либо сама себя собирает, либо мертва.
      if (_matches(board).isEmpty && _hasMoves(board)) return board;
    }
    return board;
  }

  /// Все клетки, входящие в линии от трёх подряд.
  Set<int> _matches(List<List<int>> board) {
    final found = <int>{};

    void scan(bool horizontal) {
      for (var a = 0; a < _size; a++) {
        var runStart = 0;
        for (var b = 1; b <= _size; b++) {
          final current = b < _size
              ? (horizontal ? board[a][b] : board[b][a])
              : -1;
          final previous = horizontal ? board[a][b - 1] : board[b - 1][a];
          if (current != previous) {
            if (b - runStart >= 3) {
              for (var k = runStart; k < b; k++) {
                found.add(horizontal ? a * _size + k : k * _size + a);
              }
            }
            runStart = b;
          }
        }
      }
    }

    scan(true);
    scan(false);
    return found;
  }

  bool _hasMoves(List<List<int>> board) {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        for (final step in const [(0, 1), (1, 0)]) {
          final r2 = r + step.$1;
          final c2 = c + step.$2;
          if (r2 >= _size || c2 >= _size) continue;
          final copy = [for (final row in board) [...row]];
          final tmp = copy[r][c];
          copy[r][c] = copy[r2][c2];
          copy[r2][c2] = tmp;
          if (_matches(copy).isNotEmpty) return true;
        }
      }
    }
    return false;
  }

  /// Убирает линии, сдвигает столбцы вниз и досыпает новые — до тех пор, пока
  /// каскад не закончится.
  void _resolve() {
    var guard = 0;
    while (guard++ < 40) {
      final matched = _matches(_board);
      if (matched.isEmpty) break;
      _score += matched.length;

      for (final index in matched) {
        _board[index ~/ _size][index % _size] = -1;
      }

      for (var c = 0; c < _size; c++) {
        final column = <int>[];
        for (var r = _size - 1; r >= 0; r--) {
          if (_board[r][c] != -1) column.add(_board[r][c]);
        }
        for (var r = _size - 1; r >= 0; r--) {
          final fromBottom = _size - 1 - r;
          _board[r][c] = fromBottom < column.length
              ? column[fromBottom]
              : _rnd.nextInt(_gems.length);
        }
      }
    }

    if (!_hasMoves(_board)) _board = _freshBoard();
  }

  void _tapCell(int row, int col) {
    final selected = _selected;
    if (selected == null) {
      setState(() => _selected = (row: row, col: col));
      return;
    }
    if (selected.row == row && selected.col == col) {
      setState(() => _selected = null);
      return;
    }

    final adjacent =
        (selected.row - row).abs() + (selected.col - col).abs() == 1;
    if (!adjacent) {
      setState(() => _selected = (row: row, col: col));
      return;
    }

    setState(() {
      final tmp = _board[selected.row][selected.col];
      _board[selected.row][selected.col] = _board[row][col];
      _board[row][col] = tmp;
      _selected = null;

      if (_matches(_board).isEmpty) {
        // Обмен ничего не собрал — возвращаем как было.
        _board[row][col] = _board[selected.row][selected.col];
        _board[selected.row][selected.col] = tmp;
        return;
      }
      _resolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Собрано: $_score',
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _board = _freshBoard();
                _score = 0;
                _selected = null;
              }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                foregroundColor: kAccent,
              ),
              child: const Text('Заново', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            // Поле квадратное и не шире блока, но и не разъезжается на всю
            // ширину широкой плитки.
            final side = min(constraints.maxWidth, 260.0);
            final cell = (side - (_size - 1) * 4) / _size;
            return SizedBox(
              width: side,
              child: Column(
                children: [
                  for (var r = 0; r < _size; r++)
                    Padding(
                      padding: EdgeInsets.only(bottom: r == _size - 1 ? 0 : 4),
                      child: Row(
                        children: [
                          for (var c = 0; c < _size; c++)
                            Padding(
                              padding: EdgeInsets.only(
                                right: c == _size - 1 ? 0 : 4,
                              ),
                              child: _GemTile(
                                gem: _gems[_board[r][c]],
                                size: cell,
                                selected:
                                    _selected?.row == r && _selected?.col == c,
                                onTap: () => _tapCell(r, c),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          _gems.map((gem) => '${gem.glyph} — ${gem.name}').join(' · '),
          style: const TextStyle(color: kTextSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

class _GemTile extends StatelessWidget {
  final _Gem gem;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _GemTile({
    required this.gem,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: gem.color.withValues(alpha: selected ? 0.45 : 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? gem.color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  gem.glyph,
                  style: TextStyle(
                    fontSize: gem.fontSize,
                    fontWeight: FontWeight.w700,
                    color: gem.color,
                  ),
                ),
              ),
              if (gem.badge != null)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Text(
                    gem.badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: gem.color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
