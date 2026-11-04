import { DEV_FACTOR_MODE } from '../common/BuildConfig';
import { common } from '@kit.AbilityKit';
import { AppService } from '../services/AppService';
import { LedgerTab } from '../components/LedgerTab';
import { PlanTab } from '../components/PlanTab';
import { DashboardTab } from '../components/DashboardTab';
import { KnowledgeTab } from '../components/KnowledgeTab';
import { ProfileTab } from '../components/ProfileTab';
import { AppIcon, DevelopmentBanner } from '../components/DesignSystem';
import { Theme, Passbook } from '../common/Theme';

// 尊重用户关闭动效的选择，重新打开应用时仍保留。
PersistentStorage.persistProp('gentleMotion', true);

@Component
struct NavItem {
  @Prop label: string = '';
  @Prop icon: string = 'leaf';
  @Link currentTab: number;
  @Prop destinationIndex: number = 0;
  build() {
    Column({ space: 4 }) {
      Stack() {
        AppIcon({ name: this.icon, iconSize: 22, color: Passbook.print })
          .opacity(this.currentTab === this.destinationIndex ? 1 : 0.38)
      }.width(52).height(30).borderRadius(15)
      .backgroundColor(this.currentTab === this.destinationIndex ? Passbook.wash : Color.Transparent)
      Text(this.label).fontSize(11).fontWeight(this.currentTab === this.destinationIndex ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTab === this.destinationIndex ? Passbook.print : Passbook.faint)
    }.width('100%').height(66).justifyContent(FlexAlign.Center)
      .id(`nav-${this.destinationIndex}-${this.currentTab === this.destinationIndex ? 'selected' : 'idle'}`)
      .accessibilityGroup(true).accessibilityText(this.label + (this.currentTab === this.destinationIndex ? '，已选中' : ''))
  }
}

@Entry
@Component
struct Index {
  @State tick: number = 0;
  @State activeTab: number = 0;
  // 看板点明细后跳到存折，并按该区间筛选；清空即恢复全部
  @State @Watch('onLedgerFilter') ledgerFilterFrom: string = '';
  @State ledgerFilterTo: string = '';
  @State pageVisible: boolean = true;
  @State ready: boolean = false;
  @State bootMessage: string = '';
  private controller: TabsController = new TabsController();
  aboutToAppear(): void {
    AppService.bootstrap(getContext(this) as common.UIAbilityContext).then((res) => {
      if (res.ok) { this.ready = true; this.tick++; }
      else { this.bootMessage = res.message; }
    });
  }
  onLedgerFilter(): void {
    if (this.ledgerFilterFrom.length > 0) {
      this.activeTab = 0;
      this.controller.changeIndex(0);
      this.tick++;
    }
  }

  onPageShow(): void { this.pageVisible = true; this.tick++; }
  onPageHide(): void { this.pageVisible = false; }
  @Builder ledgerNav() { NavItem({ label: '存折', icon: 'leaf', currentTab: $activeTab, destinationIndex: 0 }) }
  @Builder planNav() { NavItem({ label: '计划', icon: 'plan', currentTab: $activeTab, destinationIndex: 1 }) }
  @Builder chartNav() { NavItem({ label: '看板', icon: 'chart', currentTab: $activeTab, destinationIndex: 2 }) }
  @Builder bookNav() { NavItem({ label: '知绿', icon: 'book', currentTab: $activeTab, destinationIndex: 3 }) }
  @Builder userNav() { NavItem({ label: '我的', icon: 'user', currentTab: $activeTab, destinationIndex: 4 }) }
  build() {
    Column() {
      if (this.ready) {
        DevelopmentBanner()
        Tabs({ barPosition: BarPosition.End, index: this.activeTab, controller: this.controller }) {
          TabContent() { LedgerTab({ tick: this.tick, active: this.activeTab === 0 && this.pageVisible, filterFrom: $ledgerFilterFrom, filterTo: $ledgerFilterTo,
            onOpenPlan: () => { this.activeTab = 1; this.controller.changeIndex(1); } }) }.tabBar(this.ledgerNav)
          TabContent() { PlanTab({ tick: this.tick }) }.tabBar(this.planNav)
          TabContent() { DashboardTab({ tick: this.tick, ledgerFrom: $ledgerFilterFrom, ledgerTo: $ledgerFilterTo }) }.tabBar(this.chartNav)
          TabContent() { KnowledgeTab({ tick: this.tick }) }.tabBar(this.bookNav)
          TabContent() { ProfileTab({ tick: $tick }) }.tabBar(this.userNav)
        }.barMode(BarMode.Fixed).barHeight(72).barBackgroundColor(Passbook.page)
          .divider({ strokeWidth: 0.5, color: Passbook.rule })
          .onChange((index: number) => { this.activeTab = index; this.tick++; })
          .width('100%').layoutWeight(1)
      } else {
        Column({ space: 18 }) {
          AppIcon({ name: 'leaf', iconSize: 44 })
          Text('绿碳存折').fontSize(26).fontColor(Theme.ink)
          Text(this.bootMessage.length > 0 ? this.bootMessage : '正在翻开你的绿色存折…').fontSize(13).fontColor(Theme.muted)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor(Passbook.page)
  }
}
