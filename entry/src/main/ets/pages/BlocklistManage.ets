import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import {
  BlocklistRepository,
  BlockedKeyword,
  BlockedUser,
  BlockedQuestionAuthor,
  BlockedTopic
} from '../services/BlocklistRepository';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

type BlockKind = 'keyword' | 'user' | 'questionAuthor' | 'topic';

@Entry
@Component
struct BlocklistManagePage {
  @State keywords: BlockedKeyword[] = [];
  @State users: BlockedUser[] = [];
  @State questionAuthors: BlockedQuestionAuthor[] = [];
  @State topics: BlockedTopic[] = [];
  // 折叠状态（默认收起）
  @State keywordExpanded: boolean = false;
  @State userExpanded: boolean = false;
  @State questionAuthorExpanded: boolean = false;
  @State topicExpanded: boolean = false;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @State topBarHeight: number = 0;
  @StorageProp('fontSecondary') fontSecondary: string = '14fp';
  @StorageProp('fontMeta') fontMeta: string = '13fp';
  @StorageProp('fontBodySm') fontBodySm: string = '15fp';

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    const ctx = this.context();
    this.keywords = BlocklistRepository.getKeywords(ctx);
    this.users = BlocklistRepository.getUsers(ctx);
    this.questionAuthors = BlocklistRepository.getQuestionAuthors(ctx);
    this.topics = BlocklistRepository.getTopics(ctx);
  }

  private removeItem(kind: BlockKind, idOrText: string): void {
    const ctx = this.context();
    if (kind === 'keyword') {
      BlocklistRepository.removeKeyword(ctx, idOrText);
    } else if (kind === 'user') {
      BlocklistRepository.removeUser(ctx, idOrText);
    } else if (kind === 'questionAuthor') {
      BlocklistRepository.removeQuestionAuthor(ctx, idOrText);
    } else {
      BlocklistRepository.removeTopic(ctx, idOrText);
    }
    this.reload();
  }


  @Builder
  ItemRow(name: string, kind: BlockKind, idOrText: string) {
    Row() {
      Text(name)
        .fontSize(this.fontSecondary)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('删除')
        .fontSize(this.fontMeta)
        .fontColor($r('app.color.error_text'))
        .padding({ left: 12, right: 4 })
        .onClick(() => {
          this.removeItem(kind, idOrText);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  EmptyRow(hint: string) {
    Text(hint)
      .fontSize(this.fontMeta)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
  }

  // ── 屏蔽关键词（可折叠）────────────────────────────────
  @Builder
  KeywordSection() {
    Column({ space: 10 }) {
      Row() {
        Text('屏蔽关键词')
          .fontSize(this.fontBodySm)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.keywords.length}`)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.keywordExpanded ? '▾' : '▸')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.keywordExpanded = !this.keywordExpanded; })

      if (this.keywordExpanded) {
        if (this.keywords.length === 0) {
          this.EmptyRow('在内容卡片菜单中选择「按关键词屏蔽」后会出现在这里');
        } else {
          ForEach(this.keywords, (kw: BlockedKeyword) => {
            this.ItemRow(kw.text + (kw.isRegex ? '（正则）' : ''), 'keyword', kw.text);
          }, (kw: BlockedKeyword) => kw.text + (kw.isRegex ? '_re' : ''))
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(20)
  }

  // ── 屏蔽用户（可折叠）────────────────────────────────
  @Builder
  UserSection() {
    Column({ space: 10 }) {
      Row() {
        Text('屏蔽用户')
          .fontSize(this.fontBodySm)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.users.length}`)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.userExpanded ? '▾' : '▸')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.userExpanded = !this.userExpanded; })

      if (this.userExpanded) {
        if (this.users.length === 0) {
          this.EmptyRow('在内容卡片菜单中选择「屏蔽用户」后会出现在这里');
        } else {
          ForEach(this.users, (u: BlockedUser) => {
            this.ItemRow(u.name.length > 0 ? u.name : (u.urlToken.length > 0 ? u.urlToken : u.id), 'user',
              u.id.length > 0 ? u.id : u.urlToken);
          }, (u: BlockedUser) => u.id.length > 0 ? u.id : u.urlToken)
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(20)
  }

  // ── 屏蔽提问者（可折叠）──────────────────────────────
  @Builder
  QuestionAuthorSection() {
    Column({ space: 10 }) {
      Row() {
        Text('屏蔽提问者')
          .fontSize(this.fontBodySm)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.questionAuthors.length}`)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.questionAuthorExpanded ? '▾' : '▸')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.questionAuthorExpanded = !this.questionAuthorExpanded; })

      if (this.questionAuthorExpanded) {
        if (this.questionAuthors.length === 0) {
          this.EmptyRow('在回答卡片菜单中选择「屏蔽提问者」后会出现在这里');
        } else {
          ForEach(this.questionAuthors, (qa: BlockedQuestionAuthor) => {
            this.ItemRow(qa.name.length > 0 ? qa.name : qa.id, 'questionAuthor', qa.id);
          }, (qa: BlockedQuestionAuthor) => qa.id)
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(20)
  }

  // ── 屏蔽话题（可折叠）────────────────────────────────
  @Builder
  TopicSection() {
    Column({ space: 10 }) {
      Row() {
        Text('屏蔽话题')
          .fontSize(this.fontBodySm)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.topics.length}`)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.topicExpanded ? '▾' : '▸')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.topicExpanded = !this.topicExpanded; })

      if (this.topicExpanded) {
        if (this.topics.length === 0) {
          this.EmptyRow('在内容卡片菜单中选择「按话题屏蔽」后会出现在这里');
        } else {
          ForEach(this.topics, (t: BlockedTopic) => {
            this.ItemRow(t.name.length > 0 ? t.name : ('#' + t.id), 'topic', t.id);
          }, (t: BlockedTopic) => t.id)
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(20)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '管理屏蔽列表' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })
      Scroll() {
        Column({ space: 16 }) {
          this.KeywordSection()
          this.UserSection()
          this.QuestionAuthorSection()
          this.TopicSection()
        }
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
  }
}
