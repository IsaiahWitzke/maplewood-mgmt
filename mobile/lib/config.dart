class AppConfig {
  static const driveFolderName = 'Maplewood Receipts';
  static const sheetName = 'Receipts';

  static const scopes = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/generative-language.retriever',
  ];
}
