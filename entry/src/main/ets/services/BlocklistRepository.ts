import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

// 屏蔽项模型（对齐安卓 BlockedKeyword / BlockedUser / BlockedQuestionAuthor / BlockedTopic）
export interface BlockedKeyword {
  text: string;
  isRegex: boolean;
  caseSensitive: boolean;
}

export interface BlockedUser {
  id: string;
  name: string;
  urlToken: string;
}

export interface BlockedQuestionAuthor {
  id: string;
  name: string;
}

export interface BlockedTopic {
  id: string;
  name: string;
}

const FILE_NAME: string = 'zhihu_blocklist';
const KEY_KEYWORDS: string = 'blocked_keywords';
const KEY_USERS: string = 'blocked_users';
const KEY_QA: string = 'blocked_question_authors';
const KEY_TOPICS: string = 'blocked_topics';

export class BlocklistRepository {
  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: FILE_NAME });
  }

  // ---- 关键词 ----
  static getKeywords(context: common.Context): BlockedKeyword[] {
    const raw = this.store(context).getSync(KEY_KEYWORDS, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as BlockedKeyword[];
    } catch (e) {
      return [];
    }
  }

  static addKeyword(context: common.Context, kw: BlockedKeyword): void {
    const list = this.getKeywords(context);
    if (list.some((k) => k.text === kw.text && k.isRegex === kw.isRegex)) {
      return;
    }
    list.push(kw);
    const store = this.store(context);
    store.putSync(KEY_KEYWORDS, JSON.stringify(list));
    store.flushSync();
  }

  static removeKeyword(context: common.Context, text: string): void {
    const list = this.getKeywords(context).filter((k) => k.text !== text);
    const store = this.store(context);
    store.putSync(KEY_KEYWORDS, JSON.stringify(list));
    store.flushSync();
  }

  // ---- 用户 ----
  static getUsers(context: common.Context): BlockedUser[] {
    const raw = this.store(context).getSync(KEY_USERS, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as BlockedUser[];
    } catch (e) {
      return [];
    }
  }

  static addUser(context: common.Context, user: BlockedUser): void {
    const list = this.getUsers(context);
    const exists = user.id.length > 0
      ? list.some((u) => u.id === user.id)
      : list.some((u) => u.name === user.name);
    if (exists) {
      return;
    }
    list.push(user);
    const store = this.store(context);
    store.putSync(KEY_USERS, JSON.stringify(list));
    store.flushSync();
  }

  static removeUser(context: common.Context, id: string): void {
    const list = this.getUsers(context).filter((u) => u.id !== id);
    const store = this.store(context);
    store.putSync(KEY_USERS, JSON.stringify(list));
    store.flushSync();
  }

  // ---- 提问者 ----
  static getQuestionAuthors(context: common.Context): BlockedQuestionAuthor[] {
    const raw = this.store(context).getSync(KEY_QA, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as BlockedQuestionAuthor[];
    } catch (e) {
      return [];
    }
  }

  static addQuestionAuthor(context: common.Context, qa: BlockedQuestionAuthor): void {
    const list = this.getQuestionAuthors(context);
    const exists = qa.id.length > 0
      ? list.some((x) => x.id === qa.id)
      : list.some((x) => x.name === qa.name);
    if (exists) {
      return;
    }
    list.push(qa);
    const store = this.store(context);
    store.putSync(KEY_QA, JSON.stringify(list));
    store.flushSync();
  }

  static removeQuestionAuthor(context: common.Context, id: string): void {
    const list = this.getQuestionAuthors(context).filter((x) => x.id !== id);
    const store = this.store(context);
    store.putSync(KEY_QA, JSON.stringify(list));
    store.flushSync();
  }

  // ---- 查询 / 切换（主页展示本地屏蔽态，对齐安卓 isUserBlocked / isQuestionAuthorBlocked）----
  static isUserBlocked(context: common.Context, id: string): boolean {
    if (id.length === 0) {
      return false;
    }
    return this.getUsers(context).some((u) => u.id === id);
  }

  static isQuestionAuthorBlocked(context: common.Context, id: string): boolean {
    if (id.length === 0) {
      return false;
    }
    return this.getQuestionAuthors(context).some((x) => x.id === id);
  }

  // 切换用户屏蔽，返回切换后是否屏蔽
  static toggleUserBlock(context: common.Context, user: BlockedUser): boolean {
    if (user.id.length === 0) {
      return false;
    }
    if (this.isUserBlocked(context, user.id)) {
      this.removeUser(context, user.id);
      return false;
    }
    this.addUser(context, user);
    return true;
  }

  // 切换提问者屏蔽，返回切换后是否屏蔽
  static toggleQuestionAuthorBlock(context: common.Context, qa: BlockedQuestionAuthor): boolean {
    if (qa.id.length === 0) {
      return false;
    }
    if (this.isQuestionAuthorBlocked(context, qa.id)) {
      this.removeQuestionAuthor(context, qa.id);
      return false;
    }
    this.addQuestionAuthor(context, qa);
    return true;
  }

  // ---- 话题 ----
  static getTopics(context: common.Context): BlockedTopic[] {
    const raw = this.store(context).getSync(KEY_TOPICS, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as BlockedTopic[];
    } catch (e) {
      return [];
    }
  }

  static addTopic(context: common.Context, topic: BlockedTopic): void {
    const list = this.getTopics(context);
    if (list.some((t) => t.id === topic.id)) {
      return;
    }
    list.push(topic);
    const store = this.store(context);
    store.putSync(KEY_TOPICS, JSON.stringify(list));
    store.flushSync();
  }

  static removeTopic(context: common.Context, id: string): void {
    const list = this.getTopics(context).filter((t) => t.id !== id);
    const store = this.store(context);
    store.putSync(KEY_TOPICS, JSON.stringify(list));
    store.flushSync();
  }

  static clearAll(context: common.Context): void {
    const store = this.store(context);
    [KEY_KEYWORDS, KEY_USERS, KEY_QA, KEY_TOPICS].forEach((k) => {
      store.deleteSync(k);
    });
    store.flushSync();
  }
}
