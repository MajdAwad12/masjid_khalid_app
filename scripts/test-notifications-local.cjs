'use strict';
// No Firebase credentials or real network calls. Runs against in-memory mocks.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const Module = require('node:module');
const root = path.join(__dirname, '..', 'functions');
const originalLoad = Module._load;
const delivered = [];
let failNext = false;
class HttpsError extends Error {constructor(code, message){super(message);this.code=code;}}
class Timestamp {constructor(ms){this.ms=ms;}toMillis(){return this.ms;}static fromMillis(ms){return new Timestamp(ms);}}
const mocks = {
  'firebase-functions/v2/https': {onCall:(opts,handle)=>({opts,handle}),HttpsError},
  'firebase-functions/v2/firestore': {
    onDocumentDeleted:(opts,handle)=>({opts,handle}),
    onDocumentWritten:(opts,handle)=>({opts,handle}),
  },
  'firebase-admin/firestore': {FieldValue:{serverTimestamp:()=>({time:'now'})},Timestamp},
  'firebase-admin/messaging': {getMessaging:()=>({send:async(msg)=>{
    if(failNext){failNext=false; const err=new Error('simulated transport');err.code='messaging/server-unavailable';throw err;}
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
  ref(name,id){return {id, name, db:this, update:async(data)=>{Object.assign(this.table(name).get(id),data);}};}
  snapshot(name,id){const value=this.table(name).get(id);return {
    exists:value!==undefined,id,ref:this.ref(name,id),get:(key)=>value?.[key],
    data:()=>value?{...value}:undefined,
  };}
  collection(name){return {
    doc:(id)=>this.ref(name,id),
    where:(field,op,value)=>({limit:()=>({get:async()=>({docs:[...this.table(name)].filter(([,v])=>v[field]===value)
      .map(([id])=>this.snapshot(name,id))})})}),
  };}
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
  db.table(collection).set(id,{[itemId]:'C12345678901',deviceKeyHash:secret,
    status:'accepted',decidedBy:'admin',notificationState:'no-token',fcmToken:null,
    fullName:'Test Participant',activityTitle:'Trip',courseTitle:'Course'});
  const make=isCourse?courses.makeCourseFunctions:activities.makeActivityFunctions;
  const functions=make({db,requireAdmin:async()=> 'admin'});
  const fn=isCourse?functions.syncCourseDeviceToken: functions.syncActivityDeviceToken;
  const data=isCourse?{deviceKey,fcmToken:token}:{deviceKey,fcmToken:token};
  let result=await fn.handle({data});
  assert.equal(result.updated,1);
  assert.equal(result.recovered,1);
  assert.equal(db.snapshot(collection,id).get('notificationState'),'sent');
  assert.equal(delivered.at(-1).data.type,isCourse?'course_decision':'activity_decision');
  assert.equal(delivered.at(-1).token,token);
  const before=delivered.length;
  result=await fn.handle({data});
  assert.equal(result.recovered,0);
  assert.equal(delivered.length,before,`${kind} repeated sync must not resend`);

  // A transient FCM error is retried on the next successful token sync.
  Object.assign(db.table(collection).get(id),{status:'rejected',decidedBy:'admin',
    notificationState:'failed',fcmToken:oldToken});
  failNext=true;
  result=await fn.handle({data});
  assert.equal(result.recovered,0);
  assert.equal(db.snapshot(collection,id).get('notificationState'),'failed');
  result=await fn.handle({data});
  assert.equal(result.recovered,1);
  assert.equal(delivered.at(-1).data.status,'rejected');

  // Automatic acceptance is shown immediately in the registration dialog;
  // don't send an old acceptance push when the user next opens the app.
  Object.assign(db.table(collection).get(id),{notificationState:'no-token',
    decidedBy:'automatic'});
  const noExtra=delivered.length;
  result=await fn.handle({data});
  assert.equal(result.recovered,0);
  assert.equal(delivered.length,noExtra);
  console.log(`PASS ${kind}: late token, idempotency, failed send retry, automatic decision excluded`);
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
  console.log('PASS public: 4 triggers, dedupe, transient retries, permanent failure');
}
(async()=>{await testDecisionRecovery('course');await testDecisionRecovery('activity');await testPublic();
  console.log('PASS: all notification logic mocks (no real Firebase or device delivery).');
})().catch(e=>{console.error(e);process.exitCode=1;});
