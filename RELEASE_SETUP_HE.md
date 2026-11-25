# מדריך הכנה לפרסום — 25.11.2026

להפצה עם OTA, ל־Open Testing ול־TestFlight יש להשתמש במדריך [PRODUCTION.MD](PRODUCTION.MD). הפקודה הוותיקה `prepare-android-release.ps1` בהמשך בונה חבילה רגילה ללא Shorebird.

## שינויים בחבילת התיקונים

- Android Release אינו משתמש עוד ב־Debug signing. נוספה תצורה ל־`android/key.properties` מקומי (הקובץ הסודי עצמו לא נכלל).
- נוסף אימות תפקיד מנהל פעיל לכללי Storage בנוסף ל־custom claim. **אין לפרוס ללא בדיקות אמולטור והרשאות שירות**.
- נוספה תמיכה בערבית כ־locale של Flutter והוספו Flutter Localizations. `flutter pub get` יעדכן תלויות ו־pubspec.lock.
- בוצע שינוי בקוד FCM כדי להמתין לזמינות APNs באייפון; עדיין חייבים להגדיר APNs Key ב־Firebase ולבדוק במכשיר אמיתי.
- נוספו קובצי iOS Entitlements למצב Debug/Release והופעל Remote Notifications background mode. עדיין צריך להגדיר Apple Team, Capability ו־Provisioning Profile אמיתיים ב־Xcode.
- אייקוני Android/iOS הוחלפו באייקונים שנגזרו מהלוגו שהיה כבר בפרויקט; נוספה תמונת Play Store ב־`release-assets/play_icon_512.png`.
- שם האפליקציה בפלטפורמות שונה לערבית.
- נוספה אפשרות להגדיר מדיניות פרטיות ופרטי תמיכה בשלב הבנייה באמצעות `--dart-define`; כשאין URL תקין לא יוצג קישור מדיניות פרטיות.
- עודכן טסט אינטגרציה לאמולטור למודל המנהלים הנוכחי (`scripts/test-firebase-local.cjs`). נוסף גם `node scripts/release-smoke.cjs` — **בדיקת מבנה בלבד**.

## 1. התקנה (Windows)

1. שמור גיבוי (`git add .; git commit -m 'Before release fixes'`) *או* העתק את תיקיית הפרויקט.
2. פתח PowerShell בשורש הפרויקט וחלץ את קובץ התיקונים אל התיקייה הקיימת (`Expand-Archive ... -Force`).
3. הרץ:

```powershell
flutter pub get
flutter analyze
flutter test
node scripts/release-smoke.cjs
```

## 2. חתימה אמיתית ל־Android

ליצור upload key במחשב שלך בלבד באמצעות `keytool`, לשמור אותו במקום פרטי וליצור את `android/key.properties` לפי `android/key.properties.example` (לא להשאיר בו ערכי דמה!). **לא** להעלות מפתחות חתימה או סיסמאות לצ'אט או ל־GitHub.

## 3. פרטי תמיכה ומדיניות פרטיות

חובה לפרסם באתר HTTPS אמיתי מדיניות פרטיות התואמת לנתונים שנאספים ולצרף קישור בחנויות. מלא את הערכים *האמתיים* בסביבת PowerShell המקומית:

```powershell
$env:SUPPORT_MANAGER_NAME='PUT_ACTUAL_NAME_HERE'
$env:SUPPORT_MANAGER_PHONE='PUT_ACTUAL_PHONE_HERE'
$env:PRIVACY_POLICY_URL='https://your-real-domain.example/privacy'
```

אל תשתמש בערכי הדוגמה לפרסום. לאחר מכן:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare-android-release.ps1
```

## 4. Firebase Rules — מחייב פריסה נפרדת

`storage.rules` מקומי אינו משפיע על Firebase בענן עד לפריסה מפורשת. ראשית לבצע בדיקות קריאה והעלאה עם משתמש מנהל חי ובעל הרשאה מבוטלת מול Emulator Suite. ברגע שהדמיית ההרשאות עובדת, לפרוס עם `firebase deploy --only storage` אחרי גיבוי חוקים קיימים. כלל משולב Firestore דורש הפעלת Firebase Rules cross-service IAM permission, לפי Firebase documentation.

## 5. iOS — Mac + Apple Developer

הגדרת Entitlements בקוד **אינה מחליפה** הפעלת Push Notifications capability ב־Apple Developer portal וב־Runner > Signing & Capabilities ב־Xcode. ודא של־Bundle ID יש Push, שה־APNs key הוזן ב־Firebase ושחתימת Release ו־TestFlight פועלות. בדוק iPhone אמיתי, כולל קבלת עדכונים ברקע. אין להריץ `flutter build ipa` ב־Windows — נדרש Mac עם Xcode.

## 6. מה עדיין לא אומת

לא ניתן היה להריץ בסביבת יצירת ה־ZIP בדיקות Flutter, בניית AAB/IPA, Firebase Emulator Suite, Apple signing או שליחת Push אמיתית. אין להתחייב לשחרור עד שעוברים `flutter analyze`, `flutter test`, בניית AAB, TestFlight, בדיקות מכשיר וסקירת Apple/Google. בורר תאריך, לוגיקת תוכן, הרשאות שירות בפועל, בקשות מחיקת מידע, ומסמכי החנויות עדיין דורשים QA ופרטי מדיניות אמיתיים.

## 7. בדיקות פונקציות מול אמולטורים

לאחר `cd functions; npm ci; cd ..` והפעלת Firebase Emulator Suite, אפשר להריץ `node scripts/test-firebase-local.cjs`. הבדיקה הזו כותבת **רק** לאמולטורים המקומיים ובודקת יצירת מנהל, השבתת מנהל, גישה למידע וחסימת טוקן ישן. היא לא נבדקה בסביבת יצירת ה־ZIP כי אין פה Firebase CLI. לא להפעיל מול production.

## 8. פונקציית מייל פיתוח

הוסרה הפונקציה `sendRecoveryTestEmail` כי הקוד סימן אותה בעצמו כפונקציית בדיקה זמנית שלא צריכה להגיע לפרסום. בפריסה הבאה של Cloud Functions יש לוודא שהפריסה אכן מסירה אותה מהמיזם, ושפונקציות האיפוס ושחזור המנהלים ממשיכות לעבוד.
