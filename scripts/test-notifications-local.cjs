'use strict';
// No Firebase credentials or real network calls. Runs against in-memory mocks.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const Module = require('node:module');
const root = path.join(__dirname, '..', 'functions');
const originalLoad = Module._load;
const delivered = [];
let failNext = null;
let duringSend = null;
class HttpsError extends Error {constructor(code, message){super(message);this.code=code;}}
class Timestamp {constructor(ms){this.ms=ms;}toMillis(){return this.ms;}static fromMillis(ms){return new Timestamp(ms);}}
const mocks = {
  'firebase-functions/v2/https': {onCall:(opts,handle)=>({opts,handle}),HttpsError},
  'firebase-functions/v2/firestore': {
    onDocumentCreated:(opts,handle)=>({opts,handle}),
    onDocumentUpdated:(opts,handle)=>({opts,handle}),
    onDocumentDeleted:(opts,handle)=>({opts,handle}),
    onDocumentWritten:(opts,handle)=>({opts,handle}),
  },
  'firebase-admin/firestore': {FieldPath:{documentId:()=>'__name__'},FieldValue:{serverTimestamp:()=>({time:'now'})},Timestamp},
  'firebase-admin/messaging': {getMessaging:()=>({send:async(msg)=>{
    if(duringSend){const action=duringSend;duringSend=null;await action();}
    if(failNext){const err=new Error('simulated transport');err.code=failNext;failNext=null;throw err;}
    delivered.push(msg);return `fake-message-${delivered.length}`;
  }})},
  './deletion_cleanup': {deleteLinkedRegistrations:async()=>0},
  'firebase-admin/storage': {getStorage:()=>({bucket:()=>({})})},
  'firebase-functions/logger': {info:()=>{},error:()=>{},warn:()=>{}},
};
Module._load=function(name,parent,isMain){if(mocks[name])return mocks[name];return originalLoad.apply(this,arguments);};
const courses = require(path.join(root,'courses.js'));
const activities = require(path.join(root,'activities.js'));
const publicPush = require(path.join(root,'public_notifications.js'));
Module._load=originalLoad;

class Database {
  constructor(){this.tables = new Map();}
  table(name){if(!this.tables.has(name))this.tables.set(name,new Map());return this.tables.get(name);}
  ref(name,id){return {id, name, db:this, get:async()=>this.snapshot(name,id), update:async(data)=>{Object.assign(this.table(name).get(id),data);}};}
  snapshot(name,id){const value=this.table(name).get(id);return {
    exists:value!==undefined,id,ref:this.ref(name,id),get:(key)=>value?.[key],
    data:()=>value?{...value}:undefined,
  };}
  collection(name){
    const filters=[];
    let cursor='', size=Infinity;
    const query={
      doc:id=>this.ref(name,id),
      where(field,op,value){assert.equal(op,'==');filters.push([field,value]);return query;},
      orderBy(){return query;},
      startAfter(id){cursor=id;return query;},
      limit(n){size=n;return query;},
      get:async()=>({docs:[...this.table(name)].sort(([a],[b])=>a.localeCompare(b))
        .filter(([id,row])=>id>cursor&&filters.every(([f,v])=>row[f]===v))
        .slice(0,size).map(([id])=>this.snapshot(name,id))}),
    };
    return query;
  }
  batch(){const actions=[];return {update:(ref,values)=>actions.push([ref,values]),
    commit:async()=>{for(const [ref,values] of actions)Object.assign(this.table(ref.name).get(ref.id),values);}};}
  async runTransaction(fn){const tx={
    get:async(ref)=>this.snapshot(ref.name,ref.id),
    update:(ref,values)=>Object.assign(this.table(ref.name).get(ref.id),values),
    create:(ref,values)=>this.table(ref.name).set(ref.id,{...values}),
  };return fn(tx);}
}

