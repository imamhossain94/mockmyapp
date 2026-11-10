class UndoStack<T> {
  UndoStack({this.maxSize = 50});

  final int maxSize;
  final List<T> _undo = [];
  final List<T> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  DateTime? _lastPush;

  void push(T previousState) {
    final now = DateTime.now();
    if (_lastPush != null &&
        now.difference(_lastPush!) < const Duration(milliseconds: 400)) {
      _lastPush = now;
      return;
    }

    _undo.add(previousState);
    if (_undo.length > maxSize) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _lastPush = now;
  }

  T? undo(T currentState) {
    if (!canUndo) return null;
    _redo.add(currentState);
    _lastPush = null;
    return _undo.removeLast();
  }

  T? redo(T currentState) {
    if (!canRedo) return null;
    _undo.add(currentState);
    _lastPush = null;
    return _redo.removeLast();
  }

  /// Drops all history.
  ///
  /// For when the stack's subject changes rather than its contents: the editor
  /// switching to another screen of the project keeps one stack, and carrying
  /// the old document's states across would let an undo silently edit a screen
  /// that is no longer on screen.
  void clear() {
    _undo.clear();
    _redo.clear();
    _lastPush = null;
  }
}
