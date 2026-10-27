import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, GasScope, FactorUsableAs, ReviewStatus } from '../common/Domain';

const FUEL_URL = 'https://www.ndrc.gov.cn/xxgk/zcfb/tz/201511/W020190905506437983335.pdf';
const PAPER_URL = 'https://www.chinacace.org/news/uploads/2022/11/1668654470905455.pdf';
const FOOD_URL = 'https://josephpoore.com/data/science-2018/Poore%20and%20Nemecek%20%282018%29%20Reducing%20foods%20environmental%20impacts%20through%20producers%20and%20consumers.pdf';
const WALK_URL = 'https://www.resci.cn/CN/abstract/article/1007-7588/41501';
const CITATION = '仅引用数值并标明来源与定位；原文及图表版权归原权利人，未获全文或插图转载授权。';

function reviewed(code: string, category: BehaviorCategory, subItem: string, label: string,
  value: number, gas: GasScope, unit: string, role: FactorUsableAs, region: string, year: number,
  boundary: string, method: string, title: string, url: string, locator: string, published: string,
  condition: string, note: string): CarbonFactor {
  return { code: code, version: '2026.10.16.1', category: category, subItem: subItem, scenarioLabel: label,
    value: value, gasScope: gas, perUnit: unit, distanceBasis: unit === 'km' ? 'pkm' : 'na', usableAs: role,
    region: region, dataYear: year, boundary: boundary, methodology: method, sourceTitle: title,
    sourceUrl: url, sourceLocator: locator, publishedAt: published, licenseNote: CITATION,
    reviewStatus: ReviewStatus.VERIFIED, reviewer: 'Codex：原文数值定位与核对（2026-10-16）',
    verifiedBy: '自动复算与单位校验；未冒填团队签字', evidenceRequirement: condition, note: note };
}

