'use strict';

// Called by the admin lifecycle suite after verifying all three local emulators.
const assert = require('node:assert/strict');
const {randomBytes, createHash} = require('node:crypto');

async function testRegistrationPrivacy({db, call, token, apiRoot}) {
  assert.equal(new URL(apiRoot).hostname, '127.0.0.1');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  const key = randomBytes(32).toString('hex');
  const other = randomBytes(32).toString('hex');
  for (const [kind, parents] of [['Course','courses'],['Activity','activities']]) {
    const lower = kind.toLowerCase(), field = lower+'Id';
    const program = db.collection(parents).doc();
    const roster = db.collection(lower+'_registrations');
    const data = {[field]:program.id,fullName:'Synthetic Participant',
      phone:'0000000000',deviceKey:key};
    const submit = async input => {
      const name='registerFor'+kind;
      const response=await call(name,input);
      // The Windows emulator can forward HTTP over a named pipe, with no peer
      // IP. Verify that transport fails closed, then exercise the same real
      // callable handler against emulator Firestore with a loopback peer.
      if(response.status!==503 || !['Unable to verify request origin.',
        'Cannot verify request source.'].includes(response.body.error?.message)) return response;
      const factory=require('../functions/'+parents)['make'+kind+'Functions'];
      const handler=factory({db,requireAdmin:()=>assert.fail('public registration path')})[name];
      try {
        return {status:200,body:{result:await handler.run({data:input,rawRequest:{ip:'127.0.0.1'}})}};
      } catch(error) {
        if(!error.httpErrorCode) throw error;
        return {status:error.httpErrorCode.status,body:{error:{message:error.message}}};
      }
    };
    const manage = (args,auth=token) => call('manage'+kind+'Registration',
      {[field]:program.id,...args},auth);
    const lookup = async deviceKey => {
      const response = await call('my'+kind+'Registrations',{deviceKey});
      assert.equal(response.status,200);
      return response.body.result;
    };
    const inventory = db.collection(lower+'_counts').doc(program.id);
    const rosterForProgram = roster.where(field,'==',program.id);
    const rows = () => rosterForProgram.get();
    const counts = async (pending, accepted, rejected) => {
      assert.deepEqual((await inventory.get()).data(), {
        pendingCount:pending, acceptedCount:accepted, rejectedCount:rejected,
      });
    };
    const acceptedResponse = {status:200,body:{result:{status:'submitted'}}};
    const verifyKey = async (ref,deviceKey) => {
      const reference=(await lookup(deviceKey)).reference;
      const operation=await prepare(ref);
      return manage({...operation,action:'verify',reference});
    };
    const prepare = async ref => {
      const args={registrationId:ref.id};
      const response=await manage({...args,action:'prepare'});
      assert.equal(response.status,200);
      return {...args,generation:response.body.result.generation,identityChecked:true};
    };
    const decide=(ref,decision,auth=token)=>call('decide'+kind+'Registration',
      {[field]:program.id,registrationId:ref.id,decision},auth);
    const fresh = () => randomBytes(32).toString('hex');
    const fixture = name => ({...data,fullName:name,deviceKey:fresh()});
    const parentAtStart={title:'',isOpen:true,registrationMode:'automatic',
      capacity:1,acceptedCount:1,pendingCount:0,rejectedCount:0};
    const sync=(deviceKey,fcmToken)=>call('sync'+kind+'DeviceToken',{deviceKey,fcmToken});
    await program.set(parentAtStart);
    try {
      assert.ok((await submit(data)).status>=400,'missing visibility');
      await program.update({isVisible:false});
      assert.ok((await submit(data)).status>=400,'hidden program');
      await program.update({isVisible:true});
      assert.deepEqual(await submit(data),acceptedResponse);
      await counts(0,1,0);
      // A new identity and a replay receive precisely the same response, even full.
      assert.deepEqual(await submit({...data,deviceKey:other}),acceptedResponse);
      assert.deepEqual(await submit(fixture('Different Fixture')),acceptedResponse);
      const original=(await rows()).docs;
      assert.equal(original.length,1);
      const row=original[0].ref;
      assert.equal(original[0].get('status'),'accepted');
      assert.equal(original[0].get('deviceVerified'),false);
      assert.deepEqual((await program.get()).data(),{...parentAtStart,isVisible:true});
      const mine=await lookup(key), foreign=await lookup(other);
      assert.deepEqual(mine.registrations,[]);
      assert.deepEqual(foreign.registrations,[]);
      assert.notEqual(mine.reference,foreign.reference);
      for(const path of [roster.id,roster.id+'/'+row.id,inventory.path,inventory.parent.id]) {
        assert.equal((await fetch(apiRoot+'/'+path)).status,403);
      }
      assert.equal((await fetch(apiRoot+'/'+inventory.path,{
        headers:{Authorization:'Bearer '+token}})).status,200,'verified staff can read live counts');
      for(const path of [row.path,inventory.path]){
        const response=await fetch(apiRoot+'/'+path,{method:'PATCH',
          headers:{'Content-Type':'application/json'},
          body:JSON.stringify({fields:{status:{stringValue:'accepted'}}})});
        assert.equal(response.status,403);
      }
      assert.equal((await manage({registrationId:row.id,action:'prepare'},null)).status,401);
      const operation=await prepare(row);
      assert.ok((await manage({...operation,action:'verify',reference:foreign.reference})).status>=400);
      assert.ok((await manage({...operation,action:'erase',identityChecked:false})).status>=400);
      await program.update({isVisible:false});
      const verify=()=>manage({...operation,action:'verify',reference:mine.reference});
      const checks=await Promise.all([verify(),verify()]);
      assert.equal(checks.filter(x=>x.body.result?.changed).length,1);
      await counts(0,1,0);
      assert.equal((await lookup(key)).registrations[0].status,'accepted');
      assert.deepEqual((await lookup(other)).registrations,[]);
      assert.equal((await manage({...operation,action:'withdraw'})).status,200);
      assert.equal((await lookup(key)).registrations[0].status,'withdrawn');
      await counts(0,0,0);
      assert.equal((await program.get()).get('acceptedCount'),undefined,
        'older clients can submit again after a former full program releases a seat');
      const erase=()=>manage({...operation,action:'erase'});
      await Promise.all([erase(),erase()]).then(out=>
        assert.equal(out.filter(x=>x.body.result?.changed).length,1));

      // Legacy unverified requests retain their status and are counted only on
      // explicit staff verification. Reusing a deleted ID has a new generation.
      await row.set({...original[0].data(),status:'unverified',decidedBy:null,
        notifyAutomatic:false,notificationState:'not-sent'});
      assert.ok((await erase()).status>=400,'stale generation');
      assert.ok((await verifyKey(row,key)).status>=400,'legacy closed verification');
      await program.update({isVisible:true,registrationMode:'approval'});
      assert.equal((await verifyKey(row,key)).status,200);
      await counts(1,0,0);
      const legacyArgs=await prepare(row);
      await manage({...legacyArgs,action:'erase'});
      await counts(0,0,0);

      // Concurrent distinct requests contend for the last seat. Retrying the
      // winner (including from another installation) must not change its owner.
      const contenders=['First Fixture','Second Fixture'].map(fixture);
      const race=await Promise.all(contenders.map(submit));
      race.forEach(result=>assert.deepEqual(result,acceptedResponse));
      await counts(1,0,0);
      let entries=(await rows()).docs;
      assert.equal(entries.length,1);
      const winner=entries[0].ref;
      assert.equal(entries[0].get('status'),'pending');
      const winnerKey=contenders.find(x=>x.fullName===entries[0].get('fullName')).deviceKey;
      assert.deepEqual((await lookup(winnerKey)).registrations,[]);
      assert.equal((await decide(winner,'accepted',null)).status,401);
      assert.equal((await decide(winner,'accepted')).status,200);
      await counts(0,1,0);
      assert.equal((await decide(winner,'rejected')).status,200);
      await counts(0,0,1);
      assert.deepEqual((await lookup(winnerKey)).registrations,[]);
      const replay=contenders.find(x=>x.deviceKey===winnerKey);
      assert.deepEqual(await submit({...replay,deviceKey:fresh()}),acceptedResponse);
      assert.equal((await winner.get()).get('status'),'rejected');
      await counts(0,0,1);
      const next=fixture('Family Participant');
      const twins=await Promise.all([submit(next),submit({...next,deviceKey:fresh()})]);
      twins.forEach(result=>assert.deepEqual(result,acceptedResponse));
      await counts(1,0,1);
      entries=(await rows()).docs;
      assert.equal(entries.length,2);
      const replacement=entries.find(doc=>doc.id!==winner.id).ref;
      assert.equal((await decide(winner,'accepted')).status,429,'full reaccept');
      const staffAdd=await call('adminAdd'+kind+'Participant',{
        [field]:program.id,fullName:'Staff Fixture'},token);
      assert.equal(staffAdd.status,429,'staff cannot overbook');
      await manage({...await prepare(replacement),action:'erase'});
      await counts(0,0,1);
      assert.equal((await winner.get()).exists,true);
      assert.equal((await decide(winner,'accepted')).status,200);
      await counts(0,1,0);
      const beforeVerify=await winner.get();
      assert.equal(beforeVerify.get('deviceVerified'),false);
      assert.equal((await verifyKey(winner,winnerKey)).status,200);
      assert.equal((await lookup(winnerKey)).registrations[0].status,'accepted');
      await inventory.update({acceptedCount:7});
      await manage({...await prepare(winner),action:'erase'});
      await counts(0,0,0);

      // Pre-upgrade occupied seats survive lazy initialization. Seed a previous
      // hour's requests to distinguish the active-seat cap from rate limiting.
      await inventory.delete();
      await program.update({capacity:null});
      const capKey=fresh(), allowance=kind==='Course'?8:10;
      const hash=createHash('sha256').update(
        (kind==='Course'?'course-device':'activity-installation')+'\0'+capKey).digest('hex');
      const seeds=[];
      const batch=db.batch();
      for(let i=0;i<allowance;i++){
        const ref=roster.doc(fresh());
        seeds.push(ref);
        batch.set(ref,{[field]:program.id,deviceKeyHash:hash,deviceVerified:false,
          status:i%2?'accepted':'pending',createdAt:new Date(Date.now()-7200000)});
      }
      await batch.commit();
      const family={...data,deviceKey:capKey,fullName:'Current Fixture'};
      assert.deepEqual(await submit(family),acceptedResponse);
      assert.equal((await rows()).size,allowance,'prior-hour cap holds');
      assert.equal((await verifyKey(seeds[0],capKey)).status,200);
      assert.deepEqual(await submit(family),acceptedResponse);
      await counts(allowance/2+1,allowance/2,0);
      for (let i=2;i<allowance;i++) assert.deepEqual(await submit(family),acceptedResponse);
      assert.equal((await submit(family)).status,429,'hourly limit still applies');
      // No synthetic token may reach FCM: seed terminal sent state or pending.
      const pageBatch=db.batch();
      for(const ref of seeds) pageBatch.delete(ref);
      const pagedKey=fresh();
      const pageHash=createHash('sha256').update(
        (kind==='Course'?'course-device':'activity-installation')+'\0'+pagedKey).digest('hex');
      for(let i=0;i<106;i++)pageBatch.set(roster.doc(fresh()),
        {[field]:program.id,deviceKeyHash:pageHash,deviceVerified:i<105,
          status:'accepted',decidedBy:'automatic',notificationState:'sent'});
      await pageBatch.commit();
      const testToken='local-only-token-for-already-completed-records';
      assert.deepEqual((await sync(pagedKey,testToken)).body.result,{synced:true});
      assert.deepEqual((await sync(fresh(),testToken)).body.result,{synced:true});
      const synced=await roster.where('deviceKeyHash','==',pageHash).get();
      assert.equal(synced.size,106);
      assert.ok(synced.docs.every(doc=>doc.get('fcmToken')===testToken));
      let cursor=null,listed=0;
      do {
        const response=await call('my'+kind+'Registrations',{deviceKey:pagedKey,cursor});
        assert.equal(response.status,200);
        listed+=response.body.result.registrations.length;
        cursor=response.body.result.nextCursor;
      } while(cursor);
      assert.equal(listed,105);
      console.log('PASS '+kind+': immediate pending/automatic seats, concurrent admission, duplicates, full, preverification decisions, seat release, privacy, legacy records, active cap, rate limit and pagination');
    } finally {
      const items=await rows();
      const batch=db.batch();
      items.docs.forEach(doc=>batch.delete(doc.ref));
      batch.delete(inventory);
      batch.delete(program);
      await batch.commit();
    }
  }
}
module.exports={testRegistrationPrivacy};
