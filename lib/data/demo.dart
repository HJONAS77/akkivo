import '../domain/models.dart';

BoardBundle demoBoards() => BoardBundle(
  const [
    Board(id: 'home', name: 'Min vardag', rows: 3, columns: 3),
    Board(id: 'feelings', name: 'Så känner jag', rows: 2, columns: 3),
  ],
  [
    for (final entry in [
      'Jag vill',
      'ha',
      'vatten',
      'mat',
      'hjälp',
      'paus',
    ].asMap().entries)
      Cell(
        id: 'home-${entry.key}',
        boardId: 'home',
        row: entry.key ~/ 3,
        column: entry.key % 3,
        text: entry.value,
        action: CellAction.addToMessage,
      ),
    const Cell(
      id: 'yes',
      boardId: 'home',
      row: 2,
      column: 0,
      text: 'Ja',
      action: CellAction.speak,
      color: 0xffdcefd9,
    ),
    const Cell(
      id: 'no',
      boardId: 'home',
      row: 2,
      column: 1,
      text: 'Nej',
      action: CellAction.speak,
      color: 0xffffe1dc,
    ),
    const Cell(
      id: 'feelings-link',
      boardId: 'home',
      row: 2,
      column: 2,
      text: 'Känslor',
      action: CellAction.navigateToBoard,
      target: 'feelings',
      color: 0xffe8e1f3,
    ),
    for (final entry in [
      'Jag är glad',
      'Jag är ledsen',
      'Jag är trött',
      'Jag har ont',
      'Jag är arg',
      'Jag mår bra',
    ].asMap().entries)
      Cell(
        id: 'feeling-${entry.key}',
        boardId: 'feelings',
        row: entry.key ~/ 3,
        column: entry.key % 3,
        text: entry.value,
        action: CellAction.speak,
        color: 0xffffeed0,
      ),
  ],
  'home',
);
