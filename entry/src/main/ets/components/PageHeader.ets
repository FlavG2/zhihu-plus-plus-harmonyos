import { router } from '@kit.ArkUI';
import { ThemeColors } from '../services/ThemeColors';
import { ZhihuMaterial } from '../services/ZhihuMaterial';

/**
 * 统一顶栏组件（A 类「返回 + 标题」简单栏）。
 *
 * - 圆形返回按钮 + 鸿蒙原生按压光效（ButtonType.Circle + stateEffect），
 *   视觉对齐酷安/系统返回键，比裸 Text('‹') 更精致。
 * - 标题 text_primary，深色 / OLED 下自动跟随主题。
 * - 顶栏底色走 OLED 纯黑逻辑（与全局顶栏统一覆盖范围一致）。
 * - titleSlot / actions 插槽支持搜索框、右侧图标等变体。
 * - rightButtons / rightPill 数据驱动 prop：右侧图标按钮（如 ⋮）与右侧胶囊
 *   （如「关注」），用普通回调数组而非 @BuilderParam 传入，规避跨组件 @Builder
 *   传递导致的 this 绑定崩溃（Search/WebContent 曾因此进页即闪退）。
 *
 * ⚠️ PageHeader 放置三条铁律（2026-09-02 顶栏分色时总结）：
 *   1. 必须是根 Column 的直接子节点，不能塞进 Scroll > Column(padding l16 r16)，
 *      否则栏宽只有 屏宽-32，两侧露父底色 → 顶栏左右颜色不一致。
 *   2. 用它的页面根容器必须有 .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP])，
 *      且根容器不能再加 .padding({top: topSafeAreaVp})（PageHeader 内部已含）→
 *      否则状态栏那条露页面底色 + 栏显矮。
 *   3. Scroll 内 Column 补 .width('100%')。
 *
 * 沉浸光感顶栏（uiMaterial / API 26+，对齐 PiliPlus）：
 *   开关 AppStorage.enableHdsTopBar（设置-外观-沉浸光感-实验）+ 设备能力门
 *   ZhihuMaterial.uiImmersiveAvailable()。两者都通过时走 .systemMaterial()，
 *   否则回退到原 glass_top_bar_background + backdropBlur。
 *   ⚠️ 必须用 if 分支条件渲染：API<26 设备上 .systemMaterial() 不存在，
 *      链式属性方法缺失 try-catch 抓不住，只有 if 分支让代码不走到才能安全。
 */
interface RightButton {
  /** sys.symbol.X 字面符号名（必须字面值，动态拼接不校验） */
  icon: Resource;
  /** 点击回调（与 menu 二选一，menu 优先走 bindMenu） */
  action?: () => void;
  /** 弹出菜单项（如 WebContent 的 ⋮ 菜单），存在时按钮走 bindMenu 而非 onClick */
  menu?: Array<MenuElement>;
}

interface RightPill {
  text: string;
  active: boolean;
  action: () => void;
}

@Component
export struct PageHeader {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('pillRadius') private pillRadius: number = 18;
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('pagePadding') private pagePadding: number = 20;

  @Prop title: string = '';
  @Prop showBack: boolean = true;
  /**
   * 是否在顶部内边距中预留状态栏高度。默认 true（页面根 Column 直接子节点场景）。
   * 当 PageHeader 被放进某个滚动容器、其上方已有 Tab 栏等已处理过状态栏避让的元素时，
   * 调用方应传 false，避免重复累加状态栏高度导致顶栏被压低。
   */
  @Prop safeAreaTop: boolean = true;
  backAction?: () => void;
  @BuilderParam titleSlot?: () => void;
  @BuilderParam actions?: () => void;
  /**
   * 右侧图标按钮（如导出 / 分享）。
   * 用普通回调 prop 而非 @BuilderParam 传入，规避跨组件 @Builder 传递导致的 this 绑定崩溃
   *（Search/WebContent 曾因此进入即闪退）。
   */
  rightAction?: () => void;
  /**
   * 右侧多个图标按钮（如 ⋮ 菜单）。数据驱动，由调用方提供 Resource + 回调。
   * ArkTS 不允许组件字段直接用接口类型作为 @Prop —— 改用普通字段（非装饰器），
   * 调用方传入的 Array 会在每次 build 时被读取（ArkUI 不需要 @Prop 也会触发重渲染，
   * 因为父组件状态变更会重建 PageHeader）。
   */
  rightButtons?: Array<RightButton>;
  /**
   * 右侧胶囊按钮（如「关注」）。同上，普通字段非 @Prop。
   */
  rightPill?: RightPill;

