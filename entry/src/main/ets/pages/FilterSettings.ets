import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { FilterSettingsRepository, FILTER_KEYS, RecommendAlgo } from '../services/FilterSettingsRepository';
import { BlockHistoryRepository } from '../services/BlockHistoryRepository';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';
import { SettingsCard, NumberSettingRow } from './FilterSettingRows';

interface FilterToggleItem {
  key: string;
  title: string;
  desc: string;
  implemented: boolean;
}

interface AlgoOption {
  label: string;
  value: RecommendAlgo;
}

// 推荐设置区：前两项为纯配置；质量 / 智能过滤已下放到独立子页（齿轮图标导航）
const RECOMMEND_TOGGLES: FilterToggleItem[] = [
  { key: FILTER_KEYS.recommendLogin, title: '推荐内容时登录', desc: '获取推荐时携带登录凭证', implemented: true },
  { key: FILTER_KEYS.autoRefresh, title: '启动时自动刷新首页', desc: '关闭后优先显示上次缓存内容', implemented: true },
];

// 内容屏蔽区
const CONTENT_BLOCK_TOGGLES: FilterToggleItem[] = [
  { key: FILTER_KEYS.blockEdu, title: '屏蔽知乎学堂内容', desc: '匹配 d.zhihu.com 学堂内容', implemented: true },
  { key: FILTER_KEYS.blockWechat, title: '屏蔽微信公众号文章', desc: '匹配 mp.weixin.qq.com 外链', implemented: true },
  { key: FILTER_KEYS.blockYanxuan, title: '屏蔽知乎盐选付费内容', desc: '屏蔽盐选会员付费回答与文章', implemented: true },
];

// 屏蔽规则区（关键词/用户/主题/阈值/广告平台已实现）
const RULE_BLOCK_TOGGLES: FilterToggleItem[] = [
  { key: FILTER_KEYS.keywordBlock, title: '启用关键词屏蔽', desc: '屏蔽包含指定关键词的内容', implemented: true },
  { key: FILTER_KEYS.userBlock, title: '启用用户屏蔽', desc: '屏蔽指定用户发布的内容', implemented: true },
  { key: FILTER_KEYS.topicBlock, title: '启用主题屏蔽', desc: '屏蔽包含指定主题的内容', implemented: true },
  { key: FILTER_KEYS.blockAd, title: '屏蔽知乎广告平台内容', desc: '匹配 xg.zhihu.com 广告内容', implemented: true },
];

const FILTER_TOGGLE_DEFAULTS: Record<string, boolean> = {
  'recommend_login': true,
  'auto_refresh_on_launch': true,
  'block_zhihu_edu': true,
  'block_wechat': true,
  'block_yanxuan': true,
  'keyword_block': true,
  'user_block': true,
  'topic_block': true,
  'block_ad': true,
};

@Entry
@Component
struct FilterSettingsPage {
  @State toggleState: Record<string, boolean> = {};
  @State recommendAlgo: RecommendAlgo = 'mixed';
  @State topicThreshold: number = 1;
  @State topicThresholdInput: string = '1';
  @State showThresholdSheet: boolean = false;
  @State blockCount: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @State private topBarHeight: number = 0;
  @StorageProp('fontSubhead') fontSubhead: string = '18fp';
  @StorageProp('fontMeta') fontMeta: string = '13fp';
  @StorageProp('fontBody') fontBody: string = '16fp';
  @StorageProp('fontCaption') fontCaption: string = '12fp';
  @StorageProp('fontSecondary') fontSecondary: string = '14fp';

