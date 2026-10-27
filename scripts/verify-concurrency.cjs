const assert=require('assert/strict');
const {DB,R,RW,P,B,PointService,repo,draft,seedPts,task,tables,clone,snake,DateUtil,today,D}=require('./service-fixtures.cjs');
let checks=0;
async function check(name,fn){await fn();checks++;console.log('PASS '+name);}
(async()=>{
 await check('同时入账两笔均完成且积分按累计减排结算',async()=>{
  const db=new DB();const out=await Promise.all([R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023')),R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023'))]);
  assert.ok(out.every(r=>r.ok),out.map(r=>r.message).join('|'));assert.equal(db.s.records.length,2);assert.equal(db.s.snapshots.length,2);assert.equal((await PointService.account(db)).balance,16);
 });
 await check('余额40并发兑换两份30分奖励，只允许一份成功',async()=>{
  const db=new DB();await seedPts(db,'participation','seed',40);
  const out=await Promise.all([RW.redeem(db,'REWARD_GREEN_BADGE','one'),RW.redeem(db,'REWARD_GREEN_BADGE','two')]);
  assert.equal(out.filter(r=>r.ok).length,1);assert.equal(db.s.redemptions.length,1);assert.equal((await PointService.account(db)).balance,10);
 });
 await check('记录写入失败的回滚不吞掉排队中的兑换',async()=>{
  const db=new DB();await seedPts(db,'participation','seed',40);db.fail='snapshot';
  const [record,reward]=await Promise.all([R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023')),RW.redeem(db,'REWARD_GREEN_BADGE','after-failure')]);
  assert.equal(record.ok,false);assert.equal(reward.ok,true,reward.message);assert.equal(db.s.records.length,0);assert.equal(db.s.redemptions.length,1);assert.equal((await PointService.account(db)).balance,10);
 });
 await check('后发兑换读取前笔入账完成后的余额',async()=>{
  const db=new DB();await seedPts(db,'participation','seed',35);
  const [record,reward]=await Promise.all([R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023',3)),RW.redeem(db,'REWARD_TREE_CERT','after-create')]);
  assert.equal(record.ok,true);assert.equal(reward.ok,true,reward.message);assert.equal((await PointService.account(db)).balance,2);
 });
 await check('同一版本同时修订，后发请求识别版本已更新',async()=>{
  const db=new DB(),first=await R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023'));
  const out=await Promise.all([R.reviseRecord(db,repo,first.data.record.recordId,1,draft('EF_ELEC_HENAN_2023',2)),R.reviseRecord(db,repo,first.data.record.recordId,1,draft('EF_ELEC_HENAN_2023',3))]);
  assert.equal(out.filter(r=>r.ok).length,1);assert.equal(db.s.records.length,2);assert.equal(db.s.snapshots.length,2);
 });
 await check('同时完成参与任务均执行且不重复奖励',async()=>{
  const db=new DB();db.s.tasks.push(task('a',{participationOnly:true}),task('b',{participationOnly:true}));
  const out=await Promise.all([P.completeParticipation(db,'a',today,'隔离测试参与'),P.completeParticipation(db,'b',today,'隔离测试参与')]);
  assert.ok(out.every(r=>r.ok),out.map(r=>r.message).join('|'));assert.equal(db.s.tasks.filter(t=>t.status==='completed').length,2);assert.equal(db.s.points.filter(p=>p.reason==='participation').length,2);
 });
 await check('并发导出不读取入账一半的记录和快照',async()=>{
  const db=new DB();db.dumpTable=async name=>({behavior_record:db.s.records,calculation_snapshot:db.s.snapshots,point_event:db.s.points}[name]||[]).map(snake);
  const [record,backup]=await Promise.all([R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023')),B.buildBackup(db)]);
  assert.equal(record.ok,true);assert.equal(backup.ok,true);const f=JSON.parse(backup.data);assert.equal(f.tables.behavior_record.length,1);assert.equal(f.tables.calculation_snapshot.length,1);assert.equal(B.validate(backup.data).ok,true);
 });
 await check('入账与恢复同时发起，恢复前快照包含完整入账且无队列死锁',async()=>{
  const db=new DB(),original=B.writeToAppDir;let autosave;
  const stateKey={behavior_record:'records',calculation_snapshot:'snapshots',point_event:'points',redemption:'redemptions',weekly_plan:'plans',plan_task:'tasks'};
  db.dumpTable=async name=>(db.s[stateKey[name]]||[]).map(snake);
  db.deleteAllRows=async name=>{if(stateKey[name])db.s[stateKey[name]]=[];};
  db.importRow=async()=>{};
  B.writeToAppDir=async(context,name,text)=>{autosave=JSON.parse(text);return{ok:true,data:'isolated-autosave'};};
  try{
   const empty=JSON.stringify({schemaVersion:2,dataEnvironment:'production',factorSetVersion:repo.setVersion(),tables:tables()});
   const [record,restore]=await Promise.all([R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023')),B.restore(db,empty,{})]);
   assert.equal(record.ok,true,record.message);assert.equal(restore.ok,true,restore.message);
   assert.equal(autosave.tables.behavior_record.length,1);assert.equal(autosave.tables.calculation_snapshot.length,1);assert.equal(B.validate(JSON.stringify(autosave)).ok,true);assert.equal(db.s.records.length,0);assert.equal(db.s.points.length,0);
  }finally{B.writeToAppDir=original;}
 });
 console.log(`PASS ${checks} concurrency checks`);
})().catch(e=>{console.error(e);process.exitCode=1;});