async function testDecisionRecovery(kind){
  const db = new Database();
  const deviceKey='a'.repeat(64);
  const token='FCM_TOKEN_'+'T'.repeat(40);
  const oldToken='OLD_TOKEN_'+'X'.repeat(40);
  const hash=(s)=>crypto.createHash('sha256').update(s).digest('hex');
  const isCourse=kind==='course';
  const collection=isCourse?'course_registrations':'activity_registrations';
  const itemId=isCourse?'courseId':'activityId';
  const secret=hash(isCourse?`course-device\0${deviceKey}`:`activity-installation\0${deviceKey}`);
  const id='b'.repeat(64);
  db.table(collection).set(id,{[itemId]:'C12345678901',deviceKeyHash:secret,deviceVerified:true,
    status:'accepted',decidedBy:'admin',notificationState:'no-token',fcmToken:null,
    fullName:'Test Participant',activityTitle:'Trip',courseTitle:'Course'});
  const make=isCourse?courses.makeCourseFunctions:activities.makeActivityFunctions;
  const functions=make({db,requireAdmin:async()=> 'admin'});
  const fn=isCourse?functions.syncCourseDeviceToken: functions.syncActivityDeviceToken;
  const data=isCourse?{deviceKey,fcmToken:token}:{deviceKey,fcmToken:token};
  let result=await fn.handle({data});
  assert.deepEqual(result,{synced:true});
  assert.equal(db.snapshot(collection,id).get('notificationState'),'sent');
  assert.deepEqual(delivered.at(-1).data,{type:'registration_update'});
  assert.deepEqual(delivered.at(-1).notification,{title:'لديك تحديث جديد',body:'افتح التطبيق للاطلاع على التحديث.'});
  assert.equal(delivered.at(-1).token,token);
  const before=delivered.length;
  result=await fn.handle({data});
  assert.deepEqual(result,{synced:true});
  assert.equal(delivered.length,before,`${kind} repeated sync must not resend`);

  // A transient FCM error is retried on the next successful token sync.
  Object.assign(db.table(collection).get(id),{status:'rejected',decidedBy:'admin',
    notificationState:'failed',fcmToken:oldToken});
  failNext='messaging/server-unavailable';
  result=await fn.handle({data});
  assert.deepEqual(result,{synced:true});
  assert.equal(db.snapshot(collection,id).get('notificationState'),'failed');
  result=await fn.handle({data});
  assert.deepEqual(result,{synced:true});
  assert.deepEqual(delivered.at(-1).data,{type:'registration_update'});

  const row=db.table(collection).get(id);
  Object.assign(row,{notificationState:'ready',notificationAttempts:0,deviceVerified:false});
  const hidden=delivered.length;
  await fn.handle({data});
  assert.equal(delivered.length,hidden+1);
  Object.assign(row,{notificationState:'ready',notificationAttempts:0});
  failNext='messaging/registration-token-not-registered';
  await fn.handle({data});
  assert.equal(row.fcmToken,null);
  await fn.handle({data});
  assert.equal(row.fcmToken,null,'invalidated token must stay cleared');
  await fn.handle({data:{deviceKey,fcmToken:oldToken}});
  assert.equal(row.notificationState,'sent');
  Object.assign(row,{notificationState:'reserved',notificationStartedMs:1,notificationAttempts:1});
  await fn.handle({data:{deviceKey,fcmToken:oldToken}});
  assert.equal(row.notificationState,'sent','expired pre-dispatch reservation recovers');
  Object.assign(row,{notificationState:'sending',notificationStartedMs:1});
  const uncertain=delivered.length;
  await fn.handle({data});
  assert.equal(row.notificationState,'uncertain');
  assert.equal(delivered.length,uncertain);
  Object.assign(row,{notificationState:'ready',notificationAttempts:0});
  for(let i=0;i<4;i++){
    failNext='messaging/server-unavailable';
    await fn.handle({data});
  }
  failNext=null;
  assert.equal(row.notificationAttempts,3);
  assert.equal(delivered.length,uncertain);
  Object.assign(row,{notificationState:'ready',notificationAttempts:0,fcmToken:oldToken});
  const worker=isCourse?functions.recoverCourseDecisionDelivery:functions.recoverActivityDecisionDelivery;
  const event={data:{after:db.snapshot(collection,id)}};
  const beforeWorker=delivered.length;
  await worker.handle(event);
  await worker.handle(event);
  assert.equal(delivered.length,beforeWorker+1,'interrupted callable and replay share one completed decision');
  // Historical automatic decisions are never replayed on upgrade.
  Object.assign(db.table(collection).get(id),{notificationState:'no-token',
    decidedBy:'automatic'});
  const noExtra=delivered.length;
  result=await fn.handle({data});
  assert.deepEqual(result,{synced:true});
  assert.equal(delivered.length,noExtra);
  const created=isCourse?functions.notifyAutomaticCourseDecision:functions.notifyAutomaticActivityDecision;
  Object.assign(row,{notifyAutomatic:true,status:"accepted",notificationState:"ready",notificationAttempts:0});
  await created.handle({data:db.snapshot(collection,id)});
  await created.handle({data:db.snapshot(collection,id)});
  assert.equal(delivered.length,noExtra+1);
  assert.equal(delivered.at(-1).token,oldToken,'previously invalid token stays suppressed');
  assert.deepEqual(delivered.at(-1).data,{type:"registration_update"});
  const rotated="ROTATED_TOKEN_"+"R".repeat(40);
  Object.assign(row,{notificationState:"ready",notificationAttempts:0});
  duringSend=()=>fn.handle({data:{deviceKey,fcmToken:rotated}});
  failNext="messaging/invalid-registration-token";
  await fn.handle({data:{deviceKey,fcmToken:oldToken}});
  assert.equal(row.fcmToken,rotated);
  assert.equal(row.notificationState,"ready","rotation survives in-flight invalidation");
  await worker.handle(event);
  await worker.handle(event);
  assert.equal(delivered.at(-1).token,rotated);
  assert.equal(delivered.length,noExtra+2);
  console.log(`PASS ${kind}: generic payload, preverification and automatic delivery, rotation, invalidation, bounded retries, interrupted sends and deduplication`);
}

