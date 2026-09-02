import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { ZhihuIdentityClient, ZhihuIdentityAccount } from '../services/ZhihuIdentityClient';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct IdentityManagementPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @State topBarHeight: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageProp('fontBody') fontBody: string = '16fp';
  @StorageProp('fontCaption') fontCaption: string = '12fp';
  @StorageProp('fontSecondary') fontSecondary: string = '14fp';
  @StorageProp('fontSubhead') fontSubhead: string = '18fp';
  @StorageProp('fontMeta') fontMeta: string = '13fp';

  @State private accounts: ZhihuIdentityAccount[] = [];
  @State private currentAccountId: string = '';
  @State private loading: boolean = false;
  @State private switchingToAccountId: string | null = null;
  @State private creating: boolean = false;
  @State private errorMessage: string | null = null;
  @State private switchTarget: ZhihuIdentityAccount | null = null;
  @State private showCreateDialog: boolean = false;
  @State private acceptedCreateRules: boolean = false;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private isBusy(): boolean {
    return this.loading || this.switchingToAccountId !== null || this.creating;
  }

  private canCreateSubAccount(): boolean {
    return this.accounts.length < 2 &&
      this.accounts.some((a: ZhihuIdentityAccount) => a.canCreateSubAccount && a.subAccountControlStatus === 0);
  }

  private accountTypeLabel(type: number): string {
    if (type === 1) {
      return '主账号';
    }
    if (type === 2) {
      return '马甲号';
    }
    return '知乎账号';
  }

  aboutToAppear(): void {
    const self = ZhihuSessionRepository.load(this.context()).self;
    this.currentAccountId = self?.id ?? '';
    this.refresh();
  }

  private async refresh(): Promise<void> {
    if (this.switchingToAccountId !== null || this.creating) {
      return;
    }
    this.loading = true;
    this.errorMessage = null;
    try {
      const client = new ZhihuIdentityClient(this.context());
      const accounts = await client.listAccounts();
      this.accounts = accounts;
      this.currentAccountId = ZhihuSessionRepository.load(this.context()).self?.id ?? '';
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '获取身份列表失败';
    } finally {
      this.loading = false;
    }
  }

  private async doSwitch(target: ZhihuIdentityAccount): Promise<void> {
    if (this.isBusy()) {
      return;
    }
    this.switchingToAccountId = target.id;
    this.errorMessage = null;
    try {
      const client = new ZhihuIdentityClient(this.context());
      const result = await client.switchAccount(target.id);
      this.currentAccountId = result.account.id;
      promptAction.showToast({ message: `已切换到 ${result.account.name}` });
      router.back();
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '切换账号失败';
    } finally {
      this.switchingToAccountId = null;
    }
  }

  private async doCreate(): Promise<void> {
    if (this.isBusy()) {
      return;
    }
    if (!this.canCreateSubAccount()) {
      promptAction.showToast({ message: '当前账号暂不能创建新账号' });
      return;
    }
    this.creating = true;
    this.errorMessage = null;
    try {
      const client = new ZhihuIdentityClient(this.context());
      const result = await client.createSubAccount();
      this.accounts = [...this.accounts, result.account];
      this.currentAccountId = result.account.id;
      promptAction.showToast({ message: '新账号已创建并初始化，正在返回首页' });
      router.back();
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '创建新账号失败';
    } finally {
      this.creating = false;
    }
  }


  @Builder
  private AccountRow(account: ZhihuIdentityAccount): void {
    Row({ space: 12 }) {
      if (account.avatarUrl.length > 0) {
        Image(account.avatarUrl)
          .width(40)
          .height(40)
          .objectFit(ImageFit.Cover)
          .borderRadius(20)
          .clip(true)
      } else {
        Column() {
          Text(account.name.slice(0, 1))
            .fontSize(this.fontBody)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.action_text'))
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.action_background'))
        .borderRadius(20)
      }

      Column({ space: 4 }) {
        Text(account.name)
          .fontSize(this.fontBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.accountTypeLabel(account.accountType))
          .fontSize(this.fontCaption)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        if (account.id === this.currentAccountId) {
          Text('当前登录')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.action_text'))
        } else if (account.id === this.switchingToAccountId) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.action_text'))
        } else {
          Text('切换')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.action_text'))
        }
      }
      .constraintSize({ minWidth: 56 })
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(20)
    .onClick(() => {
      if (account.id !== this.currentAccountId && !this.isBusy()) {
        this.switchTarget = account;
      }
    })
  }

  @Builder
  private SwitchDialog(): void {
    Column() {
      Column({ space: 16 }) {
        Text('切换账号')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(`将切换到「${this.switchTarget?.name ?? ''}」。切换后首页会重新加载，之后的推荐、内容和互动都属于该账号。`)
          .fontSize(this.fontSecondary)
          .lineHeight(22)
          .fontColor($r('app.color.text_secondary'))

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(12)
            .onClick(() => {
              if (!this.isBusy()) {
                this.switchTarget = null;
              }
            })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('切换')
            .fontSize(this.fontBody)
            .fontColor('#FFFFFFFF')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor($r('app.color.action_text'))
            .borderRadius(12)
            .opacity(this.isBusy() ? 0.5 : 1)
            .onClick(() => {
              if (!this.isBusy() && this.switchTarget !== null) {
                const target = this.switchTarget;
                this.switchTarget = null;
                this.doSwitch(target);
              }
            })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
      }
      .padding(20)
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({ width: 1, color: $r('app.color.card_border') })
      .borderRadius(24)
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (!this.isBusy()) {
        this.switchTarget = null;
      }
    })
  }

  @Builder
  private CreateDialog(): void {
    Column() {
      Column({ space: 16 }) {
        Text('新账号使用规则')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(
          '您即将创建的新账号，与当前账号共用同一手机号，为两个相互独立的账号身份。' +
          '新账号拥有独立的昵称、头像与个人主页，账号之间的内容、数据、互动行为完全隔离。' +
          '两个账号均需遵守社区规范与用户协议，任一账号存在违规行为，可能影响同一手机号下其他账号的使用权限。'
        )
          .fontSize(this.fontSecondary)
          .lineHeight(22)
          .fontColor($r('app.color.text_secondary'))

        Row({ space: 8 }) {
          Checkbox()
            .select(this.acceptedCreateRules)
            .onChange((v: boolean) => {
              this.acceptedCreateRules = v;
            })
          Text('我已知悉创建机会有限，创建后将立即切换')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('取消')
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(12)
            .onClick(() => {
              if (!this.isBusy()) {
                this.showCreateDialog = false;
              }
            })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('同意并创建')
            .fontSize(this.fontBody)
            .fontColor(this.canCreateSubAccount() && !this.isBusy() ? '#FFFFFFFF' : $r('app.color.text_secondary'))
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(this.canCreateSubAccount() && !this.isBusy() ? $r('app.color.action_text') : $r('app.color.card_border'))
            .borderRadius(12)
            .opacity(this.canCreateSubAccount() && !this.isBusy() ? 1 : 0.5)
            .onClick(() => {
              if (this.acceptedCreateRules && this.canCreateSubAccount() && !this.isBusy()) {
                this.showCreateDialog = false;
                this.doCreate();
              }
            })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
      }
      .padding(20)
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({ width: 1, color: $r('app.color.card_border') })
      .borderRadius(24)
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (!this.isBusy()) {
        this.showCreateDialog = false;
      }
    })
  }

  build() {
    Stack() {
      Stack({ alignContent: Alignment.Top }) {
        PageHeader({ title: '身份管理' })
          .zIndex(2)
          .onAreaChange((_old: Area, newValue: Area) => {
            if (newValue.height > 0) {
              this.topBarHeight = Number(newValue.height);
            }
          })

        Scroll() {
          Column({ space: 16 }) {
            // 加载失败提示
            if (this.errorMessage !== null) {
              Column({ space: 8 }) {
                Text('加载失败')
                  .fontSize(this.fontBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(this.errorMessage ?? '')
                  .fontSize(this.fontMeta)
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding(16)
              .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
              .border({ width: 1, color: $r('app.color.card_border') })
              .borderRadius(20)
              .onClick(() => {
                this.refresh();
              })
            }

            // 初次加载中
            if (this.loading && this.accounts.length === 0) {
              Column() {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color($r('app.color.action_text'))
              }
              .width('100%')
              .height(160)
              .justifyContent(FlexAlign.Center)
            }

            // 账号列表
            if (this.accounts.length > 0) {
              Column({ space: 4 }) {
                Text('当前手机号下的账号')
                  .fontSize(this.fontMeta)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 4 })
                Text('两个账号共用当前手机号，但昵称、主页、内容、推荐和互动数据相互独立。')
                  .fontSize(this.fontCaption)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 4, bottom: 4 })

                Column({ space: 2 }) {
                  ForEach(this.accounts, (account: ZhihuIdentityAccount) => {
                    this.AccountRow(account);
                  }, (account: ZhihuIdentityAccount) => account.id)
                }
                .width('100%')
                .padding(6)
                .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
                .border({ width: 1, color: $r('app.color.card_border') })
                .borderRadius(24)
              }
              .width('100%')
            } else if (!this.loading && this.errorMessage === null) {
              Column({ space: 8 }) {
                Text('未找到可管理的账号')
                  .fontSize(this.fontBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('请确认当前登录状态后重试')
                  .fontSize(this.fontMeta)
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding(16)
              .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
              .border({ width: 1, color: $r('app.color.card_border') })
              .borderRadius(20)
            }

            // 新账号
            if (this.accounts.length > 0) {
              Column({ space: 4 }) {
                Text('新账号')
                  .fontSize(this.fontMeta)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 4 })
                Text(
                  this.canCreateSubAccount()
                    ? '新账号会先使用系统昵称完成初始化。昵称修改受知乎次数限制，本客户端不会自动改名。'
                    : (this.accounts.length >= 2
                      ? '当前手机号下已经存在主账号和马甲号。'
                      : '当前登录账号暂不满足创建新账号的条件。')
                )
                  .fontSize(this.fontCaption)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 4, bottom: 4 })

                Column({ space: 2 }) {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text('创建新账号')
                        .fontSize(this.fontBody)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                      Text('共用当前手机号，数据相互独立')
                        .fontSize(this.fontCaption)
                        .lineHeight(18)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (this.creating) {
                      LoadingProgress()
                        .width(20)
                        .height(20)
                        .color($r('app.color.action_text'))
                    }
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 16, bottom: 16 })
                  .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
                  .border({ width: 1, color: $r('app.color.card_border') })
                  .borderRadius(20)
                  .opacity(this.canCreateSubAccount() && !this.isBusy() ? 1 : 0.5)
                  .onClick(() => {
                    this.acceptedCreateRules = false;
                    this.showCreateDialog = true;
                  })
                }
                .width('100%')
                .padding(6)
                .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
                .border({ width: 1, color: $r('app.color.card_border') })
                .borderRadius(24)
              }
              .width('100%')
            }
          }
          .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topBarHeight })
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      if (this.switchTarget !== null) {
        this.SwitchDialog();
      }
      if (this.showCreateDialog) {
        this.CreateDialog();
      }
    }
    .width('100%')
    .height('100%')
  }
}
