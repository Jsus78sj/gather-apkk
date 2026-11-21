/// Arabic number agreement for counted nouns (1 / 2 / 3-10 / 11+).
String arabicCount(
  int n, {
  required String one,
  required String two,
  required String few,
  required String many,
}) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  return '$n $many';
}

String arabicItems(int n) => arabicCount(
      n,
      one: 'عنصر واحد',
      two: 'عنصران',
      few: 'عناصر',
      many: 'عنصراً',
    );

String arabicFiles(int n) => arabicCount(
      n,
      one: 'ملف واحد',
      two: 'ملفان',
      few: 'ملفات',
      many: 'ملفاً',
    );

String arabicFolders(int n) => arabicCount(
      n,
      one: 'مجلد واحد',
      two: 'مجلدان',
      few: 'مجلدات',
      many: 'مجلداً',
    );