  private algoOptions: AlgoOption[] = [
    { label: '网页端推荐', value: 'web' },
    { label: '客户端推荐', value: 'android' },
    { label: '混合推荐', value: 'mixed' },
  ];

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    const ctx = this.context();
    this.recommendAlgo = FilterSettingsRepository.getStr(ctx, FILTER_KEYS.recommendAlgo, 'mixed') as RecommendAlgo;
    this.topicThreshold = FilterSettingsRepository.getInt(ctx, FILTER_KEYS.topicThreshold, 1);
    const all: FilterToggleItem[] = RECOMMEND_TOGGLES.concat(CONTENT_BLOCK_TOGGLES, RULE_BLOCK_TOGGLES);
    const next: Record<string, boolean> = {};
    for (const item of all) {
      const def: boolean = FILTER_TOGGLE_DEFAULTS[item.key] ?? false;
      next[item.key] = FilterSettingsRepository.getBool(ctx, item.key, def);
    }
    this.toggleState = next;
    this.blockCount = BlockHistoryRepository.getRecords(ctx).length;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message: message, duration: 2000 });
  }

  private updateToggle(key: string, value: boolean): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.toggleState)) {
      next[k] = this.toggleState[k];
    }
    next[key] = value;
    this.toggleState = next;
  }

  private onToggleChange(item: FilterToggleItem, value: boolean): void {
    this.updateToggle(item.key, value);
    FilterSettingsRepository.setBool(this.context(), item.key, value);
    if (!item.implemented) {
      this.showToast(`「${item.title}」功能暂未生效，将在后续版本开放`);
    }
  }

  private algoLabel(): string {
    for (const o of this.algoOptions) {
      if (o.value === this.recommendAlgo) {
        return o.label;
      }
    }
    return '混合推荐';
  }

  @Builder algoMenuBuilder() {
    Menu() {
      ForEach(this.algoOptions, (o: AlgoOption, index: number) => {
        MenuItem({ content: o.label }).onClick(() => {
          this.selectAlgo(o.value);
        })
      }, (o: AlgoOption, index: number): string => 'algo_' + index)
    }
  }

  private selectAlgo(v: RecommendAlgo): void {
    this.recommendAlgo = v;
    FilterSettingsRepository.setStr(this.context(), FILTER_KEYS.recommendAlgo, v);
  }

  private openThresholdDialog(): void {
    // 主题屏蔽本体已实现，阈值输入框用 bindSheet（本 SDK AlertDialog 无 textInput）
    this.topicThresholdInput = String(this.topicThreshold);
    this.showThresholdSheet = true;
  }

  @Builder ThresholdSheet() {
    Column({ space: 16 }) {
      Text('主题屏蔽阈值')
        .fontSize(this.fontSubhead)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, top: 8 })

      Text('回答/文章所关联的问题包含 ≥ N 个被屏蔽主题时隐藏；N=1 表示任一命中即屏蔽。')
        .fontSize(this.fontMeta)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, right: 20 })

      TextInput({ text: this.topicThresholdInput, placeholder: '1' })
        .type(InputType.Number)
        .width('100%')
        .padding({ left: 20, right: 20 })
        .onChange((v: string) => { this.topicThresholdInput = v; })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => { this.showThresholdSheet = false; })
        Button('确认')
          .layoutWeight(1)
          .backgroundColor($r('app.color.action_background'))
          .fontColor($r('app.color.action_text'))
          .onClick(() => {
            let n = parseInt(this.topicThresholdInput, 10);
            if (!Number.isFinite(n) || n < 1) { n = 1; }
            if (n > 20) { n = 20; }
            this.topicThreshold = n;
            this.topicThresholdInput = String(n);
            FilterSettingsRepository.setInt(this.context(), FILTER_KEYS.topicThreshold, n);
            this.showThresholdSheet = false;
            promptAction.showToast({ message: `主题屏蔽阈值已设为 ${n}` });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 24 })
    }
    .width('100%')
  }


  // 带齿轮的设置入口行：点击齿轮 / 标题 / 箭头跳转子页（无总开关，仅导航）
  @Builder GearNavRow(title: string, desc: string, subPage: string, showDivider: boolean) {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(title)
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (desc.length > 0) {
            Text(desc)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(this.fontSubhead)
          .fontColor([$r('app.color.text_tertiary')])

        Text('›')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => router.pushUrl({ url: subPage }))

      if (showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder ToggleRow(item: FilterToggleItem, showDivider: boolean) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_primary'))
          if (item.desc.length > 0) {
            Text(item.desc)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.toggleState[item.key] ?? false })
          .selectedColor($r('app.color.action_text'))
          .onChange((isOn: boolean) => {
            this.onToggleChange(item, isOn);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  // 带齿轮的设置入口行：标题+描述 → 齿轮 → 开关 → ›
  // 点击齿轮/标题/箭头跳子页；开关独立控制主开关，互不冒泡
  @Builder ToggleNavRow(item: FilterToggleItem, subPage: string, showDivider: boolean) {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(item.title)
              .fontSize(this.fontBody)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (item.desc.length > 0) {
              Text(item.desc)
                .fontSize(this.fontCaption)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(this.fontSubhead)
            .fontColor([$r('app.color.text_tertiary')])

          Text('›')
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .onClick(() => router.pushUrl({ url: subPage }))

        Toggle({ type: ToggleType.Switch, isOn: this.toggleState[item.key] ?? false })
          .selectedColor($r('app.color.action_text'))
          .onChange((isOn: boolean) => {
            this.onToggleChange(item, isOn);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder AlgoRow() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('推荐算法')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_primary'))
        Text('选择首页推荐内容来源')
          .fontSize(this.fontCaption)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 4 }) {
        Text(this.algoLabel())
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
        Text('›')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_tertiary'))
      }
      .bindMenu(this.algoMenuBuilder)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })
  }

  @Builder ThresholdRow() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('主题屏蔽阈值')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_primary'))
        Text('回答的问题包含 ≥ N 个被屏蔽主题时隐藏')
          .fontSize(this.fontCaption)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 4 }) {
        Text(String(this.topicThreshold))
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
        Text('›')
          .fontSize(this.fontSubhead)
          .fontColor($r('app.color.text_tertiary'))
      }
      .padding({ left: 14, right: 12, top: 8, bottom: 8 })
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(14)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => this.openThresholdDialog())
  }

  @Builder ManageListRow() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text('管理屏蔽列表')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('›')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => router.pushUrl({ url: 'pages/BlocklistManage' }))

      Divider()
        .color($r('app.color.card_border'))
        .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }

  @Builder BlockHistoryRow() {
    Row({ space: 12 }) {
      Text('屏蔽记录')
        .fontSize(this.fontBody)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('›')
        .fontSize(this.fontBody)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => router.pushUrl({ url: 'pages/BlockHistory' }))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '推荐系统与内容过滤' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Scroll() {
        Column({ space: 16 }) {
          SettingsCard({ title: '推荐设置' }) {
            this.AlgoRow()
            ForEach(RECOMMEND_TOGGLES, (item: FilterToggleItem, idx: number) => {
              this.ToggleRow(item, idx < RECOMMEND_TOGGLES.length - 1);
            })
            this.GearNavRow('质量过滤', '按赞同数、关注数等指标过滤低质内容', 'pages/QualityFilterSettings', true)
            this.GearNavRow('推荐次数过滤', '自动过滤展示超 N 次的内容', 'pages/SmartFilterSettings', false)
          }

          SettingsCard({ title: '内容屏蔽' }) {
            ForEach(CONTENT_BLOCK_TOGGLES, (item: FilterToggleItem, idx: number) => {
              this.ToggleRow(item, idx < CONTENT_BLOCK_TOGGLES.length - 1);
            })
          }

          SettingsCard({ title: '屏蔽规则' }) {
            ForEach(RULE_BLOCK_TOGGLES, (item: FilterToggleItem, idx: number) => {
              this.ToggleRow(item, idx < RULE_BLOCK_TOGGLES.length - 1);
            })
            this.ThresholdRow()
          }

          SettingsCard({ title: '管理与统计' }) {
            this.ManageListRow()
            this.BlockHistoryRow()
          }

          Text(`已累计屏蔽 ${this.blockCount} 条内容`)
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.text_secondary'))
            .padding({ top: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topBarHeight })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .bindSheet($$this.showThresholdSheet, this.ThresholdSheet(), {
      showClose: false,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      detents: [300],
      backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
      onDisappear: () => { this.showThresholdSheet = false; }
    })
  }
}
