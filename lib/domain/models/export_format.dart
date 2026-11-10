/// The file type an export is written as.
///
/// A model of its own, rather than living beside the export settings, because
/// two different things speak it: the settings say what the app *writes*, and
/// every store target says what its console *accepts* (see `StoreRules`). One
/// vocabulary for both is what lets the export checker compare them directly.
enum ExportFormat {
  png('PNG', 'png', 'image/png'),
  jpg('JPG', 'jpg', 'image/jpeg');

  const ExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}
