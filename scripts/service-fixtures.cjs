/* Actual service logic, isolated transactional fixtures; never writes the user's app database. */
const assert=require('assert/strict'),fs=require('fs');
const loader=require('./service-loader.cjs'),load=loader(false),dev=loader(true);
const D=load('common/Domain'),{DateUtil}=load('common/Format');
const {RecordService:R}=load('services/RecordService'),{PlanService:P}=load('services/PlanService');
const {PointService}=load('services/PointService'),{FactorRepository}=load('services/FactorRepository');
const {RewardService:RW}=load('services/RewardService');
const {BackupService:B}=load('services/BackupService'),{BackupPolicy}=load('services/BackupPolicy');
const {PlanEngine}=load('services/PlanEngine'),{EnvironmentPolicy:E}=load('common/DataEnvironment');
const {TASK_TEMPLATES}=load('data/TaskTemplates'),{DDL}=load('services/LedgerSchema');
const repo=FactorRepository.createDefault(),today=DateUtil.today();
const clone=x=>structuredClone(x),key=(id,rev)=>`${id}#${rev}`;
class DB{
 constructor(){this.s={records:[],snapshots:[],points:[],redemptions:[],tasks:[],plans:[],meta:{}};this.fail='';}
 async begin(){assert.equal(this.before,undefined,'no nested transactions');this.before=clone(this.s);}
 async commit(){delete this.before;}
 async rollBack(){if(this.before)this.s=this.before;delete this.before;}
 async insertRecord(r){this.s.records.push(clone(r));}
 async insertSnapshot(s){if(this.fail==='snapshot')throw Error('injected snapshot failure');this.s.snapshots.push(clone(s));}
 async getRecord(id,rev){return clone(this.s.records.find(r=>key(r.recordId,r.revision)===key(id,rev))||null);}
 async getSnapshot(id,rev){return clone(this.s.snapshots.find(r=>key(r.recordId,r.revision)===key(id,rev))||null);}
 async listRecordVersions(id){return clone(this.s.records.filter(r=>r.recordId===id));}
 async listLatestRecords(){const m=new Map();for(const r of this.s.records)if(!m.has(r.recordId)||r.revision>m.get(r.recordId).revision)m.set(r.recordId,r);return clone([...m.values()]);}
 async updateRecordStatus(id,rev,status){this.s.records.find(r=>key(r.recordId,r.revision)===key(id,rev)).status=status;}
 async eligibleReductionTotalsExcluding(id){const m=new Map();for(const r of await this.listLatestRecords())if(r.recordId!==id&&r.status==='active'){const s=await this.getSnapshot(r.recordId,r.revision);if(s.reductionKg>0)m.set(s.gasScope,(m.get(s.gasScope)||0)+s.reductionKg);}return m;}
 async listActiveDaysExcluding(id){return [...new Set((await this.listLatestRecords()).filter(r=>r.recordId!==id&&r.status==='active').map(r=>r.occurredAt))];}
 async sumPointsByReason(reason){return this.s.points.filter(p=>p.reason===reason).reduce((n,p)=>n+p.delta,0);}
 async hasPointEvent(k){return this.s.points.some(p=>p.uniqueKey===k);}
 async sumBonusPointsOnDay(day){return this.s.points.filter(p=>p.dayKey===day&&['daily_first','streak7','participation'].includes(p.reason)).reduce((n,p)=>n+p.delta,0);}
 async insertPointEvent(p,day){assert.ok(!await this.hasPointEvent(p.uniqueKey));this.s.points.push({...clone(p),dayKey:day});}
 async listPointEvents(){return clone(this.s.points);}
 async findPointEventByKey(k){return clone(this.s.points.find(p=>p.uniqueKey===k)||null);}
 // 兑换与证书（第 9.1 节）：价格冻结在兑换记录，requestId 幂等
 async listRewards(){return clone(REWARDS);}
 async getRedemptionByRequest(id){return clone(this.s.redemptions.find(r=>r.requestId===id)||null);}
 async listRedemptions(){return clone(this.s.redemptions.slice().reverse());}
 async insertRedemption(r){if(this.fail==='redemption')throw Error('injected redemption failure');this.s.redemptions.push(clone(r));}
 async queryStatRows(){const out=[];for(const r of await this.listLatestRecords())if(r.status==='active'){const s=await this.getSnapshot(r.recordId,r.revision);if(s)out.push({recordId:r.recordId,gasScope:s.gasScope,reductionKg:s.reductionKg,category:r.category,occurredAt:r.occurredAt});}return clone(out);}
 async listBadgeDefs(){return[];}async listBadgeUnlocks(){return[];}async countLatestActiveRecords(){return(await this.listLatestRecords()).filter(r=>r.status==='active').length;}
 async listPlanTasksByRecord(id){return clone(this.s.tasks.filter(t=>t.linkedRecordId===id));}
 async listTemplates(){return clone(TASK_TEMPLATES);}
 async getPlanTask(id){return clone(this.s.tasks.find(t=>t.planTaskId===id)||null);}
 async updatePlanTask(t){if(this.fail==='task')throw Error('injected task failure');const i=this.s.tasks.findIndex(x=>x.planTaskId===t.planTaskId);assert.ok(i>=0);this.s.tasks[i]=clone(t);}
 async insertPlanTask(t){this.s.tasks.push(clone(t));}
 async getLatestPlanId(){return this.s.meta.latest_plan_id||'';}
 async getPlan(id){return clone(this.s.plans.find(p=>p.planId===id)||null);}
 async listPlanTasks(id){return clone(this.s.tasks.filter(t=>t.planId===id));}
 async countRows(){return this.s.plans.length;}async insertPlan(p){this.s.plans.push(clone(p));}
 async setMeta(k,v){this.s.meta[k]=v;}async getMeta(k){return this.s.meta[k]||'';}
 async dumpTable(){return[];}
}
const draft=(code,qty=1)=>{const f=repo.find(code);return{category:f.category,occurredAt:today,entrySource:D.EntrySource.USER_INPUT,remark:'测试夹具：数量与基准及处理路径有依据',applicabilityAccepted:true,baselineType:D.BaselineType.USER_DECLARED,scenarios:[{role:D.ScenarioRole.BASELINE,factorCode:code,quantity:qty,unit:f.perUnit,label:''}],passengers:0};};
const task=(id='task',over={})=>({planTaskId:id,planId:'plan',templateId:'P03',name:'任务',category:D.BehaviorCategory.WATER_ENERGY,day:today,status:'planned',expectedKg:0.5897,quantity:1,unit:'kWh',extraMinutes:1,extraCost:0,reason:'fixture',participationOnly:false,linkedRecordId:'',actualKg:0,rewarded:false,...over});
const REWARDS=[{rewardId:'REWARD_GREEN_BADGE',name:'绿色收藏章',price:30,kind:'badge',description:'可重复申请的收藏印章，相同请求只扣一次。',repeatable:1,priceVersion:'v1'},{rewardId:'REWARD_TREE_CERT',name:'虚拟植树成就证书',price:50,kind:'certificate',description:'显示编号、日期与用户记录范围；明确不代表真实植树。',repeatable:1,priceVersion:'v1'}];
const seedPts=(db,reason,key,delta)=>db.insertPointEvent({eventId:'pts_'+key,recordId:'',revision:0,reason:reason,uniqueKey:key,delta,detail:'seed',createdAt:DateUtil.toDateTime(new Date())},today);
const tables=()=>Object.fromEntries(['behavior_record','calculation_snapshot','carbon_factor','point_event','reward_def','redemption','badge_def','badge_unlock','task_template','weekly_plan','plan_task','article','attachment'].map(k=>[k,[]]));
const snake=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k.replace(/[A-Z]/g,c=>'_'+c.toLowerCase()),typeof v==='boolean'?Number(v):v]));

module.exports={DB,load,dev,D,DateUtil,R,P,PointService,FactorRepository,RW,B,BackupPolicy,PlanEngine,E,TASK_TEMPLATES,DDL,repo,today,clone,key,draft,task,REWARDS,seedPts,tables,snake};
