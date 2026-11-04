import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onWindowStageCreate');

    const mainWindow = windowStage.getMainWindowSync();
    mainWindow.setWindowSystemBarProperties({ statusBarColor: '#FFFFFF', statusBarContentColor: '#16181D', navigationBarColor: '#FFFFFF', navigationBarContentColor: '#16181D' }).catch(() => {});

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'lvt', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 存折标题与数字字体随包离线提供（SIL OFL 1.1，见 rawfile/fonts/LICENSES.txt）；注册失败时回退系统字体。
      try {
        const font = windowStage.getMainWindowSync().getUIContext().getFont();
        font.registerFont({ familyName: 'PassbookSerif', familySrc: $rawfile('fonts/passbook_serif.otf') });
        font.registerFont({ familyName: 'PassbookNumeral', familySrc: $rawfile('fonts/passbook_numeral.ttf') });
      } catch (e) {
        hilog.warn(DOMAIN, 'lvt', 'register fonts failed: %{public}s', JSON.stringify(e));
      }
      hilog.info(DOMAIN, 'lvt', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'lvt', '%{public}s', 'Ability onBackground');
  }
}
