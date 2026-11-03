const assert=require('assert/strict');
const {load,D,DateUtil,repo,draft,DB,today}=require('./service-fixtures.cjs');
const {ActionCoachService}=load('services/ActionCoachService');
const {WeeklyReportService}=load('services/WeeklyReportService');
const {LocalMockBenefitService}=load('services/LocalMockBenefitService');
const {AiCoachService}=load('services/AiCoachService');
const {AiConfigStore}=load('services/AiConfigStore');
const {maskKey}=load('models/AiModels');
let checks=0;async function check(name,fn){await fn();checks++;console.log('PASS '+name);}
const task=(id,day,status,extra={})=>({planTaskId:id,planId:'p',templateId:'P01',name:id,category:D.BehaviorCategory.TRAVEL,day,status,expectedKg:0.42,quantity:1,unit:'km',extraMinutes:10,extraCost:0,reason:'与已保存计划一致',participationOnly:false,linkedRecordId:'',actualKg:0,rewarded:false,...extra});
const voucher=(over={})=>({
 record:{recordId:'record-7',revision:1,status:D.RecordStatus.ACTIVE},
 snapshot:{reductionKg:0.5897,isNetIncrease:false,gasScope:D.GasScope.CO2},
 sources:[{reviewStatus:'verified'}],isLatest:true, ...over
});
(async()=>{
 await check('行动教练只展示未来七天未完成任务，今日与进行中优先且不修改输入',()=>{
  const tasks=[task('later',DateUtil.addDays(today,2),D.PlanTaskStatus.PLANNED),task('today',today,D.PlanTaskStatus.PLANNED),task('started',today,D.PlanTaskStatus.IN_PROGRESS),task('done',today,D.PlanTaskStatus.COMPLETED),task('old',DateUtil.addDays(today,-1),D.PlanTaskStatus.PLANNED),task('far',DateUtil.addDays(today,7),D.PlanTaskStatus.PLANNED)];
  const before=structuredClone(tasks);const recs=ActionCoachService.recommend(tasks,today,3);
  assert.deepEqual(recs.map(r=>r.planTaskId),['started','today','later']);assert.deepEqual(tasks,before);assert.equal(ActionCoachService.recommend(tasks,'bad-day',3).length,0);
 });
 await check('参与型行动建议不带入预计减排，限制数量与稳定排序有效',()=>{
  const tasks=[task('b',today,D.PlanTaskStatus.PLANNED,{participationOnly:true,expectedKg:8}),task('a',today,D.PlanTaskStatus.PLANNED,{extraMinutes:5}),task('c',today,D.PlanTaskStatus.PLANNED,{extraMinutes:5})];
  const recs=ActionCoachService.recommend(tasks,today,2);assert.deepEqual(recs.map(r=>r.planTaskId),['a','c']);
  const participation=ActionCoachService.recommend([tasks[0]],today,1);assert.equal(participation[0].expectedKg,0);assert.equal(participation[0].participationOnly,true);
 });
 await check('周报按CO2/CO2e分开汇总并省略编号、备注和身份字段',async()=>{
  const db={queryStatRows:async()=>[
   {recordId:'private-record-1',revision:4,dayKey:today,category:D.BehaviorCategory.WATER_ENERGY,reductionKg:0.5897,gasScope:D.GasScope.CO2,remark:'private-note',userName:'private-name'},
   {recordId:'private-record-2',revision:1,dayKey:today,category:D.BehaviorCategory.FOOD,reductionKg:0.4,gasScope:D.GasScope.CO2E,remark:'secret'},
   {recordId:'old',revision:1,dayKey:DateUtil.addDays(today,-8),category:D.BehaviorCategory.TRAVEL,reductionKg:100,gasScope:D.GasScope.CO2,remark:'outside'}
  ]};
  const result=await WeeklyReportService.buildWeeklyReport(db,today);assert.equal(result.ok,true,result.message);const text=result.data;
  assert.match(text,/CO₂ \/ kgCO₂ · 1 条/);assert.match(text,/CO₂e \/ kgCO₂e · 1 条/);assert.doesNotMatch(text,/private-record|private-note|private-name|secret|outside/);assert.match(text,/完整个人碳足迹/);assert.match(text,/经核证碳资产/);
 });
 await check('周报拒绝无效日期且空记录说明无数据',async()=>{
  const bad=await WeeklyReportService.buildWeeklyReport({queryStatRows:async()=>[]},'2026-99-99');assert.equal(bad.ok,false);
  const empty=await WeeklyReportService.buildWeeklyReport({queryStatRows:async()=>[]},today);assert.equal(empty.ok,true);assert.match(empty.data,/还没有可汇总/);
 });
 await check('本地碳普惠仿真仅接受最新有效已核验正向记录',()=>{
  assert.equal(LocalMockBenefitService.evaluate(voucher()).eligible,true);
  assert.equal(LocalMockBenefitService.evaluate(voucher({isLatest:false})).eligible,false);
  assert.equal(LocalMockBenefitService.evaluate(voucher({record:{recordId:'record-7',revision:1,status:D.RecordStatus.VOIDED}})).eligible,false);
  assert.equal(LocalMockBenefitService.evaluate(voucher({snapshot:{reductionKg:-.2,isNetIncrease:true,gasScope:D.GasScope.CO2}})).eligible,false);
  assert.equal(LocalMockBenefitService.evaluate(voucher({sources:[{reviewStatus:'pending'}]})).eligible,false);
 });
 await check('仿真提交按记录版本幂等、只在内存查询且明确标注模拟',()=>{
  const v=voucher();const first=LocalMockBenefitService.submit(v,'2026-11-03T10:00:00');assert.equal(first.ok,true);assert.equal(first.data.status,'SIMULATED_ACCEPTED');assert.match(first.data.platformName,/本地模拟/);assert.match(first.data.notice,/不是平台交易/);
  const second=LocalMockBenefitService.submit(v,'2026-11-03T11:00:00');assert.deepEqual(second.data,first.data);assert.equal(LocalMockBenefitService.query(first.data.requestId).data.createdAt,'2026-11-03T10:00:00');
  const invalid=LocalMockBenefitService.submit(voucher({isLatest:false}),'2026-11-03T12:00:00');assert.equal(invalid.ok,false);
 });
 await check('行为服务升级不更改既有记账与积分用例依赖',async()=>{
  const db=new DB();const res=await require('./service-fixtures.cjs').R.createRecord(db,repo,draft('EF_ELEC_HENAN_2023'));assert.equal(res.ok,true,res.message);assert.equal(db.s.records.length,1);assert.equal(db.s.points.length>0,true);
 });
 
 await check('AI 上下文只含计划摘要，不含记录编号、备注或身份字段',()=>{
  const outcome={ok:true,code:'',message:'',plan:null,plannedKg:8.13,gapKg:0,participationCount:3,targetMet:true,trace:[],
   tasks:[
    {planTaskId:'ptask-secret-1',planId:'plan',templateId:'P03',name:'一次有依据的节电',category:D.BehaviorCategory.WATER_ENERGY,day:today,status:D.PlanTaskStatus.PLANNED,expectedKg:.5897,quantity:1,unit:'kWh',extraMinutes:2,extraCost:0,reason:'private-reason',participationOnly:false,linkedRecordId:'private-record',actualKg:0,rewarded:false},
    {planTaskId:'ptask-secret-2',planId:'plan',templateId:'P08',name:'一次按需取餐',category:D.BehaviorCategory.FOOD,day:today,status:D.PlanTaskStatus.PLANNED,expectedKg:0,quantity:1,unit:'times',extraMinutes:0,extraCost:0,reason:'x',participationOnly:true,linkedRecordId:'',actualKg:0,rewarded:false}
   ]};
  const context=AiCoachService.buildContext(outcome);
  assert.match(context,/一次有依据的节电/);assert.match(context,/只计参与/);
  assert.doesNotMatch(context,/ptask-secret|private-reason|private-record|plan/);
 });
 await check('AI 文本清洗去掉列表符号与换行，并限制长度',()=>{
  const cleaned=AiCoachService.sanitize('- 第一句\n* 第二句\n\n• 第三句');
  assert.equal(cleaned,'第一句 第二句 第三句');
  assert.equal(AiCoachService.sanitize('字'.repeat(600)).length,400);
 });
 await check('AI 配置校验要求 https、模型与密钥，并掩码展示密钥',()=>{
  const base={endpoint:'https://api.example.com/v1/chat/completions',model:'demo',apiKey:'sk-test-12345678',enabled:true};
  assert.equal(AiConfigStore.validate(base).ok,true);
  assert.equal(AiConfigStore.validate({...base,endpoint:'http://api.example.com'}).ok,false);
  assert.equal(AiConfigStore.validate({...base,model:' '}).ok,false);
  assert.equal(AiConfigStore.validate({...base,apiKey:''}).ok,false);
  assert.equal(maskKey('sk-test-12345678'),'••••5678');
  assert.equal(maskKey(''),'未填写');
 });
 await check('AI 网络错误转为可读中文，不把超时原文直接抛给用户',()=>{
  assert.equal(AiCoachService.describeNetworkError('Operation timeout'),'连接超时，请检查网络连接或接口地址');
  assert.equal(AiCoachService.describeNetworkError('Could not resolve host'),'无法解析接口地址，请检查网络或域名');
  assert.equal(AiCoachService.describeNetworkError('Connection refused'),'连接被拒绝，请检查接口地址与端口');
  assert.match(AiCoachService.describeNetworkError('weird failure'),/网络不可用（weird failure）/);
 });
 await check('模型列表地址由 chat completions 推导',()=>{
  assert.equal(AiCoachService.modelsEndpoint('https://www.sub-coco.org/v1/chat/completions'),'https://www.sub-coco.org/v1/models');
  assert.equal(AiCoachService.modelsEndpoint('https://relay.example.com/models'),'https://relay.example.com/models');
 });
 await check('模型元信息解析为上下文与每百万价格，缺失或异常时如实省略',()=>{
  const plain=AiCoachService.parseModelOption({id:'demo-model'});
  assert.equal(plain.id,'demo-model');assert.equal(AiCoachService.modelMetaText(plain),'');
  const meta=AiCoachService.parseModelOption({id:'demo-model',context_length:65536,pricing:{prompt:'0.00000027',completion:0.0000011}});
  assert.equal(meta.contextLength,65536);assert.equal(meta.priceIn,0.27);assert.equal(meta.priceOut,1.1);
  assert.equal(AiCoachService.modelMetaText(meta),'上下文66K · 输入0.27/输出1.1 每百万');
  const perMillion=AiCoachService.parseModelOption({id:'m2',context_length:1000000,pricing:{prompt:2,completion:8}});
  assert.equal(AiCoachService.modelMetaText(perMillion),'上下文1M · 输入2/输出8 每百万');
  assert.equal(AiCoachService.parseModelOption({context_length:4096}),null);
  const bad=AiCoachService.parseModelOption({id:'m3',context_length:-5,pricing:{prompt:'abc',completion:0}});
  assert.equal(bad.contextLength,undefined);assert.equal(bad.priceIn,undefined);assert.equal(bad.priceOut,undefined);
  assert.equal(AiCoachService.modelMetaText(bad),'');
 });
 await check('中转站根地址自动补全为 chat completions',()=>{
  assert.equal(AiConfigStore.effectiveEndpoint('https://www.sub-coco.org'),'https://www.sub-coco.org/v1/chat/completions');
  assert.equal(AiConfigStore.effectiveEndpoint('https://relay.example.com/'),'https://relay.example.com/v1/chat/completions');
  assert.equal(AiConfigStore.effectiveEndpoint('https://relay.example.com/v1'),'https://relay.example.com/v1/chat/completions');
  assert.equal(AiConfigStore.effectiveEndpoint('https://api.example.com/v1/chat/completions'),'https://api.example.com/v1/chat/completions');
  const v=AiConfigStore.validate({endpoint:'https://www.sub-coco.org',model:'deepseek-chat',apiKey:'sk-x',enabled:false});
  assert.equal(v.ok,true,v.message);
 });
 console.log(`PASS ${checks} feature checks`);
})().catch(e=>{console.error(e);process.exitCode=1;});
