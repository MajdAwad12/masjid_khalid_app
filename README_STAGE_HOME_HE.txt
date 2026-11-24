שלב מסך הבית — עדכון מדויק לגרסת folder(1).zip

שינויים:
• כלי ניקוי המנהלים הזמני הוסר ממסך המנהלים, AdminService וקוד Functions המקומי.
• כרטיסיית הפסוק קוראת עכשיו מ-app_settings/home ב-Firestore עם ברירת מחדל לפסוק הישן אם המסמך לא קיים.
• רק מנהל מחובר יכול לערוך כותרת, טקסט, מקור ולהסתיר או להציג את הכרטיסייה.
• הכללים החדשים נותנים קריאת מסמך home לכולם, וכתיבה רק למנהלים בעלי Custom Claim וגם role=admin.

הוראות על מחשב Windows (PowerShell בתיקיית הפרויקט):
1. בדוק שאתה בענף redesign-public-app באמצעות git branch --show-current
2. חלץ את קובץ התיקון אל שורש הפרויקט:
   Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\masjid_home_card_patch.zip" -DestinationPath . -Force
3. הרץ:
   dart format lib
   flutter analyze
   cd functions
   npm run lint
   cd ..
4. אם הכול תקין, פרוס רק את חוקי Firestore:
   firebase deploy --project masjid-khalid-app --only firestore:rules
5. הרץ Android Emulator ובדוק: משתמש ציבורי רואה את הפסוק; מנהל יכול לערוך/להסתיר/להחזיר; התחברות והתנתקות עדיין תקינות.
6. רק אחרי אימות, הסר מ-Firebase את פונקציית התחזוקה שכבר לא קיימת בקוד:
   firebase functions:delete normalizeAdminProfiles --region us-central1 --project masjid-khalid-app
   (הפקודה מוחקת את פונקציית התחזוקה בלבד, לא את הנתונים. קרא את הודעת האישור.)

חשוב: תיקון זה אינו יוצר/מוחק חשבונות, מסמכים קיימים או תמונות.
לא שינינו את נתוני Firebase החיים. אין אפשרות לבדוק כאן flutter analyze או להריץ Android; הבדיקות במחשב שלך נדרשות.
