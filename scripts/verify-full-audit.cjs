const assert=require('assert/strict');
const {DB,load,repo,draft,task,today,DateUtil,TASK_TEMPLATES,R,PointService}=require('./service-fixtures.cjs');
const {PlanLinkPolicy}=load('services/PlanLinkPolicy'),{CsvService}=load('services/CsvService'),{LedgerOperations}=load('services/LedgerOperations');
let checks=0;async function check(name,fn){await fn();checks++;console.log('PASS '+name);}
(async()=>{
 await check('关联草稿日期、类别、情景不匹配或任务已完成时入账前拒绝',()=>{
  const t=task(),tpl=TASK_TEMPLATES.find(t=>t.templateId==='P03'),d=draft('EF_ELEC_HENAN_2023');
  assert.equal(PlanLinkPolicy.draftError(t,d,tpl,repo),'');
  for(const bad of [{...d,occurredAt:DateUtil.addDays(today,-1)},{...d,category:'food'},{...d,scenarios:draft('EF_ELEC_CN_2023').scenarios}])assert.ok(PlanLinkPolicy.draftError(t,bad,tpl,repo));
  for(const bad of [{...t,status:'completed'},{...t,participationOnly:true},{...t,linkedRecordId:'exists'}])assert.ok(PlanLinkPolicy.draftError(bad,d,tpl,repo));
 });
 await check('队列遇到抛错仍释放后续任务，保持进入顺序',async()=>{
  const order=[];const a=LedgerOperations.run(async()=>{order.push('first');throw Error('expected');});
  const b=LedgerOperations.run(async()=>{order.push('second');return 2;});
  await assert.rejects(a,/expected/);assert.equal(await b,2);assert.deepEqual(order,['first','second']);
 });
 await check('CSV超过1000条明细与5000条积分仍全量导出',async()=>{
  const db=new DB(),one=await R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023'));
  const records=Array.from({length:1001},(_,i)=>({...one.data.record,recordId:`rec-${i}`}));
  const events=Array.from({length:5001},(_,i)=>({recordId:'rec-1000',revision:1,delta:1}));
  db.listLatestRecords=async limit=>{assert.equal(limit,-1);return records;};
  db.listPointEvents=async limit=>{assert.equal(limit,-1);return events;};
  db.getSnapshot=async()=>one.data.snapshot;
  const out=await CsvService.detailCsv(db);assert.equal(out.ok,true,out.message);const lines=out.data.trim().split('\r\n');assert.equal(lines.length,1002);assert.match(lines.at(-1),/,5001,active$/);
 });
 await check('超过300条积分后余额和旧凭证仍含历史事件',async()=>{
  const db=new DB(),one=await R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023'));
  const events=Array.from({length:301},(_,i)=>({recordId:one.data.record.recordId,revision:1,delta:i===0?100:-1}));
  db.listPointEvents=async (limit=300)=>limit<0?events:events.slice(-limit);
  assert.equal((await PointService.account(db)).balance,-200);
  assert.equal((await R.getVoucher(db,one.data.record.recordId,1)).data.pointDelta,-200);
 });
 await check('超过200条记录后存折数据源包含旧记录，不截断累计量',async()=>{
  const db=new DB(),rows=Array.from({length:201},(_,i)=>({recordId:`old-${i}`}));
  db.listLatestRecords=async (limit=200)=>limit<0?rows:rows.slice(0,limit);
  assert.equal((await R.listRecords(db)).length,201);
 });
 await check('首页、统计与导出对十进制半分位采用一致显示舍入',()=>{
  const {NumUtil}=load('common/Format');
  const sum=[2.9485,5.897,3.0425,16,2.9485,2.9485].reduce((a,b)=>a+b,0);
  assert.equal(NumUtil.show(sum),'33.79');assert.equal(NumUtil.show(NumUtil.roundCalc(sum)),'33.79');
  assert.equal(NumUtil.fixed(1.005,2),'1.01');assert.equal(NumUtil.fixed(-1.005,2),'-1.01');
  assert.equal(NumUtil.fixed(.0000001,8),'0.00000010');assert.equal(NumUtil.fixed(NaN,2),'--');
 });
 console.log(`PASS ${checks} full audit checks`);
})().catch(e=>{console.error(e);process.exitCode=1;});
