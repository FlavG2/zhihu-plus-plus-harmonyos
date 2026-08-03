import os

BASE = r'E:\zhihu-src\zhihu-plus-plus-next-main\entry\src\main\ets'

files = {
    'pages/Index.ets': 'feed',
    'pages/Article.ets': 'article',
    'pages/Question.ets': 'feed',
    'components/ZhihuRichWeb.ets': 'article',
}

PB = "$r('app.color.page_background')"
CB = "$r('app.color.card_background')"

for rel, kind in files.items():
    path = os.path.join(BASE, rel)
    with open(path, 'r', encoding='utf-8') as f:
        s = f.read()
    pg_func = 'ThemeColors.feedBackground' if kind == 'feed' else 'ThemeColors.articleBackground'
    before = s.count(PB) + s.count(CB)
    s = s.replace(PB, f"{pg_func}(this.oledBlack, this.isDark)")
    s = s.replace(CB, "ThemeColors.cardBackground(this.oledBlack, this.isDark)")
    after = s.count("$r('app.color.page_background')") + s.count("$r('app.color.card_background')")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)
    print(f'processed {rel}: replaced {before} occurrences, remaining raw {after}')
