/**
 * 数据库 schema 定义（第 8.3 节业务表）。
 * 表结构变更时同步提升 BuildConfig.SCHEMA_VERSION，并保证旧凭证仍可重现。
 */

export class Tables {
  static readonly BEHAVIOR_RECORD = 'behavior_record';
  static readonly CALCULATION_SNAPSHOT = 'calculation_snapshot';
  static readonly CARBON_FACTOR = 'carbon_factor';
  static readonly POINT_EVENT = 'point_event';
  static readonly REWARD_DEF = 'reward_def';
  static readonly REDEMPTION = 'redemption';
  static readonly BADGE_DEF = 'badge_def';
  static readonly BADGE_UNLOCK = 'badge_unlock';
  static readonly TASK_TEMPLATE = 'task_template';
  static readonly WEEKLY_PLAN = 'weekly_plan';
  static readonly PLAN_TASK = 'plan_task';
  static readonly ARTICLE = 'article';
  static readonly ATTACHMENT = 'attachment';
  static readonly APP_META = 'app_meta';
}

/** 建表语句。全部使用 IF NOT EXISTS，便于升级时幂等执行。 */
export const DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS behavior_record (
    record_id TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    category TEXT NOT NULL,
    quantity REAL NOT NULL,
    unit TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    day_key TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'active',
    entry_source TEXT NOT NULL DEFAULT 'user_input',
    entry_note TEXT NOT NULL DEFAULT '',
    remark TEXT NOT NULL DEFAULT '',
    parent_record_id TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (record_id, revision)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_record_day ON behavior_record(day_key)`,
  `CREATE INDEX IF NOT EXISTS idx_record_category ON behavior_record(category)`,

  `CREATE TABLE IF NOT EXISTS calculation_snapshot (
    snapshot_id TEXT NOT NULL,
    record_id TEXT NOT NULL,
    revision INTEGER NOT NULL,
    category TEXT NOT NULL,
    baseline_type TEXT NOT NULL,
    gas_scope TEXT NOT NULL,
    reduction_kg REAL NOT NULL DEFAULT 0,
    is_net_increase INTEGER NOT NULL DEFAULT 0,
    formula_version TEXT NOT NULL DEFAULT '',
    formula_text TEXT NOT NULL DEFAULT '',
    rounding_note TEXT NOT NULL DEFAULT '',
    scenarios_json TEXT NOT NULL DEFAULT '[]',
    factor_sources_json TEXT NOT NULL DEFAULT '[]',
    evidence_label TEXT NOT NULL DEFAULT '',
    scope_note TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (record_id, revision)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_snapshot_record ON calculation_snapshot(record_id)`,

  `CREATE TABLE IF NOT EXISTS carbon_factor (
    code TEXT NOT NULL,
    version TEXT NOT NULL,
    category TEXT NOT NULL,
    sub_item TEXT NOT NULL,
    scenario_label TEXT NOT NULL,
    value REAL NOT NULL,
    gas_scope TEXT NOT NULL,
    per_unit TEXT NOT NULL,
    distance_basis TEXT NOT NULL DEFAULT 'na',
    usable_as TEXT NOT NULL,
    region TEXT NOT NULL DEFAULT '',
    data_year INTEGER NOT NULL DEFAULT 0,
    boundary TEXT NOT NULL DEFAULT '',
    methodology TEXT NOT NULL DEFAULT '',
    source_title TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    source_locator TEXT NOT NULL DEFAULT '',
    published_at TEXT NOT NULL DEFAULT '',
    license_note TEXT NOT NULL DEFAULT '',
    review_status TEXT NOT NULL,
    reviewer TEXT NOT NULL DEFAULT '',
    verified_by TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (code, version)
  )`,

  `CREATE TABLE IF NOT EXISTS point_event (
    event_id TEXT PRIMARY KEY,
    record_id TEXT NOT NULL DEFAULT '',
    revision INTEGER NOT NULL DEFAULT 0,
    reason TEXT NOT NULL,
    unique_key TEXT NOT NULL,
    delta INTEGER NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    day_key TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT ''
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_point_unique ON point_event(unique_key)`,
  `CREATE INDEX IF NOT EXISTS idx_point_day ON point_event(day_key)`,

  `CREATE TABLE IF NOT EXISTS reward_def (
    reward_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price INTEGER NOT NULL DEFAULT 0,
    kind TEXT NOT NULL DEFAULT 'badge',
    description TEXT NOT NULL DEFAULT '',
    repeatable INTEGER NOT NULL DEFAULT 0,
    price_version TEXT NOT NULL DEFAULT 'v1'
  )`,

  `CREATE TABLE IF NOT EXISTS redemption (
    redemption_id TEXT PRIMARY KEY,
    request_id TEXT NOT NULL,
    reward_id TEXT NOT NULL,
    price INTEGER NOT NULL DEFAULT 0,
    price_version TEXT NOT NULL DEFAULT 'v1',
    point_event_id TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'granted',
    created_at TEXT NOT NULL DEFAULT ''
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_redemption_request ON redemption(request_id)`,

  `CREATE TABLE IF NOT EXISTS badge_def (
    badge_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    condition TEXT NOT NULL DEFAULT '',
    rule_kind TEXT NOT NULL DEFAULT '',
    rule_category TEXT NOT NULL DEFAULT '',
    rule_threshold INTEGER NOT NULL DEFAULT 0,
    achievement INTEGER NOT NULL DEFAULT 1
  )`,

  `CREATE TABLE IF NOT EXISTS badge_unlock (
    badge_id TEXT PRIMARY KEY,
    unlocked_at TEXT NOT NULL DEFAULT '',
    reason TEXT NOT NULL DEFAULT ''
  )`,

  `CREATE TABLE IF NOT EXISTS task_template (
    template_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    applicable_when TEXT NOT NULL DEFAULT '',
    evidence_rule TEXT NOT NULL DEFAULT '',
    measure_unit TEXT NOT NULL DEFAULT '',
    factor_sub_item TEXT NOT NULL DEFAULT '',
    substitute_scenario TEXT NOT NULL DEFAULT '',
    default_quantity REAL NOT NULL DEFAULT 0,
    extra_minutes INTEGER NOT NULL DEFAULT 0,
    extra_cost REAL NOT NULL DEFAULT 0,
    allowed_weekdays TEXT NOT NULL DEFAULT '',
    mutex_group TEXT NOT NULL DEFAULT '',
    max_times_per_week INTEGER NOT NULL DEFAULT 1,
    has_comparable_quantity INTEGER NOT NULL DEFAULT 1,
    explain_template TEXT NOT NULL DEFAULT ''
  )`,

  `CREATE TABLE IF NOT EXISTS weekly_plan (
    plan_id TEXT PRIMARY KEY,
    plan_version INTEGER NOT NULL DEFAULT 1,
    constraints_json TEXT NOT NULL DEFAULT '{}',
    factor_set_version TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT ''
  )`,

  `CREATE TABLE IF NOT EXISTS plan_task (
    plan_task_id TEXT PRIMARY KEY,
    plan_id TEXT NOT NULL,
    template_id TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    day TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',
    expected_kg REAL NOT NULL DEFAULT 0,
    quantity REAL NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT '',
    extra_minutes INTEGER NOT NULL DEFAULT 0,
    extra_cost REAL NOT NULL DEFAULT 0,
    reason TEXT NOT NULL DEFAULT '',
    participation_only INTEGER NOT NULL DEFAULT 0,
    linked_record_id TEXT NOT NULL DEFAULT '',
    actual_kg REAL NOT NULL DEFAULT 0,
    rewarded INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE INDEX IF NOT EXISTS idx_plan_task_plan ON plan_task(plan_id)`,

  `CREATE TABLE IF NOT EXISTS article (
    article_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    image TEXT NOT NULL DEFAULT '',
    source_title TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    image_license TEXT NOT NULL DEFAULT '',
    read_minutes INTEGER NOT NULL DEFAULT 2
  )`,

  `CREATE TABLE IF NOT EXISTS attachment (
    attachment_id TEXT PRIMARY KEY,
    record_id TEXT NOT NULL DEFAULT '',
    local_path TEXT NOT NULL DEFAULT '',
    digest TEXT NOT NULL DEFAULT '',
    mime_type TEXT NOT NULL DEFAULT '',
    deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT ''
  )`,

  `CREATE TABLE IF NOT EXISTS app_meta (
    k TEXT PRIMARY KEY,
    v TEXT NOT NULL DEFAULT ''
  )`
];
