import { router } from '@kit.ArkUI';
import { ThemeColors } from '../services/ThemeColors';
import { ZhihuMaterial } from '../services/ZhihuMaterial';

/**
 * 内容页滚动感知顶栏（Article / Question / Pin 统一复用）。
 *
 * 与 PageHeader 的区别：PageHeader 是「返回 + 标题」的静态栏；本组件是内容页的
 * 悬浮栏，带「标题 / 作者」内容行 + 三点菜单，整条随滚动跟手显隐。三态：
 *   A 紧凑：返回键 + ⋮ 菜单（标题 / 作者隐藏 —— 顶部摘要卡片/问题头可见时，避免重复）
 *   B 展开：返回键 + 标题(+作者) + ⋮（摘要卡片/问题头滚出视野后，contentProgress→1 淡入）
 *   C 隐藏：整条随滚动滑出屏幕顶部（父组件驱动 offsetY → translate）
 *
 * 设计要点：
 * - contentProgress 由父组件按「摘要卡片/问题头滚出」算连续进度(0=紧凑A，1=展开B)：Article/Question 传滚动进度，Pin 传 1。
 *   Pin 传 true（永远展示标题「XX的想法」）。
 * - offsetY 由父组件按 WebView/List 滚动方向累加（0=显示，负=隐藏），本组件只负责 translate。
 * - 返回键 / ⋮ 菜单样式对齐 Article/Pin 现状：圆形返回键 + Text('⋮') 三点。
 * - 沉浸光感：与 PageHeader 同款双门控（AppStorage.enableHdsTopBar + uiImmersiveAvailable），
 *   if 分支条件渲染，低版本设备不触碰 .systemMaterial()。
 * - 高度上报：onHeightChange 回传整条高度（含状态栏），供父组件计算隐藏位移终点。
 */
@Component
export struct ContentTopBar {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontHeading') private fontHeading: string = '20fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('pagePadding') private pagePadding: number = 20;

  /** 标题（问题标题 / 想法标题 / 文章标题）。 */
  @Prop title: string = '';
  /** 作者名（Question 传空，不显示作者）。 */
  @Prop authorName: string = '';
  /** 作者头像 URL（空则用名字首字兜底，名字也空则不显示头像）。 */
  @Prop authorAvatar: string = '';
  /** 顶栏 A→B 标题/作者淡入进度（0=紧凑A，1=展开B），父组件按滚动连续计算。 */
  @Prop contentProgress: number = 0;
  /** 父组件驱动的整条竖向偏移（0=显示，负=隐藏），本组件据此 translate。 */
  @Prop offsetY: number = 0;

  /**
   * 三点菜单项。普通字段非 @Prop（Array<MenuElement> 不能作 @Prop），
   * 父组件每次 build 传入新数组即可被重新读取（与 PageHeader.rightButtons 同套路）。
   */
  menuItems?: Array<MenuElement>;

  onBack?: () => void;
  onTitleClick?: () => void;
  onAuthorClick?: () => void;
  /** 整条高度上报（含状态栏），供父组件计算隐藏位移终点。 */
  onHeightChange?: (height: number) => void;

  private useImmersive(): boolean {
    const enabled = AppStorage.get<boolean>('enableHdsTopBar') ?? false;
    return enabled && ZhihuMaterial.uiImmersiveAvailable();
  }

  private handleBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
    } else {
      router.back();
    }
  }

  build() {
    if (this.useImmersive()) {
      Row() {
        this.BarContent()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        top: this.topSafeAreaVp + this.spaceMd,
        bottom: this.spaceMd,
        left: this.pagePadding,
        right: this.pagePadding
      })
      .systemMaterial(ZhihuMaterial.uiImmersiveMaterial())
      .translate({ y: this.offsetY })
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue.height > 0 && this.onHeightChange !== undefined) {
          this.onHeightChange(Number(newValue.height));
        }
      })
    } else {
      Row() {
        this.BarContent()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        top: this.topSafeAreaVp + this.spaceMd,
        bottom: this.spaceMd,
        left: this.pagePadding,
        right: this.pagePadding
      })
      .backgroundColor(ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.glass_top_bar_background')))
      .backdropBlur(24)
      .translate({ y: this.offsetY })
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue.height > 0 && this.onHeightChange !== undefined) {
          this.onHeightChange(Number(newValue.height));
        }
      })
    }
  }

  @Builder
  private BarContent(): void {
    // 返回键（常驻圆形键）
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
      this.handleBack();
    })

    // 内容行（标题 + 作者）：随 contentProgress 0→1 淡入；紧凑态(A)=0 时完全透明且不可点，但保留 layoutWeight 把 ⋮ 顶到右侧
    Column() {
      this.ContentRow()
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .opacity(this.contentProgress)
    .visibility(this.contentProgress > 0.01 ? Visibility.Visible : Visibility.Hidden)

    // 三点菜单（对齐 Article/Pin 现状：裸 Text('⋮') + bindMenu）
    if (this.menuItems !== undefined && this.menuItems.length > 0) {
      Text('⋮')
        .fontSize(this.fontHeading)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .bindMenu(this.menuItems)
    }
  }

  @Builder
  private ContentRow(): void {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(this.fontBody)
        .fontWeight(FontWeight.Medium)
        .lineHeight(20)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          if (this.onTitleClick !== undefined) {
            this.onTitleClick();
          }
        })

      if (this.authorAvatar.length > 0) {
        Image(this.authorAvatar)
          .width(28)
          .height(28)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.cardRadius)
          .onClick(() => {
            if (this.onAuthorClick !== undefined) {
              this.onAuthorClick();
            }
          })
      } else if (this.authorName.length > 0) {
        Column() {
          Text(this.authorName.slice(0, 1))
            .fontSize(this.fontCaption)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.action_text'))
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.action_background'))
        .borderRadius(this.cardRadius)
        .onClick(() => {
          if (this.onAuthorClick !== undefined) {
            this.onAuthorClick();
          }
        })
      }

      if (this.authorName.length > 0) {
        Text(this.authorName)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 120 })
          .onClick(() => {
            if (this.onAuthorClick !== undefined) {
              this.onAuthorClick();
            }
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
