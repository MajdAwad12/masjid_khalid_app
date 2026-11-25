# תיקוני אמינות התראות – مسجد خالد بن الوليد

תאריך: 25.11.2026. חבילת PATCH למיזוג בשורש הפרויקט הקיים, **לא פרויקט Flutter חדש**.

## מה הקבצים משנים

- `lib/services/public_notifications_service.dart`: משחזר מנוי ל-FCM Topic אחרי עיכוב APNs, חידוש טוקן, יציאה/חזרה לאפליקציה או ניתוק רשת. בקשת ההסרה מהמנוי נשמרת ומנוסה שוב אם נכשלה. ב-iOS תצוגת התראה כשהאפליקציה בחזית; ב-Android הודעה בתוך האפליקציה כשהיא בחזית.
- `lib/services/course_notifications_service.dart`: סנכרון טוקנים לקורסים ולפעילויות בהפעלה, בחזרה מהגדרות מכשיר ובשינוי טוקן, עם עד שישה ניסיונות חוזרים. ללא חשבון למשתמש הציבורי.
- `functions/courses.js` ו-`functions/activities.js`: אם המנהל אישר/דחה בזמן שלא היה למכשיר FCM token, הניסיון הבא לסנכרן את הטוקן ינסה לשלוח את ההחלטה שחיכתה. בדיקות טרנזקציה מונעות ניסיונות שליחה כפולים מסנכרון בו-זמני. שליחה שנכשלה ניתנת לניסיון חוזר בסנכרון הבא. קבלה אוטומטית בזמן ההרשמה אינה מייצרת התראת Push ישנה.
- `functions/public_notifications.js`: ניסיון שליחה חוזר קצר (עד 3 ניסיונות כוללים) רק בשגיאות FCM זמניות ידועות; לא נוצר Scheduler חדש ולא משתנה אזור הפריסה.
- `scripts/test-notifications-local.cjs`: בדיקת שרת מדומה שאינה פונה ל-Firebase חי.

**לא שונו** מסכי האפליקציה, עיצוב כרטיסיות, מסד הנתונים, אוסף המשתמשים, פרטי הרשמות קיימות, או כללי האבטחה.
**לא שונתה** תצורת אזורי Cloud Functions. לפני שינוי אזור יש לבדוק את מיקום Firestore ולבצע הגירה נפרדת ובטוחה.

## גיבוי ומיזוג (PowerShell מתוך C:\development\projects\masjid_khalid_app)

1. בצע commit או העתקה מלאה של התיקייה כגיבוי. להימנע ממיזוג לתוך פרויקט שונה מהפרויקט שנבדק.
2. הורד `masjid_push_notifications_PATCH.zip` אל Downloads.
3. בדוק שהקובץ נמצא: `Test-Path "$env:USERPROFILE\Downloads\masjid_push_notifications_PATCH.zip"`
4. חלץ: `Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\masjid_push_notifications_PATCH.zip" -DestinationPath . -Force`

## בדיקות הקוד במחשב

```powershell
flutter pub get
flutter analyze
flutter test
node .\scripts\test-notifications-local.cjs
flutter run
```

אם `flutter analyze` נכשל — אל תפרוס פונקציות; שלח את השגיאות.

## פריסה ל-Firebase (לאחר בדיקות תקינות)

```powershell
firebase use
firebase firestore:databases:list
firebase deploy --only "functions:syncCourseDeviceToken,functions:syncActivityDeviceToken,functions:notifyNewAnnouncement,functions:notifyNewCourse,functions:notifyNewActivity,functions:notifyNewHomework"
```

שתי פונקציות סנכרון הטוקנים וארבע פונקציות הפרסום עודכנו בצד השרת. כולן נכללות בפקודת הפריסה. אם הכלי מציע למחוק פונקציות אחרות או להעביר אזור — **עצור לפני אישור** ובדוק את הפלט.

## דברים הכרחיים מחוץ ל-ZIP

- ב-Apple Developer להפעיל Push Notifications עבור Bundle ID המלא של האפליקציה.
- ב-Xcode להפעיל Signing & Capabilities > Push Notifications ו-Background Modes > Remote notifications; לאמת שהחתימה וה-Provisioning מתאימים ל-Debug/Release.
- ב-Firebase Console > Project Settings > Cloud Messaging להעלות מפתח APNs תקין (`.p8`, Key ID, Team ID). **אין לשתף את המפתח בשיחה או לכלול אותו ב-ZIP**.
- לבקש אישור התראות במכשיר. ב-iOS מומלץ לבדוק על iPhone פיזי וב-Android על מכשיר פיזי עם Android 13 ומעלה.
- לבצע בדיקת קורס/טיול עם בקשת אישור ודחייה, בדיקת פרסום חדש בארבע הקטגוריות, בדיקה כשהאפליקציה פתוחה/ברקע/סגורה, וכיבוי/הדלקת התראות בהגדרות.
- כאשר משתמש מבטל הרשאות במערכת ההפעלה, הוא לא יקבל התראות גם אם מסומן רצון לקבל באפליקציה; כל אחת מהפלטפורמות שולטת במסירה.

## מגבלות שיש לדעת

- ב-Android כשהאפליקציה **פתוחה** מוצגת `SnackBar` בתוך האפליקציה; אין כרגע Android OS notification נפרד בחזית. ברקע/סגורה FCM מטפלת בתצוגת התראה לפי הרשאות המכשיר.
- ב-iOS בזמן שהאפליקציה פתוחה, הקוד מבקש תצוגת התראות המערכת דרך Firebase Messaging.
- FCM/APNs אינם מבטיחים מסירה של 100% לכל מכשיר; לכן נשארה בדיקת סטטוס הרשמה בתוך האפליקציה.
- בדיקת Node המקומית היא עם mocks; **לא** בוצעה קומפילציית Flutter, פריסה חיה, או בדיקה במכשיר אמיתי בסביבת הכנת ZIP זו.
- אם Cloud Function סיימה לשלוח אך העדכון ל-Firestore נכשל, יכולה להיות התראה כפולה אחרי ניסיון חוזר. טרנזקציות מונעות כפילויות שמקורן בסנכרון במקביל, אך FCM הוא best-effort.