async function testPublic(){
  const db=new Database();
  const fns=publicPush.makePublicNotificationFunctions({db});
  assert.equal(Object.keys(fns).length,4);
  for(const [name,kind] of Object.entries({notifyNewAnnouncement:'announcements',notifyNewCourse:'courses',
      notifyNewActivity:'activities',notifyNewHomework:'homework'})){
    const f=fns[name];
    assert.equal(f.opts.document,`${kind}/{itemId}`);
    assert.equal(f.opts.region,'us-central1');
    const record={title:`Test ${kind}`,isVisible:true};
    const event={params:{itemId:'T12345678901'},data:{before:{exists:false},
      after:{exists:true,data:()=>record}}};
    const before=delivered.length;
    await f.handle(event);
    assert.equal(delivered.length,before+1);
    assert.equal(delivered.at(-1).topic,publicPush.PUBLIC_TOPIC);
    await f.handle(event);
    assert.equal(delivered.length,before+1,'duplicate event should not re-send');
  }
  let attempts=0;
  const transientSend=async()=>{
    attempts++;
    if(attempts<3){const e=new Error('temporary failure');e.code='messaging/server-unavailable';throw e;}
    return 'recovered-message-id';
  };
  const recovered=await publicPush.publishOnce(db,'announcements','RETRY12345678',
    {title:'Retry test'},transientSend);
  assert.equal(recovered,true);
  assert.equal(attempts,3);
  assert.equal(db.snapshot('security_public_notification_deliveries',
    'announcements_RETRY12345678').get('state'),'sent');
  let permanentAttempts=0;
  const permanentFailure=async()=>{
    permanentAttempts++;
    const e=new Error('invalid argument');e.code='messaging/invalid-argument';throw e;
  };
  const permanent=await publicPush.publishOnce(db,'announcements','BAD12345678',
    {title:'Invalid test'},permanentFailure);
  assert.equal(permanent,false);
  assert.equal(permanentAttempts,1);
  assert.equal(db.snapshot('security_public_notification_deliveries',
    'announcements_BAD12345678').get('state'),'failed');
  const ledger=db.table('security_public_notification_deliveries');
  ledger.set('courses_interrupted',{state:'reserved',leaseUntil:0,attempts:1});
  assert.equal(await publicPush.publishOnce(db,'courses','interrupted',{title:'A'},async()=>'ok'),true);
  ledger.set('courses_unknown',{state:'dispatching',leaseUntil:0});
  assert.equal(await publicPush.publishOnce(db,'courses','unknown',{title:'A'},async()=>assert.fail()),false);
  assert.equal(ledger.get('courses_unknown').state,'uncertain');
  console.log('PASS public: 4 triggers, dedupe, transient retries, permanent failure');
}
(async()=>{await testDecisionRecovery('course');await testDecisionRecovery('activity');await testPublic();
  console.log('PASS: all notification logic mocks (no real Firebase or device delivery).');
})().catch(e=>{console.error(e);process.exitCode=1;});
