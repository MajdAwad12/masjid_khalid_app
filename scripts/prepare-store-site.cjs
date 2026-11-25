'use strict';

const fs = require('node:fs');
const path = require('node:path');
const project = path.resolve(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(project, 'store-config.json'), 'utf8').replace(/^\uFEFF/, ''));
const name = config.SUPPORT_MANAGER_NAME?.trim();
const phone = config.SUPPORT_MANAGER_PHONE?.trim();
const email = config.SUPPORT_EMAIL?.trim();
if (!name || !/^[+\d][\d ()-]{6,24}$/.test(phone ?? '') ||
    !/^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(email ?? '')) {
  throw new Error('Enter the approved public operator name, telephone and support email in store-config.json.');
}
const policy = new URL(config.PRIVACY_POLICY_URL);
if (policy.protocol !== 'https:' || policy.pathname !== '/privacy' || policy.search || policy.hash ||
    policy.username || policy.password || /(^|\.)(localhost|example|invalid|test|example\.com|example\.org)$/.test(policy.hostname)) {
  throw new Error('PRIVACY_POLICY_URL must be the public HTTPS /privacy address.');
}
const escape = text => text.replace(/[&<>"']/g, ch => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[ch]);
const legal = key => fs.readFileSync(path.join(project, 'assets/legal', key + '-ar.txt'), 'utf8');
const pages = {
  privacy: ['سياسة الخصوصية', legal('privacy')],
  terms: ['شروط الاستخدام', legal('terms')],
  support: ['الدعم والمساعدة', 'للاستفسار عن التطبيق أو الإبلاغ عن خطأ أو محتوى، تواصل مع إدارة المسجد.'],
  delete: ['طلب حذف الحساب أو بيانات التسجيل', 'للمسؤول: افتح الإعدادات واختر «حذف حسابي نهائياً»، ثم أكّد بكلمة المرور. تُزال صلاحية الإدارة ويُحذف حساب الدخول وبيانات الاسترداد. تبقى منشورات المسجد وسجلاته التشغيلية وفق سياسة الخصوصية.\n\nللزائر أو لمن فقد الوصول إلى الحساب: أرسل طلب الحذف إلى البريد أدناه مع اسم البرنامج ووسيلة للرد، أو اسم المستخدم إذا كان الطلب لحساب مسؤول. تتحقق الإدارة من هويتك وصلاحيتك للتصرف عن المشارك قبل محو سجله الفردي. اذكر بوضوح إن كنت تريد الانسحاب فقط أو محو بيانات التسجيل. الانسحاب أو الرفض لا يمحو السجل. لا ترسل كلمة مرور أو رمز تحقق.'],
};
const directory = path.join(project, 'build/store-site');
fs.mkdirSync(directory, {recursive: true});
for (const [slug, [title, body]] of Object.entries(pages)) {
  const paragraphs = body.trim().split(/\r?\n\s*\r?\n/).map(p => '<p>' + escape(p) + '</p>').join('\n');
  const links = Object.entries(pages).map(([key, [label]]) => '<a href="/' + key + '">' + label + '</a>').join(' · ');
  const html = `<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} | مسجد خالد بن الوليد</title><style>body{max-width:44rem;margin:4rem auto;padding:0 1.3rem;background:#faf8f2;color:#222d27;font:1.15rem/1.85 system-ui}nav{margin:2rem 0}a{color:#175545}address{font-style:normal}h1{line-height:1.35}</style>
<header>مسجد خالد بن الوليد</header><main><h1>${title}</h1>${paragraphs}
<address>${escape(name)}<br><a dir="ltr" href="mailto:${escape(email)}">${escape(email)}</a><br><a dir="ltr" href="tel:${phone.replace(/[^+\d]/g, '')}">${escape(phone)}</a></address></main><nav>${links}</nav></html>`;
  fs.writeFileSync(path.join(directory, slug + '.html'), html);
  if (slug === 'support') fs.writeFileSync(path.join(directory, 'index.html'), html);
}
console.log('Prepared public Arabic privacy, terms, support and deletion pages.');