  /**
   * 当前是否走沉浸光感顶栏。计算属性：用户开关 + 设备能力双门控。
   * 写成方法而非 @Computed —— 因为 @StorageLink('enableHdsTopBar') 已能触发重渲染，
   * 每次重建时调用本方法即可拿到最新值。
   */
  private useImmersive(): boolean {
    const enabled = AppStorage.get<boolean>('enableHdsTopBar') ?? false;
    return enabled && ZhihuMaterial.uiImmersiveAvailable();
  }

  build() {
    if (this.useImmersive()) {
      Row() {
        this.BarContent()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        top: (this.safeAreaTop ? this.topSafeAreaVp : 0) + this.spaceMd,
        bottom: this.spaceMd,
        left: this.pagePadding,
        right: this.pagePadding
      })
      .systemMaterial(ZhihuMaterial.uiImmersiveMaterial())
    } else {
      Row() {
        this.BarContent()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        top: (this.safeAreaTop ? this.topSafeAreaVp : 0) + this.spaceMd,
        bottom: this.spaceMd,
        left: this.pagePadding,
        right: this.pagePadding
      })
      .backgroundColor(ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.glass_top_bar_background')))
      .backdropBlur(24)
    }
  }

  /**
   * 顶栏内部内容：返回键 + 标题 + actions 插槽 + rightAction 单按钮
   * + rightButtons 多按钮 + rightPill 胶囊。所有变体共享一份。
   * 抽到 @Builder 后两个分支（沉浸/回退）可复用，避免重复代码。
   */
  @Builder
  private BarContent(): void {
    if (this.showBack) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(this.fontSymbol)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .backgroundColor(this.isDark ? '#1AFFFFFF' : '#0D000000')
      .stateEffect(true)
      .width(36)
      .height(36)
      .margin({ right: 4 })
      .onClick(() => {
        if (this.backAction !== undefined) {
          this.backAction();
        } else {
          router.back();
        }
      })
    }
    if (this.title) {
      Text(this.title)
        .fontSize(this.fontSubhead)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else if (this.titleSlot) {
      Row() {
        this.titleSlot()
      }
      .layoutWeight(1)
    } else {
      // 无标题时占位把右侧内容推到右边
      Blank().layoutWeight(1)
    }
    if (this.actions) {
      this.actions()
    }
    if (this.rightPill) {
      Text(this.rightPill.text)
        .fontSize(this.fontSecondary)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.rightPill.active
          ? $r('app.color.text_secondary')
          : $r('app.color.action_text'))
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .backgroundColor(this.rightPill.active
          ? ThemeColors.cardBackground(this.oledBlack, this.isDark)
          : $r('app.color.action_background'))
        .border({
          width: 1,
          color: this.rightPill.active ? $r('app.color.card_border') : $r('app.color.action_background')
        })
        .borderRadius(this.pillRadius)
        .margin({ left: 4 })
        .onClick(() => {
          if (this.rightPill) {
            this.rightPill.action();
          }
        })
    }
    if (this.rightButtons && this.rightButtons.length > 0) {
      ForEach(this.rightButtons, (btn: RightButton) => {
        this.RightIconButton(btn)
      }, (btn: RightButton, index: number) => `${index}`)
    }
    if (this.rightAction !== undefined) {
      Button() {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(this.fontSymbol)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .backgroundColor(this.isDark ? '#1AFFFFFF' : '#0D000000')
      .stateEffect(true)
      .width(36)
      .height(36)
      .margin({ left: 4 })
      .onClick(() => {
        if (this.rightAction !== undefined) {
          this.rightAction();
        }
      })
    }
  }

  /**
   * 右侧图标按钮（支持两种形态）：
   * - menu 存在：bindMenu 弹出菜单（WebContent ⋮）
   * - 否则：onClick 回调
   * 抽 @Builder 避免 ForEach 内 if/else 重复 Button 属性链。
   */
  @Builder
  private RightIconButton(btn: RightButton): void {
    if (btn.menu !== undefined) {
      Button() {
        SymbolGlyph(btn.icon)
          .fontSize(this.fontSymbol)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .backgroundColor(this.isDark ? '#1AFFFFFF' : '#0D000000')
      .stateEffect(true)
      .width(36)
      .height(36)
      .margin({ left: 4 })
      .bindMenu(btn.menu)
    } else {
      Button() {
        SymbolGlyph(btn.icon)
          .fontSize(this.fontSymbol)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .backgroundColor(this.isDark ? '#1AFFFFFF' : '#0D000000')
      .stateEffect(true)
      .width(36)
      .height(36)
      .margin({ left: 4 })
      .onClick(() => {
        if (btn.action !== undefined) {
          btn.action();
        }
      })
    }
  }
}