/** Narrow, conditional estimates. Verified means the quoted number/source was checked, not behavior certification. */
export const REVIEWED_BEHAVIOR_FACTORS: CarbonFactor[] = [
  reviewed('EF_TRAVEL_GASOLINE_MASS_2015', BehaviorCategory.TRAVEL, 'drive_gasoline_mass', '汽油驾车（按个人用油质量对照）',
    44.8 * 0.0189 * 0.98 * 44 / 12, GasScope.CO2, 'kg', FactorUsableAs.BASELINE, '中国燃料缺省参数参考', 2015,
    '只估算被替代行程的汽油燃烧直接CO₂；不含燃油开采炼制、车辆制造、道路设施和其他温室气体。',
    '由附录参数推导：44.8 GJ/t × 0.0189 tC/GJ × 98% × 44/12 = 3.0425472 tCO₂/t，即同数值 kgCO₂/kg汽油。',
    '国家发展改革委《公共建筑运营企业温室气体排放核算方法和报告指南（试行）》', FUEL_URL,
    '附录一表1：中国化石燃料相关参数缺省值·汽油；正文燃料燃烧公式。仅引用通用燃料参数，不宣称执行完整交通碳普惠方法学。',
    '2015-11', '请说明原本驾车的行程、汽油质量及其估算依据，并确认填的是个人分担量。升数需有密度依据后换算；本场景不适用乙醇汽油、电动车或新增出行。',
    '原本汽油消耗量必须另填 kg，不能把行程公里当作燃油质量。载客分担需已计入该质量。结果为有条件的燃烧参考估算。'),
  reviewed('EF_TRAVEL_WALK_DIRECT', BehaviorCategory.TRAVEL, 'walk', '步行（运行直接排放）',
    0, GasScope.CO2, 'km', FactorUsableAs.ACTUAL, '直接运行边界', 2018,
    '步行运行阶段无燃料燃烧直接CO₂；不包含食品、基础设施或全生命周期影响。',
    '同一行程以步行替代原本汽油驾车；只比较运行直接燃烧排放。',
    '荣培君等《开封城市家庭日常出行碳排放空间分异研究》，资源科学，2018', WALK_URL,
    '2.2.1 出行碳排核算方法：步行与自行车视为零碳排放。本应用将其限定为运行直接燃烧边界。', '2018-06-22', '',
    '实际步行公里与基准个人汽油质量分别填写，不包含步行的完整生命周期。'),
  reviewed('EF_TRAVEL_BIKE_DIRECT', BehaviorCategory.TRAVEL, 'bike', '普通自行车（运行直接排放）',
    0, GasScope.CO2, 'km', FactorUsableAs.ACTUAL, '直接运行边界', 2018,
    '普通人力自行车运行阶段无燃料燃烧直接CO₂；不适用电动自行车，不包含制造、食品及设施影响。',
    '同一行程以普通人力自行车替代原本汽油驾车；只比较运行直接燃烧排放。',
    '荣培君等《开封城市家庭日常出行碳排放空间分异研究》，资源科学，2018', WALK_URL,
    '2.2.1 出行碳排核算方法：步行与自行车视为零碳排放。本应用限定为普通人力自行车运行直接燃烧边界。', '2018-06-22', '',
    '不适用电动自行车。只在确实替代原本驾车的情况下记录。'),
  reviewed('EF_RECYCLE_PAPER_UTILIZED_2022', BehaviorCategory.RECYCLING, 'waste_paper_utilized', '废纸已再生利用（生产环节参考）',
    4, GasScope.CO2, 'kg', FactorUsableAs.SINGLE, '中国行业比较参考，非本地工厂实测', 2022,
    '只比较以废纸生产再生纸与原生纸生产环节；不包含收运、分类损耗等完整生命周期。原文为约数。',
    '报告给出每利用1吨废纸生产再生纸约减少4吨CO₂；同单位换算为约4 kgCO₂/kg实际利用废纸。未再生利用的投放量不能套用。',
    '中国循环经济协会《循环经济助力碳达峰研究报告》', PAPER_URL,
    '印刷页8，废纸循环利用的碳减排效果段落：仅对比生产环节，每利用1吨废纸生产再生纸约减少4吨CO₂。', '2022-11',
    '必须有可说明实际再生利用路径和重量的回收／处理记录，填写已用于再生纸生产的废纸重量；仅扔进回收箱不满足条件。请在备注写明接收方、路径及重量依据。',
    '这是满足再生利用条件时的行业生产环节约数估算，不是个人投放即产生的核证减排量；不与其他同批废纸记录重复计入。'),
  reviewed('EF_FOOD_APPLE_PROCUREMENT_PN2018', BehaviorCategory.FOOD, 'food_apple_procurement', '按需采购苹果，避免买多浪费',
    0.4, GasScope.CO2E, 'kg', FactorUsableAs.SINGLE, '全球生产加权均值代理，非中国本地实测', 2010,
    '食品供应链投入至零售阶段的温室气体；不包含消费者烹饪和废弃处置。本项目只作减少采购所对应的上游需求参考估算。',
    'Poore与Nemecek图1F：Apples，功能单位1kg零售产品，GHG均值0.4 kgCO₂eq（图中一位小数）；样本参考年份中位数2010。',
    'Poore & Nemecek, Reducing food’s environmental impacts through producers and consumers, Science 360, 987–992 (2018), corrected 2019',
    FOOD_URL, '图1F：Apples / 1kg / GHG emissions / Mean 0.4；正文第1页说明投入至零售边界及样本中位参考年2010。', '2018-06-01',
    '仅限按需采购、减少原本会浪费的苹果购买量。填写减少采购的零售整果重量（kg），说明原本量、本次量和称重依据；不是吃完一顿饭的重量、果皮或苹果核重量。',
    '采用论文图中的一位小数全球均值作为代理，存在地区与供应链差异。吃完已买的苹果并不直接等于上游排放减少，本场景要求确有减少采购的对照。')
];
